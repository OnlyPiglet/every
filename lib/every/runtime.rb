module Every
  # launchd/systemd-spawned processes can't read TCC-protected folders on macOS
  # (Documents, Desktop, Downloads) — if the tool lives there, every scheduled
  # run dies with "Operation not permitted" before our code even loads. So when
  # (and ONLY when) the install sits in such a folder, we mirror bin/ + lib/
  # into the unprotected data dir and point the scheduler at that copy.
  #
  # Everywhere else — Homebrew, /usr/local, ~/code — the scheduler invokes the
  # installed launcher directly, so `brew upgrade` (or a git pull) takes effect
  # on the next run instead of freezing old code into a copy.
  module Runtime
    RUNTIME_DIR = File.join(DATA_DIR, "runtime")
    BIN = File.join(RUNTIME_DIR, "bin", "every")

    module_function

    def tcc_protected?(path)
      !(path.to_s =~ %r{/(Documents|Desktop|Downloads)(/|\z)}).nil?
    end

    def needs_copy?
      tcc_protected?(ROOT) && !ROOT.start_with?(DATA_DIR)
    end

    def ensure!
      return unless needs_copy?

      FileUtils.rm_rf(RUNTIME_DIR)
      FileUtils.mkdir_p(RUNTIME_DIR)
      FileUtils.cp_r(File.join(ROOT, "bin"), RUNTIME_DIR)
      FileUtils.cp_r(File.join(ROOT, "lib"), RUNTIME_DIR)
      FileUtils.chmod(0o755, BIN)
      BIN
    end

    # Path the scheduler should invoke. When a copy is required, the stable copy.
    # Otherwise the launcher exactly as invoked — for a Homebrew install that's
    # the /opt/homebrew/bin/every symlink, which survives version upgrades.
    def bin
      return BIN if needs_copy?
      launcher = File.expand_path($PROGRAM_NAME)
      File.exist?(launcher) ? launcher : Every::BIN
    end
  end
end
