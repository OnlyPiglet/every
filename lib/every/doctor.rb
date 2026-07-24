module Every
  # `every doctor` — explains, in plain language, why scheduled tasks
  # might not be running. Covers the classic launchd traps.
  module Doctor
    module_function

    def run
      failures = 0

      failures += report("running on macOS",
                         RUBY_PLATFORM.include?("darwin"),
                         "every v1 only supports macOS (launchd)")

      _out, st = Open3.capture2e("launchctl", "print", "gui/#{Launchd.uid}")
      failures += report("launchd user session reachable (gui/#{Launchd.uid})",
                         st.success?,
                         "no GUI session — launchd agents don't run over bare SSH sessions")

      dir_ok = begin
        FileUtils.mkdir_p(DATA_DIR)
        File.writable?(DATA_DIR)
      rescue StandardError
        false
      end
      failures += report("data dir writable (#{DATA_DIR})", dir_ok,
                         "fix permissions on #{DATA_DIR}")

      store = Store.load
      if store.tasks.empty?
        puts "  (no tasks registered yet)"
      else
        failures += report("runtime copy present (#{Runtime.bin})",
                           File.exist?(Runtime.bin),
                           "refresh it: every resume <name> (or re-add any task)")
      end

      store.tasks.each do |name, task|
        puts "\ntask: #{name}"
        plist = Launchd.plist_path(name)
        failures += report("plist exists (#{plist})", File.exist?(plist),
                           "re-create the task: every rm #{name} && every <schedule> -- <cmd>")

        if task["paused"]
          puts "  · paused — resume with: every resume #{name}"
        else
          failures += report("agent loaded in launchd", Launchd.loaded?(name),
                             "load it: every resume #{name}")
        end

        first_word = task["cmd"].to_s.strip.split(/\s+/).first.to_s
        _o, st = Open3.capture2e("/bin/zsh", "-lc", "command -v #{shellword(first_word)}")
        failures += report("command resolvable in login shell (#{first_word})",
                           st.success?,
                           "launchd runs zsh as a LOGIN shell: PATH set only in ~/.zshrc " \
                           "(e.g. mise/rbenv hooks) is not visible — move it to ~/.zprofile, " \
                           "or use an absolute path")

        if task["cwd"].to_s =~ %r{/(Documents|Desktop|Downloads)(/|\z)}
          puts "  · note: added inside #{Regexp.last_match(1)} (TCC-protected) — if the command touches"
          puts "    that folder, grant Full Disk Access to ruby (System Settings → Privacy & Security)"
        end

        last = store.last_run(name)
        if last.nil?
          puts "  · no runs recorded yet (next: check `every list`)"
        elsif last["exit"] != 0
          failures += report("last run succeeded", false,
                             "exit=#{last['exit']} — see: every log #{name}")
          log_path = File.join(LOG_DIR, "#{name}.log")
          if File.exist?(log_path) && File.read(log_path).include?("Operation not permitted")
            puts "    hint: 'Operation not permitted' usually means the ruby binary needs"
            puts "    Full Disk Access (System Settings → Privacy & Security) to touch that folder"
          end
        else
          puts "  ✓ last run ok (#{last['ts']})"
        end
      end

      puts
      if failures.zero?
        puts "all good ✓"
      else
        puts "#{failures} problem(s) found"
        exit 1
      end
    end

    def report(label, ok, fix)
      if ok
        puts "  ✓ #{label}"
        0
      else
        puts "  ✗ #{label}"
        puts "    → #{fix}"
        1
      end
    end

    def shellword(w)
      "'" + w.gsub("'", "'\\\\''") + "'"
    end
  end
end
