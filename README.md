# every

Schedule anything on your Mac, humanely. `every` is a tiny CLI that turns one
human phrase into a correctly configured `launchd` agent — and, unlike raw
launchd/cron, it always shows you **whether the thing actually ran** and what
it printed.

```bash
every 15m -- ~/bin/sync-notes.sh
every hourly -- brew update
every day 9am -- ruby ~/bin/report.rb
every monday 10:00 --name weekly-report -- ~/bin/weekly.sh

every list          # what's scheduled · last run · ok/FAIL · next run
every log brew      # stdout/stderr of recent runs
every doctor        # plain-language diagnosis of why something isn't running
every pause brew    # stop scheduling, keep the task
every resume brew
every rm brew       # remove (logs are kept)
```

No dependencies — pure Ruby stdlib, runs on the system Ruby that ships with
macOS. Nothing to `gem install`.

## Install (local, for now)

```bash
chmod +x ~/Documents/Projects/every/bin/every
ln -s ~/Documents/Projects/every/bin/every ~/bin/every   # or anywhere on PATH
```

## Schedule syntax

| Phrase | Meaning |
|---|---|
| `90s`, `15m`, `2h` | fixed interval (min 10s) |
| `hourly` | every hour |
| `day 9am`, `day 17:30` | daily at that time |
| `monday 10:00`, `friday 6pm` | weekly on that day |

## How it works

- Each task becomes `~/Library/LaunchAgents/com.every.<name>.plist`, loaded via
  `launchctl bootstrap`. The agent invokes `every run <name>`.
- The agent runs a **copy** of every from `~/.local/share/every/runtime/`
  (refreshed on add/resume). launchd-spawned processes can't read
  TCC-protected folders (Documents/Desktop/Downloads), so executing from a
  project checkout inside Documents would fail with "Operation not permitted".
- `every run` executes your command through **your login shell**
  (`/bin/zsh -lc`), in **the directory where you added the task** — so PATH and
  relative paths behave like your terminal, dodging launchd's classic PATH trap.
- Output and exit codes are captured to `~/.local/share/every/logs/<name>.log`
  and `~/.local/share/every/runs/<name>.jsonl` — that's what powers
  `list`/`log`/`doctor`.

## Good to know

- **Quoting:** your shell strips quotes before `every` sees the command. Wrap
  anything with flags-in-quotes or pipes in ONE quoted string:
  `every day 9am -- 'psql -c "select 1" | tee ~/log.txt'`.

- **Sleep:** interval tasks run only while the Mac is awake. Missed *calendar*
  tasks (`day 9am`) fire once when the Mac next wakes — launchd coalesces them.
- **PATH:** the login shell reads `~/.zprofile`, not `~/.zshrc`. If a command
  works in your terminal but `doctor` says it's not resolvable, move its PATH
  setup to `~/.zprofile` or use an absolute path.
- **Full Disk Access:** if a task touches protected folders (Documents,
  Desktop…) and logs show `Operation not permitted`, grant Full Disk Access to
  the ruby binary in System Settings → Privacy & Security.
- Logs rotate at 5 MB (previous file kept as `.log.old`).

## Uninstall

```bash
every list            # then `every rm <name>` for each task
rm -rf ~/.local/share/every
```

## Status

v0.1.0 — local project, macOS only. Linux (systemd user timers) is the planned
v2. See `DECISIONS.md` for design choices.
