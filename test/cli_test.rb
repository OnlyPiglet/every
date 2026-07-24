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
end
