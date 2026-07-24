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
end
