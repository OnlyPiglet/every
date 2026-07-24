# every — design decisions (v0.1)

Dated log; append, don't rewrite.

- **2026-07-24 — Pure stdlib, system-Ruby compatible (2.6+).** No gems, so the
  tool runs on the Ruby that ships with macOS and needs zero install steps.
  Distribution later = Homebrew formula (brew itself vendors Ruby).
- **2026-07-24 — launchd agent calls `every run <name>`, not the command
  directly.** The runner is what captures output/exit/duration into
  `~/.local/share/every` — visibility is the product; plists alone can't do it.
- **2026-07-24 — Commands execute via `/bin/zsh -lc` (login shell), chdir'd to
  the directory where the task was added.** Kills the two classic launchd traps
  (PATH differs from terminal; wrong cwd). Known limit: `-l` reads `.zprofile`,
  not `.zshrc` — `doctor` explains this when a command doesn't resolve.
- **2026-07-24 — `launchctl bootstrap/bootout` (modern API) with `load -w`
  fallback.** On conflict, bootout + retry.
- **2026-07-24 — State layout:** tasks in `tasks.json`; per-task run history as
  JSONL (`runs/<name>.jsonl`); raw output in `logs/<name>.log` with `===`
  headers; 5 MB rotation to `.old`. `EVERY_HOME` env var overrides the data dir
  (used by tests).
- **2026-07-24 — Schedule DSL kept tiny:** `Ns/Nm/Nh`, `hourly`, `day <time>`,
  `<weekday> <time>`. No cron expressions in v1 — the whole point is not being
  cron.
- **2026-07-24 — Plists execute a runtime copy in `~/.local/share/every/runtime`,
  never the checkout.** Found by a live fire test: launchd-spawned ruby gets
  "Operation not permitted" reading anything under TCC-protected folders
  (Documents/Desktop/Downloads), so an agent pointing into the project checkout
  dies before our code loads. The copy is refreshed on every add/resume;
  `doctor` checks for its presence and warns about TCC-protected task cwd.
- **2026-07-24 — No git yet.** Working account on this machine is a work
  account; repo stays local until published from the right identity
  (bohdan-ai-gh).
