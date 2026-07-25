require "json"
require "fileutils"
require "time"
require "open3"
require "rbconfig"

module Every
  VERSION = "0.1.3".freeze
  HOMEPAGE = "https://github.com/Serhii-Leniv/every".freeze
  TAGLINE = "humane task scheduler for macOS (launchd) and Linux (systemd, beta)".freeze

  # Exit codes (sysexits.h convention): 0 ok · 64 usage/bad args ·
  # 66 no such task/log · 1 other failure. Runs also surface 124 (timeout) and
  # 128+signum (killed by a signal); see runner.rb.
  EX_USAGE = 64
  EX_NOINPUT = 66

  ROOT = File.expand_path("..", __dir__)
  BIN  = File.join(ROOT, "bin", "every")

  DATA_DIR   = File.expand_path(ENV["EVERY_HOME"] || "~/.local/share/every")
  LOG_DIR    = File.join(DATA_DIR, "logs")
  RUNS_DIR   = File.join(DATA_DIR, "runs")
  AGENTS_DIR = File.expand_path("~/Library/LaunchAgents")
end

require "every/color"
require "every/tail"
require "every/schedule"
require "every/store"
require "every/runtime"
require "every/launchd"
require "every/systemd"
require "every/backend"
require "every/runner"
require "every/doctor"
require "every/cli"
