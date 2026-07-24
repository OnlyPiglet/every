require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class ScheduleTest < Minitest::Test
  S = Every::Schedule

  def parse(str)
    S.parse(str.split)
  end

  # ---- intervals ----

  def test_minutes
    s = parse("15m")
    assert_equal :interval, s.kind
    assert_equal 900, s.interval
  end

  def test_seconds_and_hours
    assert_equal 90, parse("90s").interval
    assert_equal 7200, parse("2h").interval
  end

  def test_hourly_alias
    assert_equal 3600, parse("hourly").interval
  end

  def test_interval_minimum
    assert_raises(ArgumentError) { parse("5s") }
  end

  # ---- daily ----

  def entry(s, i = 0)
    e = s.entries[i]
    [e["weekday"], e["hour"], e["minute"]]
  end

  def test_day_am
    s = parse("day 9am")
    assert_equal :calendar, s.kind
    assert_equal [nil, 9, 0], entry(s)
  end

  def test_day_24h_with_minutes
    assert_equal [nil, 17, 30], entry(parse("day 17:30"))
  end

  def test_day_pm_with_minutes
    assert_equal [nil, 21, 5], entry(parse("day 9:05pm"))
  end

  def test_midnight_and_noon
    assert_equal [nil, 0, 0], entry(parse("day 12am"))
    assert_equal [nil, 12, 0], entry(parse("day 12pm"))
  end

  # ---- weekly ----

  def test_weekday
    s = parse("monday 10:00")
    assert_equal :calendar, s.kind
    assert_equal [1, 10, 0], entry(s)
  end

  def test_weekday_pm
    assert_equal [5, 18, 0], entry(parse("friday 6pm"))
  end

  # ---- multi-entry calendar forms ----

  def test_multiple_times_per_day
    s = parse("day 9am,6pm")
    assert_equal :calendar, s.kind
    assert_equal [{ "hour" => 9, "minute" => 0 }, { "hour" => 18, "minute" => 0 }],
                 s.entries
  end

  def test_weekdays_set
    s = parse("weekdays 9:30")
    assert_equal [1, 2, 3, 4, 5], s.entries.map { |e| e["weekday"] }
    assert s.entries.all? { |e| e["hour"] == 9 && e["minute"] == 30 }
  end

  def test_weekends_set
    assert_equal [0, 6], parse("weekends 11am").entries.map { |e| e["weekday"] }
  end

  def test_multiple_weekdays
    s = parse("monday,thursday 10:00")
    assert_equal [1, 4], s.entries.map { |e| e["weekday"] }
  end

  def test_day_set_times_product
    s = parse("weekdays 9am,6pm")
    assert_equal 10, s.entries.length
  end

  def test_next_run_picks_earliest_entry
    from = Time.new(2026, 7, 24, 12, 0, 0)
    t = parse("day 9am,6pm").next_run(from)
    assert_equal Time.new(2026, 7, 24, 18, 0, 0), t
  end

  # ---- legacy format migration ----

  def test_from_h_migrates_pre_02_daily
    s = S.from_h("raw" => "day 9am", "kind" => "daily", "hour" => 9, "minute" => 0)
    assert_equal :calendar, s.kind
    assert_equal [{ "hour" => 9, "minute" => 0 }], s.entries
  end

  def test_from_h_migrates_pre_02_weekly
    s = S.from_h("raw" => "monday 10:00", "kind" => "weekly",
                 "hour" => 10, "minute" => 0, "weekday" => 1)
    assert_equal [{ "hour" => 10, "minute" => 0, "weekday" => 1 }], s.entries
  end

  # ---- rejects ----

  def test_rejects_garbage
    assert_raises(ArgumentError) { parse("borscht") }
    assert_raises(ArgumentError) { parse("day") }
    assert_raises(ArgumentError) { parse("day 25:00") }
    assert_raises(ArgumentError) { parse("day 9:75") }
    assert_raises(ArgumentError) { parse("day 9am,25:00") }
    assert_raises(ArgumentError) { parse("monday,funday 10:00") }
    assert_raises(ArgumentError) { S.parse([]) }
  end

  # An empty / comma-only time list must ERROR, not create a never-firing task.
  def test_rejects_empty_time_list
    assert_raises(ArgumentError) { parse("day ,") }
    assert_raises(ArgumentError) { parse("day 9am,") }
    assert_raises(ArgumentError) { parse("day 9am,,6pm") }
  end

  # am/pm with an out-of-band hour must error, not silently become 13:00 / 00:00.
  def test_rejects_bad_ampm_hours
    assert_raises(ArgumentError) { parse("day 13pm") }
    assert_raises(ArgumentError) { parse("day 0am") }
  end

  def test_dedupes_repeated_times_and_days
    assert_equal 1, parse("day 9am,9am").entries.length
    assert_equal 1, parse("monday,monday 10:00").entries.length
  end

  # A legacy persisted weekday of 7 (Sunday) must clamp to 0, not crash systemd.
  def test_from_h_clamps_legacy_weekday_seven
    s = S.from_h("raw" => "sunday 9am", "kind" => "weekly",
                 "hour" => 9, "minute" => 0, "weekday" => 7)
    assert_equal 0, s.entries.first["weekday"]
  end

  # ---- next_run ----

  def test_daily_next_run_today_if_future
    from = Time.new(2026, 7, 24, 8, 0, 0)
    t = parse("day 9am").next_run(from)
    assert_equal Time.new(2026, 7, 24, 9, 0, 0), t
  end

  def test_daily_next_run_tomorrow_if_past
    from = Time.new(2026, 7, 24, 10, 0, 0)
    t = parse("day 9am").next_run(from)
    assert_equal Time.new(2026, 7, 25, 9, 0, 0), t
  end

  def test_weekly_next_run_lands_on_weekday_within_a_week
    from = Time.new(2026, 7, 24, 12, 0, 0)
    t = parse("monday 10:00").next_run(from)
    assert_equal 1, t.wday
    assert_equal [10, 0], [t.hour, t.min]
    assert t > from
    assert t - from <= 7 * 86_400
  end

  def test_weekly_same_day_future_time_stays_today
    from = Time.new(2026, 7, 24, 8, 0, 0) # a Friday
    t = parse("friday 6pm").next_run(from)
    assert_equal Time.new(2026, 7, 24, 18, 0, 0), t
  end

  def test_interval_has_no_calendar_next_run
    assert_nil parse("15m").next_run
  end

  # ---- serialization round-trip ----

  def test_to_h_from_h_round_trip
    ["15m", "hourly", "day 9am", "monday 10:00"].each do |raw|
      s = parse(raw)
      r = S.from_h(s.to_h)
      assert_equal s.to_h, r.to_h
      assert_equal raw, r.raw
    end
  end
end
