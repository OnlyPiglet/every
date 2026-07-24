require "minitest/autorun"
require "fileutils"
require "json"
ENV["EVERY_HOME"] = "/private/tmp/every-runner-test"
FileUtils.rm_rf(ENV["EVERY_HOME"])
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class RunnerTest < Minitest::Test
  def setup
    FileUtils.rm_rf(ENV["EVERY_HOME"])
    FileUtils.mkdir_p(Every::RUNS_DIR)
  end

  def teardown
    FileUtils.rm_rf(ENV["EVERY_HOME"])
  end

  # A task firing forever must not grow its ledger without bound. trim_runs
  # runs after every append, so the file can never exceed the byte cap by more
  # than one record — that bounded *size* (not an exact line count) is the
  # stability guarantee.
  def test_run_ledger_size_is_bounded
    path = File.join(Every::RUNS_DIR, "loop.jsonl")
    max_seen = 0
    8000.times do |i|
      File.open(path, "a") { |f| f.puts JSON.generate("ts" => "2026-01-01T00:00:0#{i % 10}+03:00", "exit" => i % 2, "dur" => 0.1) }
      Every::Runner.trim_runs(path)
      max_seen = [max_seen, File.size(path)].max
    end
    # 8000 raw records would be ~440 KB; bounded it must stay near the cap.
    assert max_seen <= Every::Runner::RUN_TRIM_BYTES + 1024,
           "ledger size unbounded: peaked at #{max_seen} bytes"
    # Trimming actually happened (fewer lines than appended)...
    assert File.readlines(path).length < 8000
    # ...and the most recent run survived (status/list depend on it).
    assert_equal 8000.pred % 2, JSON.parse(File.readlines(path).last)["exit"]
  end

  # Below the byte cap, nothing is trimmed — small tasks keep full history.
  def test_small_ledger_untouched
    path = File.join(Every::RUNS_DIR, "small.jsonl")
    10.times { |i| File.open(path, "a") { |f| f.puts JSON.generate("ts" => "t#{i}", "exit" => 0) } }
    Every::Runner.trim_runs(path)
    assert_equal 10, File.readlines(path).length
  end

  # A chatty task must not be held whole in memory — output comes back bounded.
  def test_capture_bounds_output
    out, code = Every::Runner.capture("yes xxxxxxxx | head -c 300000", Dir.home, nil)
    assert_equal 0, code
    assert out.bytesize < 100 * 1024, "output not bounded: #{out.bytesize} bytes"
    assert_includes out, "truncated"
  end

  # Small output passes through verbatim, no truncation marker.
  def test_capture_small_output_verbatim
    out, code = Every::Runner.capture("echo hello there", Dir.home, nil)
    assert_equal 0, code
    assert_includes out, "hello there"
    refute_includes out, "truncated"
  end

  # A hung task is killed at the timeout so it can't block the next run.
  def test_capture_timeout_kills
    t0 = Time.now
    out, code = Every::Runner.capture("sleep 30", Dir.home, 1)
    assert_operator code, :!=, 0
    assert_operator (Time.now - t0), :<, 5.0, "timeout did not fire promptly"
    assert_includes out, "timeout"
  end

  # Timeout must kill the whole process tree, not just the shell.
  def test_capture_timeout_kills_children
    marker = File.join(ENV["EVERY_HOME"], "child-alive")
    # A backgrounded child that would outlive a naive shell-only kill.
    Every::Runner.capture("(sleep 30 && touch #{marker}) & sleep 30", Dir.home, 1)
    sleep 2
    refute File.exist?(marker), "orphaned child survived the timeout kill"
  end
end
