module Every
  # launchd-spawned processes cannot read TCC-protected folders (Documents,
  # Desktop, Downloads) — if the tool itself lives there, every scheduled run
  # dies with "Operation not permitted" before our code even loads. So we
  # mirror bin/ + lib/ into the (unprotected) data dir and point plists at
  # that copy. Refreshed on every add/resume, so dev edits propagate.
  module Runtime
    RUNTIME_DIR = File.join(DATA_DIR, "runtime")
    BIN = File.join(RUNTIME_DIR, "bin", "every")

    module_function

    def ensure!
      return Every::BIN if ROOT.start_with?(DATA_DIR)

      FileUtils.rm_rf(RUNTIME_DIR)
      FileUtils.mkdir_p(RUNTIME_DIR)
      FileUtils.cp_r(File.join(ROOT, "bin"), RUNTIME_DIR)
      FileUtils.cp_r(File.join(ROOT, "lib"), RUNTIME_DIR)
      FileUtils.chmod(0o755, BIN)
      BIN
    end

    def bin
      ROOT.start_with?(DATA_DIR) ? Every::BIN : BIN
    end
  end
end
