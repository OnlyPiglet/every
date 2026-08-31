module Every
  # Native Windows backend.  Each task is registered with the Windows Task
  # Scheduler under the `\\every\\` task path.  The scheduler invokes Ruby
  # directly; the user's command remains in tasks.json and is still executed by
  # Runner, just like the launchd and systemd backends.
  module WindowsTaskScheduler
    TASK_DIR = File.join(DATA_DIR, "windows-tasks")
    TASK_PATH_PREFIX = "\\every\\"
    WEEKDAY_TAGS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

    module_function

    def task_name(name)
      "#{TASK_PATH_PREFIX}#{name}"
    end

    # Kept as a file path for diagnostics and cleanup.  The source of truth for
    # registration is the Task Scheduler service, not this XML copy.
    def unit_path(name)
      xml_path(name)
    end

    def xml_path(name)
      File.join(TASK_DIR, "#{name}.xml")
    end

    def wrapper_path(name)
      File.join(TASK_DIR, "#{name}.runner.rb")
    end

    def write(name, schedule)
      validate_schedule!(schedule)
      FileUtils.mkdir_p(TASK_DIR)
      atomic_write(wrapper_path(name), runner_wrapper(name))
      atomic_write(xml_path(name), task_xml(name, schedule))

      out, st = schtasks("/Create", "/TN", task_name(name),
                         "/XML", xml_path(name), "/F")
      raise "Task Scheduler registration failed: #{out.strip}" unless st.success?
      true
    end

    def enable(name)
      out, st = schtasks("/Change", "/TN", task_name(name), "/ENABLE")
      raise "Task Scheduler enable failed: #{out.strip}" unless st.success?
      true
    end

    def disable(name)
      schtasks("/Change", "/TN", task_name(name), "/DISABLE")
      true
    end

    def loaded?(name)
      _out, st = schtasks("/Query", "/TN", task_name(name), "/FO", "LIST", "/NH")
      st.success?
    end

    # Task Scheduler stores tasks in its service/registry, so this deliberately
    # differs from the XML-file check used by launchd/systemd.
    def resource_exists?(name)
      loaded?(name)
    end

    # `/FO CSV /NH` is machine-readable and avoids localized column headers.
    # We only parse the task path and status; the rest is owned by the service.
    def loaded_names
      out, st = schtasks("/Query", "/FO", "CSV", "/NH")
      return [] unless st.success?

      parse_tasks(out).each_with_object([]) do |row, names|
        names << row[:name] unless row[:status].to_s =~ /disabled/i
      end
    end

    def parse_tasks(out)
      CSV.parse(out.to_s, liberal_parsing: true).each_with_object([]) do |row, acc|
        next if row.empty?
        raw_name = row[0].to_s.sub(/\A\uFEFF/, "").strip
        match = raw_name.match(/\A\\every\\(.+)\z/i)
        next unless match
        acc << { name: match[1], status: row[2].to_s }
      end
    rescue CSV::MalformedCSVError
      []
    end

    def delete_units(name)
      schtasks("/Delete", "/TN", task_name(name), "/F")
      [xml_path(name), wrapper_path(name)].each do |path|
        File.delete(path) if File.exist?(path)
      end
      true
    end

    # Used by `doctor` to distinguish a missing Task Scheduler service from a
    # missing individual task.
    def scheduler_status
      Open3.capture2e("sc.exe", "query", "Schedule")
    end

    def task_xml(name, schedule)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
          <RegistrationInfo>
            <Author>#{xml_escape(current_user)}</Author>
            <URI>#{xml_escape(task_name(name))}</URI>
          </RegistrationInfo>
          <Triggers>
        #{trigger_xml(schedule)}
          </Triggers>
          <Principals>
            <Principal id="Author">
              <UserId>#{xml_escape(current_user)}</UserId>
              <LogonType>InteractiveToken</LogonType>
              <RunLevel>LeastPrivilege</RunLevel>
            </Principal>
          </Principals>
          <Settings>
            <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
            <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
            <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
            <AllowHardTerminate>true</AllowHardTerminate>
            <StartWhenAvailable>true</StartWhenAvailable>
            <AllowStartOnDemand>true</AllowStartOnDemand>
            <Enabled>true</Enabled>
            <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
          </Settings>
          <Actions Context="Author">
            <Exec>
              <Command>#{xml_escape(RbConfig.ruby)}</Command>
              <Arguments>#{xml_escape(%("#{wrapper_path(name)}"))}</Arguments>
            </Exec>
          </Actions>
        </Task>
      XML
    end

    def trigger_xml(schedule)
      if schedule.kind == :interval
        start = Time.now + schedule.interval
        <<~XML
          <TimeTrigger>
            <StartBoundary>#{xml_time(start)}</StartBoundary>
            <Enabled>true</Enabled>
            <Repetition>
              <Interval>PT#{schedule.interval}S</Interval>
              <StopAtDurationEnd>false</StopAtDurationEnd>
            </Repetition>
          </TimeTrigger>
        XML
      else
        schedule.entries.map { |entry| calendar_trigger_xml(schedule, entry) }.join
      end
    end

    def calendar_trigger_xml(schedule, entry)
      start = schedule.next_for_entry(entry, Time.now)
      recurrence = if entry["weekday"]
                      tag = WEEKDAY_TAGS[entry["weekday"].to_i % 7]
                      <<~XML
                        <ScheduleByWeek>
                          <DaysOfWeek><#{tag}/></DaysOfWeek>
                          <WeeksInterval>1</WeeksInterval>
                        </ScheduleByWeek>
                      XML
                    else
                      <<~XML
                        <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
                      XML
                    end

      <<~XML
        <CalendarTrigger>
          <StartBoundary>#{xml_time(start)}</StartBoundary>
          <Enabled>true</Enabled>
        #{recurrence}
        </CalendarTrigger>
      XML
    end

    def runner_wrapper(name)
      # Task Scheduler Exec actions do not expose a per-task environment block.
      # A tiny Ruby wrapper sets EVERY_HOME before requiring the runtime, so
      # custom data directories behave exactly like launchd/systemd services.
      runtime_lib = File.expand_path("../lib", File.dirname(Runtime.bin))
      <<~RUBY
        ENV["EVERY_HOME"] = #{DATA_DIR.dump}
        $LOAD_PATH.unshift(#{runtime_lib.dump})
        require "every"
        Every::Runner.run(#{name.dump})
      RUBY
    end

    def validate_schedule!(schedule)
      return unless schedule.kind == :interval
      return if schedule.interval >= 60

      raise ArgumentError,
            "Windows Task Scheduler supports interval schedules from 1m; " \
            "#{schedule.human_interval} needs a future resident scheduler"
    end

    def current_user
      username = ENV["USERNAME"].to_s
      username = ENV["USER"].to_s if username.empty? && !Every.windows?
      raise "USERNAME is not set; cannot register a per-user Windows task" if username.empty?
      domain = ENV["USERDOMAIN"].to_s
      domain.empty? ? username : "#{domain}\\#{username}"
    end

    def xml_time(time)
      time.strftime("%Y-%m-%dT%H:%M:%S")
    end

    def xml_escape(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # The XML and wrapper are written before registration.  FileUtils.mv with
    # force works on both POSIX and Windows, where rename-over-existing differs.
    def atomic_write(path, content)
      tmp = "#{path}.tmp.#{Process.pid}"
      File.write(tmp, content)
      FileUtils.mv(tmp, path, force: true)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    def schtasks(*args)
      Open3.capture2e("schtasks.exe", *args)
    end
  end
end
