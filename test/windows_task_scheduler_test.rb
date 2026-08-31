require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class WindowsTaskSchedulerTest < Minitest::Test
  S = Every::Schedule
  WS = Every::WindowsTaskScheduler

  def test_interval_xml
    xml = WS.task_xml("demo", S.parse(["15m"]))
    assert_includes xml, "<TimeTrigger>"
    assert_includes xml, "<Interval>PT900S</Interval>"
    assert_includes xml, "<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>"
    assert_includes xml, "<StartWhenAvailable>true</StartWhenAvailable>"
    assert_includes xml, "\\every\\demo"
  end

  def test_calendar_xml
    xml = WS.task_xml("demo", S.parse(%w[day 9am]))
    assert_includes xml, "<CalendarTrigger>"
    assert_includes xml, "<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>"
    assert_includes xml, "<Command>"
    assert_includes xml, "demo.runner.rb"
  end

  def test_weekly_xml
    xml = WS.task_xml("demo", S.parse(%w[monday,thursday 6pm]))
    assert_includes xml, "<Monday/>"
    assert_includes xml, "<Thursday/>"
    assert_equal 2, xml.scan("<CalendarTrigger>").length
  end

  def test_wrapper_pins_data_dir_and_loads_runtime
    wrapper = WS.runner_wrapper("demo")
    assert_includes wrapper, "ENV[\"EVERY_HOME\"]"
    assert_includes wrapper, Every::DATA_DIR
    assert_includes wrapper, "require \"every\""
    assert_includes wrapper, "Every::Runner.run(\"demo\")"
  end

  def test_parse_tasks_filters_non_every_tasks
    out = <<~CSV
      "\\every\\backup","08/31/2026 09:00:00","Ready"
      "\\every\\paused","N/A","Disabled"
      "\\Microsoft\\Windows\\Other","N/A","Ready"
    CSV
    assert_equal [
      { name: "backup", status: "Ready" },
      { name: "paused", status: "Disabled" }
    ], WS.parse_tasks(out)
  end

  def test_subminute_intervals_are_rejected
    error = assert_raises(ArgumentError) do
      WS.validate_schedule!(S.parse(["15s"]))
    end
    assert_includes error.message, "from 1m"
  end

  def test_windows_shell_defaults_to_cmd
    shell = Every::Runner.windows_shell
    assert_match(/cmd\.exe\z/i, shell.first)
    assert_equal ["/d", "/s", "/c"], shell.drop(1)
  end

  def test_backend_dispatches_to_windows_scheduler
    Every.stub(:darwin?, false) do
      Every.stub(:windows?, true) do
        assert_equal WS, Every::Backend.current
      end
    end
  end
end
