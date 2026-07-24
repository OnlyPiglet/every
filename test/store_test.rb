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
end
