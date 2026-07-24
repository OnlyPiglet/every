require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "every"

class RuntimeTest < Minitest::Test
  # The tool must copy itself into the data dir ONLY from TCC-protected macOS
  # folders. From Homebrew / /usr/local / ~/code it points at the live install,
  # so `brew upgrade` reaches scheduled runs instead of freezing a stale copy.
  def test_tcc_classification
    tcc = %w[
      /Users/me/Documents/every
      /Users/me/Desktop/tools/every
      /Users/me/Downloads/every
    ]
    safe = %w[
      /opt/homebrew/Cellar/every/0.1.0/libexec
      /usr/local/Cellar/every/0.1.0/libexec
      /Users/me/code/every
      /Users/me/.local/share/every/runtime
    ]
    if RUBY_PLATFORM.include?("darwin")
      tcc.each  { |p| assert Every::Runtime.tcc_protected?(p), "#{p} should be TCC-protected" }
      safe.each { |p| refute Every::Runtime.tcc_protected?(p), "#{p} should NOT be TCC-protected" }
    else
      # No TCC on Linux — those folder names carry no restriction, so an install
      # under ~/Documents must stay live (never copied).
      (tcc + safe).each { |p| refute Every::Runtime.tcc_protected?(p), "#{p} must not be TCC on Linux" }
    end
  end
end
