require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class CliTest < Minitest::Test
  def setup
    @cli = Every::CLI.new([])
  end

  def st(paused, scheduled, last)
    @cli.send(:task_status, paused, scheduled, last)
  end

  # The dashboard must tell the truth about whether a task will actually run.
  def test_status_reflects_scheduler_reality
    ok = { "exit" => 0 }
    fail = { "exit" => 7 }

    assert_equal "paused",      st(true, false, ok)      # paused wins
    assert_equal "unscheduled", st(false, false, ok)     # agent gone -> NOT a stale "ok"
    assert_equal "·",           st(false, true, nil)     # loaded, no runs yet
    assert_equal "ok",          st(false, true, ok)      # loaded + last ok
    assert_equal "FAIL(7)",     st(false, true, fail)    # loaded + last failed
  end

  # A removed agent must never be reported as "ok" just because a past run
  # succeeded — this is the core "know it ran" promise.
  def test_unscheduled_beats_a_past_ok
    assert_equal "unscheduled", st(false, false, { "exit" => 0 })
  end

  # --json's next-run field: interval = last + interval; calendar = next fire.
  def test_next_iso_interval
    sched = Every::Schedule.parse(["15m"])
    got = @cli.send(:next_iso, sched, { "ts" => "2026-07-25T10:00:00+03:00" })
    assert_equal Time.parse("2026-07-25T10:15:00+03:00"), Time.parse(got)
  end

  def test_next_iso_interval_without_a_run_is_nil
    assert_nil @cli.send(:next_iso, Every::Schedule.parse(["15m"]), nil)
  end

  def test_next_iso_calendar_is_a_future_iso_time
    got = @cli.send(:next_iso, Every::Schedule.parse(%w[day 9am]), nil)
    assert got
    assert_equal 9, Time.parse(got).hour
  end
end
