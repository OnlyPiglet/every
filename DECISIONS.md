# every — design decisions

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
- **2026-07-24 — Calendar schedules are entry lists.** `Schedule` normalizes
  every calendar form (`day 9am,6pm`, `weekdays 9:30`, `monday,thursday 10:00`) into a
  list of `{weekday?, hour, minute}` entries → launchd `StartCalendarInterval` array.
  `from_h` migrates pre-0.2 `daily`/`weekly` task records, so existing tasks survive.
  Bounded intervals ("every 5m, 9–18, weekdays") deliberately NOT supported — launchd
  has no such primitive and faking it (108 dicts / runner-side guard) isn't worth it yet.
- **2026-07-24 — Failures notify by default.** A failed run fires a macOS
  notification via `osascript` (`--quiet` per task to opt out). Rationale: the product
  is visibility; a FAIL that waits for the user to run `list` is still silence.
- **2026-07-24 — No git yet.** Working account on this machine is a work
  account; repo stays local until published from the right identity.
- **2026-07-24 — Backend abstraction + Linux beta.** `Backend.current`
  dispatches launchd (darwin) / systemd user timers (linux); both implement
  write/enable/disable/delete_units/loaded?/unit_path. systemd side:
  service+timer pair per task, `Persistent=true` mirrors launchd's
  missed-run-on-wake catch-up, runner uses `$SHELL -lc` on Linux and
  notify-send for failure alerts. Beta honesty: unit generation is tested
  (unit tests + systemd-analyze in CI on ubuntu-latest), live end-to-end on a
  real Linux desktop is NOT yet — hence "beta" and a call for field reports.
- **2026-07-24 — Published (supersedes "No git yet"):**
  github.com/Serhii-Leniv/every, authored as Serhii-Leniv via a dedicated
  `github-serhii` ssh alias; repo-local identity + pre-commit/pre-push guard
  hooks prevent any other account from committing or pushing here.
