require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class SystemdTest < Minitest::Test
  S = Every::Schedule
  SD = Every::Systemd

  def timer(raw)
    SD.timer_unit("demo", S.parse(raw.split))
  end

  def test_interval_timer
    t = timer("15m")
    assert_includes t, "OnUnitActiveSec=900"
    assert_includes t, "OnActiveSec=900"
    refute_includes t, "OnCalendar"
    assert_includes t, "WantedBy=timers.target"
  end

  def test_daily_calendar
    t = timer("day 9am")
    assert_includes t, "OnCalendar=*-*-* 09:00:00"
    assert_includes t, "Persistent=true"
  end

  def test_weekly_calendar
    assert_includes timer("monday 10:00"), "OnCalendar=Mon *-*-* 10:00:00"
    assert_includes timer("friday 6pm"), "OnCalendar=Fri *-*-* 18:00:00"
  end

  def test_multi_entry_calendar
    t = timer("weekdays 9am,6pm")
    assert_equal 10, t.scan("OnCalendar=").length
    assert_includes t, "OnCalendar=Mon *-*-* 09:00:00"
    assert_includes t, "OnCalendar=Fri *-*-* 18:00:00"
  end

  def test_calendar_lines_for_day_set
    lines = SD.calendar_lines(S.parse(%w[weekends 11am]))
    assert_equal ["Sun *-*-* 11:00:00", "Sat *-*-* 11:00:00"], lines
  end

  def test_service_unit_quotes_paths
    u = SD.service_unit("demo")
    assert_includes u, "Type=oneshot"
    assert_match(/ExecStart=\S+ ".+" run "demo"/, u)
  end
end
