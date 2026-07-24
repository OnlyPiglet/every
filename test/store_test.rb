require "minitest/autorun"
require "fileutils"
require "json"
ENV["EVERY_HOME"] = "/private/tmp/every-store-test"
FileUtils.rm_rf(ENV["EVERY_HOME"])
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class StoreTest < Minitest::Test
  def setup
    FileUtils.rm_rf(ENV["EVERY_HOME"])
  end

  def teardown
    FileUtils.rm_rf(ENV["EVERY_HOME"])
  end

  def test_add_persists_and_reloads
    Every::Store.load.add("a", "cmd" => "echo 1")
    assert_equal "echo 1", Every::Store.load["a"]["cmd"]
  end

  # Atomic write: many saves leave a valid file and no .tmp litter behind.
  def test_atomic_write_leaves_no_tmp_and_valid_file
    s = Every::Store.load
    50.times { |i| s.add("t#{i}", "cmd" => "echo #{i}") }
    litter = Dir.glob("#{Every::Store::FILE}.tmp*")
    assert_empty litter, "atomic write left temp files: #{litter}"
    # File is always complete/parseable (never a truncated half-write).
    assert JSON.parse(File.read(Every::Store::FILE))
    assert_equal 50, Every::Store.load.tasks.length
  end

  # A corrupt registry must fail loudly, not be read as "no tasks".
  def test_corrupt_store_aborts
    FileUtils.mkdir_p(Every::DATA_DIR)
    File.write(Every::Store::FILE, "{ not valid json")
    assert_raises(SystemExit) { Every::Store.load }
  end

  # A crash mid-append leaves a torn final line; last_run must report the last
  # COMPLETE run, not fall back to nil ("no runs").
  def test_last_run_skips_torn_trailing_line
    FileUtils.mkdir_p(Every::RUNS_DIR)
    path = File.join(Every::RUNS_DIR, "torn.jsonl")
    File.open(path, "w") do |f|
      f.puts JSON.generate("ts" => "2026-07-01T09:00:00+03:00", "exit" => 0)
      f.puts JSON.generate("ts" => "2026-07-02T09:00:00+03:00", "exit" => 7)
      f.write('{"ts":"2026-07-03T09:00:00+03:00","exit":0,"du') # torn
    end
    last = Every::Store.new("tasks" => {}).last_run("torn")
    assert_equal 7, last["exit"]
  end
end
