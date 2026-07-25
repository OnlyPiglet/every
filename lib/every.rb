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

  # Data dir precedence: EVERY_HOME (explicit) → $XDG_DATA_HOME/every →
  # ~/.local/share/every (the XDG default anyway, so existing installs are
  # unchanged). Per the XDG spec, a non-absolute XDG_DATA_HOME is ignored.
  def self.resolve_data_dir(env = ENV)
    xdg = env["XDG_DATA_HOME"].to_s
    File.expand_path(
      env["EVERY_HOME"] ||
        (xdg.start_with?("/") ? File.join(xdg, "every") : "~/.local/share/every")
    )
  end

  # systemd user units live under $XDG_CONFIG_HOME/systemd/user (default
  # ~/.config/systemd/user). Non-absolute XDG_CONFIG_HOME is ignored.
  def self.resolve_config_dir(env = ENV)
    xdg = env["XDG_CONFIG_HOME"].to_s
    xdg.start_with?("/") ? File.join(xdg, "systemd", "user")
                         : File.expand_path("~/.config/systemd/user")
  end

  DATA_DIR   = resolve_data_dir
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
