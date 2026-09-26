# sysboard

Terminal dashboard for everything running or scheduled on the machine:
systemd services (system + user), timers, docker containers, cron jobs,
and autostart apps.

## Usage

    sysboard                  # interactive TUI
    sysboard --report         # one-shot pretty report
    sysboard --section docker # report: only docker; TUI: start on docker tab
    sysboard --no-auto        # disable auto-refresh
    sysboard --refresh 10     # refresh every 10s

Falls back to `--report` mode when stdin is not a terminal.

## Keys (TUI)

| Key | Action |
|---|---|
| `j`/`k`, arrows | move selection (`g`/`G` top/bottom) |
| `1`-`6`, `Tab` | switch section |
| `s` / `t` / `r` | stop / start / restart (systemd, docker) |
| `e` | toggle enable/disable (systemd) |
| `l` | view logs (`journalctl` / `docker logs`, via `$PAGER`) |
| `R` | refresh now |
| `?` | help overlay |
| `q` | quit |

System-level systemd actions prompt for sudo (the TUI leaves the alternate
screen for the password prompt, then redraws). Docker actions assume the
user is in the `docker` group. Cron and autostart sections are read-only.

## Sections

1. **System services** — `systemctl list-units` + enabled state from `list-unit-files`
2. **User services** — same, `--user`
3. **Timers** — user + system, next/last trigger via `systemctl show`
4. **Docker** — `docker ps -a` (all states; paused shown as `paused`)
5. **Cron** — `crontab -l` + `/etc/cron.d/*`
6. **Autostart** — `~/.config/autostart` + `/etc/xdg/autostart` (system entries dimmed)

## Testing

    bash tests/sysboard_test.sh

Collectors are unit-tested with function mocks (`systemctl`, `docker`,
`crontab` are overridden as shell functions; bash resolves functions before
PATH binaries). Path overrides for tests: `SYSBOARD_CRON_D`,
`SYSBOARD_USER_AUTOSTART`, `SYSBOARD_SYSTEM_AUTOSTART`,
`SYSBOARD_FORCE_TUI=1`.
