#!/usr/bin/env bats
#
# Test suite for unit-health.
#
# The tests stub out `systemctl` and `ps` so they run on any machine,
# including CI runners and build environments without a booted systemd.
#
# Run from the project root with:   bats tests/test_service_health.bats
# Override the binary under test with:   SH_BIN=/usr/bin/unit-health bats ...

setup() {
    : "${SH_BIN:=$BATS_TEST_DIRNAME/../unit-health}"
    MOCKBIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$MOCKBIN"

    cat > "$MOCKBIN/systemctl" <<'MOCK'
#!/bin/bash
case "$1" in
  list-units)
    cat <<EOF
nginx.service        loaded active   running A high performance web server
postgresql.service   loaded active   running PostgreSQL database server
redis-server.service loaded active   running Advanced key-value store
mysql.service        loaded failed   failed  MySQL database server
custom-api.service   loaded active   running Custom API daemon
cron.service         loaded inactive dead    Regular background program
EOF
    ;;
  show)
    shift; units=(); VALUE=""; props=""
    for a in "$@"; do
      case "$a" in
        --property=*) props="${a#*=}";;
        --value) VALUE=1;;
        -*) ;;
        *) units+=("$a");;
      esac
    done
    emit() {
      case "$1" in
        nginx.service)        id=nginx.service load=loaded act=active sub=running pid=101 mem=47400000 nr=0 uf=enabled ts="Sun 2024-04-19 02:00:00 UTC" desc="A high performance web server";;
        postgresql.service)   id=postgresql.service load=loaded act=active sub=running pid=102 mem=262144000 nr=0 uf=enabled ts="Tue 2024-02-06 09:00:00 UTC" desc="PostgreSQL database server";;
        redis-server.service) id=redis-server.service load=loaded act=active sub=running pid=103 mem=15728640 nr=0 uf=enabled ts="Sat 2024-05-04 12:00:00 UTC" desc="Advanced key-value store";;
        mysql.service)        id=mysql.service load=loaded act=failed sub=failed pid=0 mem=18446744073709551615 nr=8 uf=enabled ts="" desc="MySQL database server";;
        custom-api.service)   id=custom-api.service load=loaded act=active sub=running pid=104 mem=524288000 nr=3 uf=disabled ts="Mon 2024-06-03 12:00:00 UTC" desc="Custom API daemon";;
        cron.service)         id=cron.service load=loaded act=inactive sub=dead pid=0 mem="[not set]" nr=0 uf=enabled ts="" desc="Regular background program";;
        *)                    id="$1" load=not-found act=inactive sub=dead pid=0 mem="[not set]" nr=0 uf="" ts="" desc="";;
      esac
      if [ -n "$VALUE" ]; then
        case "$props" in
          ActiveState) echo "$act";;
          Requires) echo "postgresql.service";;
          Wants) echo "redis-server.service";;
          *) echo "";;
        esac
        return
      fi
      printf 'Id=%s\nLoadState=%s\nActiveState=%s\nSubState=%s\nMainPID=%s\nMemoryCurrent=%s\nNRestarts=%s\nUnitFileState=%s\nExecMainStartTimestamp=%s\nDescription=%s\n' \
        "$id" "$load" "$act" "$sub" "$pid" "$mem" "$nr" "$uf" "$ts" "$desc"
    }
    first=1
    for u in "${units[@]}"; do [ $first -eq 1 ] || echo; first=0; emit "$u"; done
    ;;
  list-dependencies) echo "wordpress.service";;
  *) exit 0;;
esac
MOCK

    cat > "$MOCKBIN/ps" <<'MOCK'
#!/bin/bash
if printf '%s ' "$@" | grep -q -- '-eo'; then
  echo "101 0.2 46000"
  echo "102 1.5 256000"
  echo "103 0.1 15360"
  echo "104 47.0 512000"
else
  exit 0
fi
MOCK
    chmod +x "$MOCKBIN/systemctl" "$MOCKBIN/ps"
    PATH="$MOCKBIN:$PATH"
}

@test "--version prints the version" {
    run "$SH_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"unit-health 1.0.0"* ]]
}

@test "--help prints usage and exits 0" {
    run "$SH_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"--watch"* ]]
}

@test "unknown option exits 2" {
    run "$SH_BIN" --does-not-exist
    [ "$status" -eq 2 ]
}

@test "default table lists all services with a header" {
    run "$SH_BIN" --no-colors
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE"* ]]
    [[ "$output" == *"nginx"* ]]
    [[ "$output" == *"postgresql"* ]]
    [[ "$output" == *"mysql"* ]]
}

@test "uptime is formatted, not raw seconds" {
    run "$SH_BIN" nginx --no-colors
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+d\ [0-9]+h\ [0-9]+m ]]
}

@test "memory is human readable" {
    run "$SH_BIN" nginx --no-colors
    [[ "$output" == *"45.2MB"* ]]
}

@test "specific services filter the output" {
    run "$SH_BIN" nginx mysql --no-colors
    [[ "$output" == *"nginx"* ]]
    [[ "$output" == *"mysql"* ]]
    [[ "$output" != *"postgresql"* ]]
}

@test "--alerts shows failed but hides healthy services" {
    run "$SH_BIN" --alerts --no-colors
    [[ "$output" == *"mysql"* ]]
    [[ "$output" != *"nginx"* ]]
}

@test "--failed shows only failed services" {
    run "$SH_BIN" --failed --no-colors
    [[ "$output" == *"mysql"* ]]
    [[ "$output" != *"redis-server"* ]]
}

@test "non-existent service errors with exit 1" {
    run "$SH_BIN" nope-not-real --no-colors
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "--json output is valid JSON (skips if no python3)" {
    command -v python3 >/dev/null || skip "python3 not available"
    run bash -c "PATH='$MOCKBIN:$PATH' '$SH_BIN' --json nginx mysql | python3 -m json.tool"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name": "nginx"'* ]]
    [[ "$output" == *'"status": "failed"'* ]]
}

@test "config CPU threshold turns a busy service into a warning" {
    conf="$BATS_TEST_TMPDIR/c.conf"
    echo 'CPU_ALERT_THRESHOLD=40' > "$conf"
    run "$SH_BIN" --config "$conf" --alerts --no-colors
    [[ "$output" == *"custom-api"* ]]
}

@test "IGNORE_SERVICES removes a service from output" {
    conf="$BATS_TEST_TMPDIR/c.conf"
    echo 'IGNORE_SERVICES="cron"' > "$conf"
    run "$SH_BIN" --config "$conf" --no-colors
    [[ "$output" != *"cron"* ]]
}

@test "--dependencies highlights requires/wants" {
    run "$SH_BIN" mysql --dependencies --no-colors
    [[ "$output" == *"Requires:"* ]]
    [[ "$output" == *"postgresql"* ]]
}
