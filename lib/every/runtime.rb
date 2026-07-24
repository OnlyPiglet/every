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

    STAMP = File.join(RUNTIME_DIR, ".version")

    # TCC only exists on macOS; on Linux these folder names carry no
    # restriction, so never copy there (a ~/Documents install stays live).
    def tcc_protected?(path)
      RUBY_PLATFORM.include?("darwin") &&
        !(path.to_s =~ %r{/(Documents|Desktop|Downloads)(/|\z)}).nil?
    end

    def needs_copy?
      tcc_protected?(ROOT) && !ROOT.start_with?(DATA_DIR)
    end

    # Refresh the copy only when missing or stale (version changed), and swap it
    # in atomically: build a sibling dir, then rename over the live one — never
    # rm_rf the directory the scheduler is executing from mid-copy.
    def ensure!
      return unless needs_copy?
      return if fresh?

      staging = "#{RUNTIME_DIR}.new"
      FileUtils.rm_rf(staging)
      FileUtils.mkdir_p(staging)
      FileUtils.cp_r(File.join(ROOT, "bin"), staging)
      FileUtils.cp_r(File.join(ROOT, "lib"), staging)
      FileUtils.chmod(0o755, File.join(staging, "bin", "every"))
      File.write(File.join(staging, ".version"), Every::VERSION)
      FileUtils.rm_rf(RUNTIME_DIR)
      File.rename(staging, RUNTIME_DIR)
      BIN
    end

    def fresh?
      File.exist?(BIN) && File.exist?(STAMP) && File.read(STAMP) == Every::VERSION
    rescue SystemCallError
      false
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
