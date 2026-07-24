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

  def test_day_am
    s = parse("day 9am")
    assert_equal :daily, s.kind
    assert_equal [9, 0], [s.hour, s.minute]
  end

  def test_day_24h_with_minutes
    s = parse("day 17:30")
    assert_equal [17, 30], [s.hour, s.minute]
  end

  def test_day_pm_with_minutes
    assert_equal [21, 5], parse("day 9:05pm").instance_eval { [hour, minute] }
  end

  def test_midnight_and_noon
    assert_equal [0, 0], parse("day 12am").instance_eval { [hour, minute] }
    assert_equal [12, 0], parse("day 12pm").instance_eval { [hour, minute] }
  end

  # ---- weekly ----

  def test_weekday
    s = parse("monday 10:00")
    assert_equal :weekly, s.kind
    assert_equal 1, s.weekday
    assert_equal [10, 0], [s.hour, s.minute]
  end

  def test_weekday_pm
    s = parse("friday 6pm")
    assert_equal 5, s.weekday
    assert_equal 18, s.hour
  end

  # ---- rejects ----

  def test_rejects_garbage
    assert_raises(ArgumentError) { parse("borscht") }
    assert_raises(ArgumentError) { parse("day") }
    assert_raises(ArgumentError) { parse("day 25:00") }
    assert_raises(ArgumentError) { parse("day 9:75") }
    assert_raises(ArgumentError) { S.parse([]) }
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
