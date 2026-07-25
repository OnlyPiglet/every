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

  # Sub-minute cadence needs tight accuracy or systemd batches to ~1 min.
  def test_timer_sets_tight_accuracy
    assert_includes timer("15s"), "AccuracySec=1s"
    assert_includes timer("day 9am"), "AccuracySec=1s"
  end

  # A custom EVERY_HOME must be propagated, else the timer reads the wrong store.
  # The resolved data dir must ALWAYS be pinned into the unit (not only when
  # EVERY_HOME is set) — otherwise an XDG_DATA_HOME install's scheduled runs
  # recompute the default dir and never find the task.
  def test_service_always_pins_data_dir
    assert_includes SD.service_unit("demo"), "Environment=EVERY_HOME=#{Every::DATA_DIR}"
  end

  # A legacy weekday of 7 must map to Sunday, not blow the DAYS index.
  def test_calendar_lines_handles_weekday_seven
    s = S.from_h("raw" => "sunday 9am", "kind" => "weekly",
                 "hour" => 9, "minute" => 0, "weekday" => 7)
    assert_equal ["Sun *-*-* 09:00:00"], SD.calendar_lines(s)
  end
end
