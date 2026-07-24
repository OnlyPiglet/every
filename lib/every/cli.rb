module Every
  class CLI
    # Bounded so the generated unit filename (com.every.<name>.plist /
    # every-<name>.timer) stays under the 255-byte filesystem limit.
    MAX_NAME = 100

    def initialize(argv)
      @argv = argv
    end

    def run
      case @argv.first
      when nil, "help", "-h", "--help"   then help
      when "version", "--version"        then version
      when "list", "ls"                  then list
      when "log"                         then log
      when "rm", "remove"                then rm(@argv[1])
      when "pause"                       then pause(@argv[1])
      when "resume"                      then resume(@argv[1])
      when "doctor"                      then Doctor.run
      when "run"                         then Runner.run(@argv[1] || usage!("run <name>"))
      else                                    add(@argv)
      end
    rescue ArgumentError => e
      warn "every: #{e.message}"
      warn "see: every help"
      exit 64
    rescue => e
      # Any other failure prints a clean line, never a raw backtrace.
      # (SystemExit/Interrupt aren't StandardError, so they pass through.)
      warn "every: #{e.message} (#{e.class})"
      exit 1
    end

    # ---- add: every <schedule> [--name NAME] -- <command> ----

    def add(argv)
      sep = argv.index("--")
      raise ArgumentError, "expected: every <schedule> -- <command>" unless sep

      pre = argv[0...sep]
      cmd_tokens = argv[(sep + 1)..-1] || []
      raise ArgumentError, "missing command after --" if cmd_tokens.empty?

      pre, explicit_name = extract_value_flag(pre, "--name")
      pre, timeout_raw = extract_value_flag(pre, "--timeout")
      quiet = !pre.delete("--quiet").nil?
      timeout = timeout_raw && parse_duration(timeout_raw)

      schedule = Schedule.parse(pre)
      # One token = a shell command line (verbatim, so pipes/globs/vars work).
      # Multiple tokens = argv, escaped so quoted args with spaces or shell
      # metacharacters aren't re-split or re-expanded by the login shell.
      cmd = cmd_tokens.length == 1 ? cmd_tokens[0] : Shellwords.join(cmd_tokens)
      store = Store.load

      if explicit_name
        name = sanitize(explicit_name)
        if name.empty?
          raise ArgumentError, "--name #{explicit_name.inspect} is empty after sanitizing " \
                               "(names allow a-z 0-9 . _ -)"
        end
        if name.length > MAX_NAME
          raise ArgumentError, "--name is too long (max #{MAX_NAME} chars)"
        end
        if store[name]
          raise ArgumentError,
                "task #{name.inspect} already exists (every rm #{name}, or pick another --name)"
        end
      else
        name = derive_name(cmd, store)
      end

      attrs = { "cmd" => cmd,
                "schedule" => schedule.to_h,
                "cwd" => Dir.pwd,
                "created_at" => Time.now.iso8601,
                "paused" => false,
                "quiet" => quiet }
      attrs["timeout"] = timeout if timeout
      store.add(name, attrs)
      Runtime.ensure!
      FileUtils.mkdir_p(LOG_DIR)   # so launchd's _agent.log redirect can open on the first fire
      backend.write(name, schedule)
      backend.enable(name)

      puts "✓ scheduled #{name}: #{schedule.raw} — #{cmd}"
      nxt = schedule.next_run
      puts "  next run: #{nxt.strftime('%a %d %b %H:%M')}" if nxt
      puts "  runs every #{schedule.human_interval} while the Mac is awake" if schedule.interval
      puts "  logs:     every log #{name}"
    end

    # ---- list ----

    def list
      store = Store.load
      if store.tasks.empty?
        puts "no tasks yet — try: every day 9am -- brew update"
        return
      end

      rows = store.tasks.map do |name, t|
        sched = Schedule.from_h(t["schedule"])
        last = store.last_run(name)
        lt = last && safe_time(last["ts"])
        last_s = lt ? lt.strftime("%d %b %H:%M") : "—"
        status =
          if t["paused"]          then "paused"
          elsif last.nil?         then "·"
          elsif last["exit"] == 0 then "ok"
          else                         "FAIL(#{last['exit']})"
          end
        [name, sched.raw, last_s, status, next_str(t, sched, last)]
      end

      headers = %w[NAME SCHEDULE LAST STATUS NEXT]
      widths = headers.each_with_index.map do |h, i|
        [h.length, rows.map { |r| r[i].to_s.length }.max || 0].max
      end
      print_row(headers, widths)
      rows.each { |r| print_row(r, widths, colorize: true) }
    end

    def next_str(task, sched, last)
      return "—" if task["paused"]
      if sched.interval
        lt = last && safe_time(last["ts"])
        return "soon" unless lt
        (lt + sched.interval).strftime("%d %b %H:%M")
      else
        sched.next_run.strftime("%d %b %H:%M")
      end
    end

    def print_row(cells, widths, colorize: false)
      out = cells.each_with_index.map { |c, i| c.to_s.ljust(widths[i]) }.join("  ")
      if colorize && $stdout.tty?
        out = out.sub(/\bok\b/, "\e[32mok\e[0m")
        out = out.sub(/\bFAIL\(\d+\)/) { |m| "\e[31m#{m}\e[0m" }
      end
      puts out
    end

    # ---- log / rm / pause / resume ----

    def log
      args = @argv[1..-1] || []
      n = 40
      if (i = args.index("-n"))
        n = args[i + 1].to_i
        n = 40 if n <= 0
        args = args[0...i] + (args[(i + 2)..-1] || [])
      end
      name = args.first
      usage!("log <name> [-n N]") unless name
      path = File.join(LOG_DIR, "#{name}.log")
      unless File.exist?(path)
        warn "every: no logs yet for #{name.inspect} (has it run? check: every list)"
        exit 1
      end
      puts File.readlines(path).last(n).join
    end

    def rm(name)
      usage!("rm <name>") unless name
      store = Store.load
      unless store[name]
        warn "every: no task #{name.inspect}"
        exit 1
      end
      backend.disable(name)
      backend.delete_units(name)
      store.remove(name)
      puts "✓ removed #{name} (logs kept in #{LOG_DIR})"
    end

    def pause(name)
      usage!("pause <name>") unless name
      store = Store.load
      unless store[name]
        warn "every: no task #{name.inspect}"
        exit 1
      end
      backend.disable(name)
      store.update(name, "paused" => true)
      puts "✓ paused #{name}"
    end

    def resume(name)
      usage!("resume <name>") unless name
      store = Store.load
      task = store[name]
      unless task
        warn "every: no task #{name.inspect}"
        exit 1
      end
      Runtime.ensure!
      backend.write(name, Schedule.from_h(task["schedule"]))
      backend.enable(name)
      store.update(name, "paused" => false)
      puts "✓ resumed #{name}"
    end

    # ---- helpers ----

    def derive_name(cmd, store)
      base = sanitize(File.basename(cmd.strip.split(/\s+/).first.to_s))[0, MAX_NAME].to_s
      base = "task" if base.empty?
      name = base
      i = 2
      while store[name]
        suffix = "-#{i}"
        name = base[0, MAX_NAME - suffix.length] + suffix
        i += 1
      end
      name
    end

    def sanitize(s)
      s = s.to_s.downcase.gsub(/[^a-z0-9_.-]/, "-").gsub(/\A-+|-+\z/, "")
      s =~ /\A\.+\z/ ? "" : s   # "." / ".." are not usable filenames
    end

    def parse_duration(raw)
      m = raw.to_s.match(/\A(\d+)(s|m|h)\z/)
      raise ArgumentError, "bad duration #{raw.inspect} (e.g. 90s, 30m, 2h)" unless m
      secs = m[1].to_i * { "s" => 1, "m" => 60, "h" => 3600 }[m[2]]
      raise ArgumentError, "--timeout must be greater than 0" if secs.zero?
      secs
    end

    # Pull `--flag value` or `--flag=value` out of the tokens. Rejects a missing
    # value or a value that is itself a flag (so `--name --quiet` can't silently
    # name the task "quiet" and swallow the flag).
    def extract_value_flag(tokens, flag)
      if (i = tokens.index(flag))
        value = tokens[i + 1]
        if value.nil? || value.start_with?("--")
          raise ArgumentError, "#{flag} needs a value"
        end
        return [tokens[0...i] + (tokens[(i + 2)..-1] || []), value]
      end
      if (i = tokens.index { |t| t.start_with?("#{flag}=") })
        value = tokens[i].split("=", 2)[1].to_s
        raise ArgumentError, "#{flag} needs a value" if value.empty?
        return [tokens[0...i] + (tokens[(i + 1)..-1] || []), value]
      end
      [tokens, nil]
    end

    def safe_time(str)
      Time.parse(str.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def backend
      Backend.current
    end

    def usage!(msg)
      warn "usage: every #{msg}"
      exit 64
    end

    def version
      puts "every #{VERSION}"
      puts TAGLINE
      puts HOMEPAGE
    end

    def help
      puts <<~TXT
        every #{VERSION} — #{TAGLINE}
        #{HOMEPAGE}

        schedule anything on your Mac, humanely

        add a task:
          every 15m -- ~/bin/sync-notes.sh
          every hourly -- brew update
          every day 9am,6pm -- ruby ~/bin/report.rb
          every weekdays 9:30 -- ~/bin/standup-prep.sh
          every monday,thursday 10:00 --name reports -- ~/bin/weekly.sh

          Flags: --name NAME, --quiet (no failure notification),
                 --timeout 30m (kill a run that overruns, so it can't block
                 the next one).
          The command runs through your login shell (PATH works), in the
          directory where you added it. Missed calendar runs fire on wake.
          Failed runs pop a macOS notification unless --quiet.

        manage:
          every list                what's scheduled, last/next run, ok/FAIL
          every log <name> [-n N]   output of recent runs
          every run <name>          run it right now (prints output, logs too)
          every pause <name>        stop scheduling (keeps the task)
          every resume <name>       start again
          every rm <name>           remove task (logs are kept)
          every doctor              explain why something isn't running

        data:  #{DATA_DIR}
        more:  #{HOMEPAGE}
      TXT
    end
  end
end
