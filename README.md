# every

**Schedule anything on your Mac. Actually know it ran.**

cron never tells you it silently skipped your backup. launchd wants 40 lines of
XML before ignoring you too. `every` is one human phrase — and a straight
answer to *"did it run?"*.

```bash
every day 9am -- brew update
every 30m -- '~/bin/sync-notes.sh'
every monday 10:00 -- './weekly-report.sh'
```

```
$ every list
NAME           SCHEDULE      LAST          STATUS   NEXT
brew           day 9am       24 Jul 09:00  ok       25 Jul 09:00
sync-notes     30m           24 Jul 14:30  ok       24 Jul 15:00
weekly-report  monday 10:00  21 Jul 10:00  FAIL(1)  28 Jul 10:00

$ every log weekly-report     # exact output of the run that broke
$ every doctor                # plain-language diagnosis
```

## vs cron · vs raw launchd

|  | cron | raw launchd | **every** |
|---|---|---|---|
| Add a job | `30 9 * * 1` in `crontab -e` | ~40 lines of XML + `launchctl` | `every monday 9:30 -- cmd` |
| Did it run? | silence | silence | `every list` → ok / FAIL |
| What did it print? | a local mailbox nobody reads | wire log paths yourself | `every log <name>` |
| Mac was asleep at 9am | run **lost forever** | runs on wake | runs on wake — and you can verify it |
| PATH | minimal, brew tools "not found" | minimal | your login shell, as in your terminal |
| Working directory | `$HOME`, always | configure it yourself | the directory you added the task from |
| A run fails | nothing happens | nothing happens | macOS notification + `FAIL` in `list` |
| When it breaks | Console.app archaeology | Console.app archaeology | `every doctor` tells you why |

Apple deprecated cron on macOS years ago. `every` is launchd — with a human
interface and a memory.

## Install

```bash
git clone https://github.com/Serhii-Leniv/every.git
ln -s "$PWD/every/bin/every" /usr/local/bin/every
```

Zero dependencies. Runs on the Ruby already inside macOS.

## Schedules

| You type | It means |
|---|---|
| `90s` · `15m` · `2h` | fixed interval |
| `hourly` | every hour |
| `day 9am` · `day 17:30` | daily at that time |
| `day 9am,6pm` | daily, several times |
| `weekdays 9:30` · `weekends 11am` | Mon–Fri / Sat+Sun |
| `monday 10:00` · `monday,thursday 6pm` | weekly on those days |

## Commands

```
every <schedule> [--name NAME] [--quiet] -- <command>   schedule it
every list                                    status of everything
every log <name> [-n N]                       output of recent runs
every run <name>                              run it right now, see the output
every pause / resume <name>                   stop / start scheduling
every rm <name>                               remove (logs are kept)
every doctor                                  why isn't it running?
```

Failed runs pop a macOS notification (silence it per task with `--quiet`).

## Fine print

- **Quoting:** your shell strips quotes first — wrap complex commands in one
  string: `every day 9am -- 'psql -c "select 1" | tee ~/log.txt'`.
- Tasks live in `~/Library/LaunchAgents/com.every.<name>.plist`; runs are
  recorded under `~/.local/share/every/` (logs rotate at 5 MB). launchd can't
  execute from TCC-protected folders, so agents run a copy of `every` from the
  data dir — see [DECISIONS.md](DECISIONS.md) for design notes.
- macOS only for now; Linux (systemd user timers) is the planned v2.
- Uninstall: `every rm` each task, then `rm -rf ~/.local/share/every`.

MIT © [Serhii Leniv](https://github.com/Serhii-Leniv)
