# service-health

A dependency-light command-line tool that reports the health of your
`systemd` services — status, uptime, memory, CPU, restart count and boot
state — in a colored table, as JSON, or live.

```
SERVICE                    STATUS      UPTIME         MEMORY     CPU     RESTARTS  ENABLED
-------------------------------------------------------------------------------------------
nginx                      ✅ running  45d 12h 3m     45.2MB     0.2%    0         yes
postgresql                 ✅ running  120d 5h 0m     250.0MB    1.5%    0         yes
redis-server               ✅ running  30d 2h 0m      15.0MB     0.1%    0         yes
mysql                      ❌ failed   -              -          -       8         yes
custom-api                 ⚠️ warning  2h 30m         500.0MB    47.0%   3         no
```

## Features

- All services at a glance in a colored, aligned table
- `--json` output for scripting and API integration
- `--watch` live monitoring
- `--alerts` / `--failed` to surface only what needs attention
- Per-service `--history`, `--logs` and `--dependencies`
- Configurable warning thresholds and an ignore list
- Honors `NO_COLOR`; degrades gracefully without root
- Depends only on **bash**, **systemd** and **coreutils** — no network required

## Installation

### From a `.deb`

```sh
sudo apt install ./service-health_1.0.0-1_all.deb
```

### From source

```sh
sudo install -m 0755 service-health /usr/bin/service-health
sudo install -m 0644 service-health.1 /usr/share/man/man1/service-health.1
sudo mkdir -p /etc/service-health
sudo install -m 0644 config.conf /etc/service-health/config.conf
```

### Build the Debian package

```sh
sudo apt install build-essential debhelper devscripts lintian
dpkg-buildpackage -us -uc -b
lintian ../service-health_*.deb
```

## Usage

```sh
service-health                      # table of all services
service-health nginx postgresql     # only these services
service-health --alerts             # only problems / warnings
service-health --failed             # only failed units, with last error
service-health --json --no-colors   # machine-readable output
service-health --watch --interval 5 # live view, refresh every 5s
service-health nginx --logs --lines 50
service-health nginx --history --days 14
service-health mysql --dependencies
service-health --detailed nginx
service-health --help
```

### JSON fields

`name`, `status`, `uptime_seconds`, `memory_mb`, `cpu_percent`,
`restart_count_24h`, `enabled_on_boot`, `last_error`. Unavailable numeric
values are `null`.

## Configuration

`service-health` sources `/etc/service-health/config.conf` if present (or the
file given with `--config`). See [`config.conf`](config.conf) for all
settings: `IGNORE_SERVICES`, `CPU_ALERT_THRESHOLD`, `MEMORY_ALERT_THRESHOLD`,
`RESTART_ALERT_THRESHOLD`, `USE_COLORS`, `DEFAULT_FORMAT`, `WATCH_INTERVAL`.

## Exit status

| Code | Meaning |
|------|---------|
| 0 | Success (including "no services found") |
| 1 | Service not found, or systemd unavailable |
| 2 | Invalid command-line usage |

## Development

### Tests

The test suite stubs `systemctl` and `ps`, so it runs anywhere — no booted
systemd required:

```sh
sudo apt install bats
bats tests/test_service_health.bats
```

Lint the script and the man page:

```sh
shellcheck service-health
groff -man -Tutf8 -ww -z service-health.1
```

### Design notes / deliberate choices

- **No `set -o errexit`.** A monitoring tool runs many commands that return
  non-zero in normal operation (`systemctl is-enabled` on a disabled unit,
  `grep -c` with zero matches, `journalctl` without privileges). `errexit`
  would abort on those, so failures are handled explicitly instead;
  `pipefail` is enabled.
- **One bulk `systemctl show`** for all units (parsed with `awk`), plus a
  single `ps` call, keeps a full run well under the performance budget.
- **Restart count.** The table shows systemd's `NRestarts` counter (instant,
  cheap). The journal-based 24h view lives in `--history`, because running
  `journalctl` once per service would blow the latency budget.
- **Emoji width.** Column padding assumes the status emoji render as two
  cells. On terminals that render the variation-selector emoji
  (`⚠️`, `⏸️`) as one cell, a column may shift by one.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
