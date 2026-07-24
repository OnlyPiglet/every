module Every
  # `every run <name>` — what launchd actually invokes. Executes the task's
  # command through the user's login shell (so PATH matches the terminal),
  # captures all output, and records the run.
  module Runner
    MAX_LOG_BYTES = 5 * 1024 * 1024

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
      dir, note = workdir(task)
      out, status = Open3.capture2e(*login_shell, task["cmd"], chdir: dir)
      out = note + out if note
      exit_code = status.exitstatus || 1
      duration = (Time.now - started).round(2)

      append_log(name, started, exit_code, duration, out)
      append_run(name, started, exit_code, duration)
      notify_failure(name, exit_code) if exit_code != 0 && !task["quiet"]

      if $stdout.tty?
        print out
        puts "— exit #{exit_code} in #{duration}s (logged: every log #{name})"
      end
      exit exit_code
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
      File.open(File.join(RUNS_DIR, "#{name}.jsonl"), "a") do |f|
        f.puts JSON.generate("ts" => started.iso8601,
                             "exit" => exit_code,
                             "dur" => duration)
      end
    end

    def rotate(path)
      return unless File.exist?(path) && File.size(path) > MAX_LOG_BYTES
      FileUtils.mv(path, "#{path}.old")
    end
  end
end
