module Every
  # Everything that touches launchd: plist rendering + launchctl calls.
  # Agents live at ~/Library/LaunchAgents/com.every.<name>.plist and invoke
  # `every run <name>`, which does the actual execution + logging.
  module Launchd
    module_function

    def label(name)
      "com.every.#{name}"
    end

    def plist_path(name)
      File.join(AGENTS_DIR, "#{label(name)}.plist")
    end

    def uid
      Process.uid
    end

    def write_plist(name, schedule)
      FileUtils.mkdir_p(AGENTS_DIR)
      File.write(plist_path(name), plist_xml(name, schedule))
      plist_path(name)
    end

    def plist_xml(name, schedule)
      agent_log = File.join(LOG_DIR, "_agent.log")
      trigger =
        if schedule.kind == :interval
          "  <key>StartInterval</key>\n" \
          "  <integer>#{schedule.interval}</integer>"
        else
          dicts = schedule.entries.map do |e|
            lines = []
            if e["weekday"]
              lines << "      <key>Weekday</key><integer>#{e['weekday']}</integer>"
            end
            lines << "      <key>Hour</key><integer>#{e['hour']}</integer>"
            lines << "      <key>Minute</key><integer>#{e['minute']}</integer>"
            "    <dict>\n#{lines.join("\n")}\n    </dict>"
          end
          "  <key>StartCalendarInterval</key>\n  <array>\n#{dicts.join("\n")}\n  </array>"
        end

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>#{xesc(label(name))}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{xesc(RbConfig.ruby)}</string>
            <string>#{xesc(Runtime.bin)}</string>
            <string>run</string>
            <string>#{xesc(name)}</string>
          </array>
        #{trigger}
        #{env_block}  <key>RunAtLoad</key>
          <false/>
          <key>StandardOutPath</key>
          <string>#{xesc(agent_log)}</string>
          <key>StandardErrorPath</key>
          <string>#{xesc(agent_log)}</string>
        </dict>
        </plist>
      XML
    end

    # Propagate a custom data dir to launchd-spawned runs, else they would
    # read the default store and not find the task.
    def env_block
      return "" unless ENV["EVERY_HOME"]
      "  <key>EnvironmentVariables</key>\n" \
      "  <dict>\n" \
      "    <key>EVERY_HOME</key><string>#{xesc(DATA_DIR)}</string>\n" \
      "  </dict>\n"
    end

    def xesc(s)
      s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def bootstrap(name)
      path = plist_path(name)
      out, st = Open3.capture2e("launchctl", "bootstrap", "gui/#{uid}", path)
      return true if st.success?

      # Most common failure: an agent with this label is already loaded.
      bootout(name)
      out, st = Open3.capture2e("launchctl", "bootstrap", "gui/#{uid}", path)
      return true if st.success?

      _legacy, st2 = Open3.capture2e("launchctl", "load", "-w", path)
      return true if st2.success?

      raise "launchctl bootstrap failed: #{out.strip}"
    end

    def bootout(name)
      Open3.capture2e("launchctl", "bootout", "gui/#{uid}/#{label(name)}")
    end

    def loaded?(name)
      _out, st = Open3.capture2e("launchctl", "print", "gui/#{uid}/#{label(name)}")
      st.success?
    end
  end
end
