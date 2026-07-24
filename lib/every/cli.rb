module Every
  class CLI
    def initialize(argv)
      @argv = argv
    end

    def run
      case @argv.first
      when nil, "help", "-h", "--help"   then help
      when "version", "--version"        then puts "every #{VERSION}"
      when "list", "ls"                  then list
      when "log"                         then log(@argv[1])
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
    end

    # ---- add: every <schedule> [--name NAME] -- <command> ----

    def add(argv)
      sep = argv.index("--")
      raise ArgumentError, "expected: every <schedule> -- <command>" unless sep

      pre = argv[0...sep]
      cmd_tokens = argv[(sep + 1)..-1] || []
      raise ArgumentError, "missing command after --" if cmd_tokens.empty?

      explicit_name = nil
      if (i = pre.index("--name"))
        explicit_name = pre[i + 1]
        raise ArgumentError, "--name needs a value" if explicit_name.nil?
        pre = pre[0...i] + (pre[(i + 2)..-1] || [])
      end

      schedule = Schedule.parse(pre)
      cmd = cmd_tokens.join(" ")
      store = Store.load

      if explicit_name
        name = sanitize(explicit_name)
        if store[name]
          raise ArgumentError,
                "task #{name.inspect} already exists (every rm #{name}, or pick another --name)"
        end
      else
        name = derive_name(cmd, store)
      end

      store.add(name, "cmd" => cmd,
                      "schedule" => schedule.to_h,
                      "cwd" => Dir.pwd,
                      "created_at" => Time.now.iso8601,
                      "paused" => false)
      Runtime.ensure!
      Launchd.write_plist(name, schedule)
      Launchd.bootstrap(name)

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
        last_s = last ? Time.parse(last["ts"]).strftime("%d %b %H:%M") : "—"
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
        return "soon" unless last
        (Time.parse(last["ts"]) + sched.interval).strftime("%d %b %H:%M")
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

    def log(name)
      usage!("log <name> [-n N]") unless name
      n = 40
      if (i = @argv.index("-n"))
        n = @argv[i + 1].to_i
        n = 40 if n <= 0
      end
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
      Launchd.bootout(name)
      plist = Launchd.plist_path(name)
      File.delete(plist) if File.exist?(plist)
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
      Launchd.bootout(name)
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
      Launchd.write_plist(name, Schedule.from_h(task["schedule"]))
      Launchd.bootstrap(name)
      store.update(name, "paused" => false)
      puts "✓ resumed #{name}"
    end

    # ---- helpers ----

    def derive_name(cmd, store)
      base = sanitize(File.basename(cmd.strip.split(/\s+/).first.to_s))
      base = "task" if base.empty?
      name = base
      i = 2
      while store[name]
        name = "#{base}-#{i}"
        i += 1
      end
      name
    end

    def sanitize(s)
      s.to_s.downcase.gsub(/[^a-z0-9_.-]/, "-").gsub(/\A-+|-+\z/, "")
    end

    def usage!(msg)
      warn "usage: every #{msg}"
      exit 64
    end

    def help
      puts <<~TXT
        every #{VERSION} — schedule anything on your Mac, humanely

        add a task:
          every 15m -- ~/bin/sync-notes.sh
          every hourly -- brew update
          every day 9am -- ruby ~/bin/report.rb
          every monday 10:00 --name weekly-report -- ~/bin/weekly.sh

          The command runs through your login shell (PATH works), in the
          directory where you added it. Missed calendar runs fire on wake.

        manage:
          every list                what's scheduled, last/next run, ok/FAIL
          every log <name> [-n N]   output of recent runs
          every pause <name>        stop scheduling (keeps the task)
          every resume <name>       start again
          every rm <name>           remove task (logs are kept)
          every doctor              explain why something isn't running

        data:  #{DATA_DIR}
        agents: ~/Library/LaunchAgents/com.every.<name>.plist
      TXT
    end
  end
end
