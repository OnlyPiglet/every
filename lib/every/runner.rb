module Every
  # `every run <name>` — what launchd actually invokes. Executes the task's
  # command through the user's login shell (so PATH matches the terminal),
  # captures all output, and records the run.
  module Runner
    MAX_LOG_BYTES = 5 * 1024 * 1024
    # The run ledger is a rolling window: enough history for status and a
    # staleness watchdog, but bounded so a task firing every minute for years
    # can't grow it without limit (and keep `list` fast). Detailed output lives
    # in the separately-rotated .log.
    MAX_RUN_RECORDS = 500
    RUN_TRIM_BYTES = 256 * 1024
    # Captured output is bounded so a chatty task can't OOM the run: keep the
    # first and last HALF_OUTPUT bytes (errors show up at both ends), drop the
    # middle. The full stream still flows to the command; we just don't hold it.
    HALF_OUTPUT = 32 * 1024

    module_function

    def run(name)
      task = Store.load[name]
      unless task
        warn "every: unknown task #{name.inspect} — orphaned agent? try: every doctor"
        exit 66
      end

      FileUtils.mkdir_p(LOG_DIR)
      FileUtils.mkdir_p(RUNS_DIR)

      started = Time.now
      mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dir, note = workdir(task)
      out, exit_code = capture(task["cmd"], dir, task["timeout"])
      out = note + out if note
      # Monotonic clock: an NTP/DST wall-clock jump mid-run can't make this
      # negative. The ledger timestamp still uses wall-clock `started`.
      duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - mono).round(2)

      append_log(name, started, exit_code, duration, out)
      append_run(name, started, exit_code, duration)
      notify_failure(name, exit_code) if exit_code != 0 && !task["quiet"]

      if $stdout.tty?
        print out
        puts "— exit #{exit_code} in #{duration}s (logged: every log #{name})"
      end
      exit exit_code
    end

    # Execute the command, capturing bounded output and enforcing an optional
    # timeout. The child runs in its own process group so a timeout kills the
    # whole tree (the login shell plus anything it spawned), never leaving a
    # hung process to block the next scheduled run.
    def capture(cmd, dir, timeout_sec)
      require "timeout"
      head = "".b
      tail = "".b
      dropped = 0
      status = nil

      Open3.popen2e(*login_shell, cmd, chdir: dir, pgroup: true) do |stdin, out, wait|
        stdin.close
        pid = wait.pid
        drain = lambda do
          while (chunk = out.read(16 * 1024))
            if head.bytesize < HALF_OUTPUT
              head << chunk
            else
              tail << chunk
              if tail.bytesize > HALF_OUTPUT
                over = tail.bytesize - HALF_OUTPUT
                dropped += over
                tail = tail.byteslice(over, HALF_OUTPUT)
              end
            end
          end
        end

        begin
          timeout_sec ? Timeout.timeout(timeout_sec) { drain.call } : drain.call
          status = wait.value
        rescue Timeout::Error
          kill_group(pid)
          status = (wait.value rescue nil)
          head << "\n[every: killed after #{timeout_sec}s timeout]\n"
        end
      end

      body = head.dup
      body << "\n… [#{dropped} bytes truncated] …\n" << tail if dropped.positive?
      [body, status&.exitstatus || 124]
    end

    def kill_group(pid)
      pgid = Process.getpgid(pid)
      Process.kill("-TERM", pgid)
      sleep 0.3
      Process.kill("-KILL", pgid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    # Run through the user's login shell so PATH matches their terminal.
    def login_shell
      if RUBY_PLATFORM.include?("darwin")
        ["/bin/zsh", "-lc"]
      else
        [ENV["SHELL"] || "/bin/bash", "-lc"]
      end
    end

    # Desktop notification so failures don't die silently in a log file.
    def notify_failure(name, exit_code)
      msg = "#{name} failed (exit #{exit_code}) — every log #{name}"
      if RUBY_PLATFORM.include?("darwin")
        script = "display notification \"#{osa_esc(msg)}\" with title \"every\""
        system("osascript", "-e", script, out: File::NULL, err: File::NULL)
      else
        system("notify-send", "every", msg, out: File::NULL, err: File::NULL)
      end
    end

    def osa_esc(s)
      s.gsub("\\", "\\\\\\\\").gsub('"', '\"')
    end

    # Probe actual readability: under launchd, TCC-protected dirs (Documents…)
    # pass File.directory? but fail on access — fall back to HOME, loudly.
    def workdir(task)
      dir = task["cwd"]
      return [Dir.home, nil] unless dir && File.directory?(dir)
      Dir.entries(dir)
      [dir, nil]
    rescue SystemCallError
      [Dir.home,
       "note: cwd #{dir} not readable under launchd (TCC) — ran from #{Dir.home}\n"]
    end

    def append_log(name, started, exit_code, duration, out)
      path = File.join(LOG_DIR, "#{name}.log")
      rotate(path)
      File.open(path, "a") do |f|
        f.puts "=== #{started.strftime('%Y-%m-%d %H:%M:%S')} exit=#{exit_code} dur=#{duration}s ==="
        f.write(out)
        f.puts unless out.empty? || out.end_with?("\n")
      end
    end

    def append_run(name, started, exit_code, duration)
      path = File.join(RUNS_DIR, "#{name}.jsonl")
      File.open(path, "a") do |f|
        f.puts JSON.generate("ts" => started.iso8601,
                             "exit" => exit_code,
                             "dur" => duration)
      end
      trim_runs(path)
    end

    # Amortized-cheap bound: only touched once the file crosses the byte cap,
    # then rewritten to the last MAX_RUN_RECORDS lines.
    def trim_runs(path)
      return if File.size(path) <= RUN_TRIM_BYTES
      lines = File.readlines(path)
      return if lines.length <= MAX_RUN_RECORDS
      File.write(path, lines.last(MAX_RUN_RECORDS).join)
    end

    def rotate(path)
      return unless File.exist?(path) && File.size(path) > MAX_LOG_BYTES
      FileUtils.mv(path, "#{path}.old")
    end
  end
end
