#!/bin/sh

## @file report_test.sh
## @brief Tests for the CSV run report ping.sh writes.
## @description
## Pings only loopback and a TEST-NET-1 blackhole address, and points
## WEBHOOK_URL at a closed local port, so no real host is contacted and no
## Teams alert is sent. Run: ./tests/report_test.sh

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ping_sh="$test_dir/../ping.sh"

failures=0

check() {
    name="$1"
    expected="$2"
    actual="$3"

    if [ "$expected" = "$actual" ]; then
        printf 'ok   - %s\n' "$name"
    else
        failures=$((failures + 1))
        printf 'FAIL - %s\n' "$name"
        printf '  expected:\n'
        printf '%s\n' "$expected" | sed 's/^/    |/'
        printf '  actual:\n'
        printf '%s\n' "$actual" | sed 's/^/    |/'
    fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/hosts.txt" <<'EOF'
# fixture
127.0.0.1        (SIMCARD - Loopback Reachable)
192.0.2.1        (VPN - TEST-NET Blackhole - port 3000)
192.168.1.246    (OFFICE - Should Be Skipped)
EOF

run_ping() {
    WEBHOOK_URL="http://127.0.0.1:9/sink" \
        "$ping_sh" --file "$work/hosts.txt" --reports-dir "$1" >/dev/null 2>&1
}

# --- a report is written ---------------------------------------------------

out_dir="$work/reports"
run_ping "$out_dir"

check "creates the reports directory if missing" \
    "yes" \
    "$([ -d "$out_dir" ] && echo yes || echo no)"

check "writes exactly one report per run" \
    "1" \
    "$(find "$out_dir" -type f | grep -c .)"

report=$(find "$out_dir" -type f | head -1)

check "names the file ping-<YYYYMMDD>-<HHMMSS>.csv" \
    "match" \
    "$(basename "$report" | grep -qE '^ping-[0-9]{8}-[0-9]{6}\.csv$' && echo match || echo "no match: $(basename "$report")")"

# --- contents --------------------------------------------------------------

check "header names the columns" \
    "timestamp,ip,location,network,status" \
    "$(head -1 "$report")"

check "one data row per pinged host, OFFICE excluded" \
    "2" \
    "$(tail -n +2 "$report" | grep -c .)"

check "records a reachable host" \
    "127.0.0.1,Loopback Reachable,simcard,reachable" \
    "$(grep '127\.0\.0\.1' "$report" | cut -d, -f2-)"

check "records an unreachable host and drops its port" \
    "192.0.2.1,TEST-NET Blackhole,vpn,unreachable" \
    "$(grep '192\.0\.2\.1' "$report" | cut -d, -f2-)"

check "omits OFFICE entries from the report" \
    "" \
    "$(grep -i 'office\|192\.168\.1\.246' "$report")"

# --- timestamp -------------------------------------------------------------

stamps=$(tail -n +2 "$report" | cut -d, -f1 | sort -u)

check "stamps every row with one ISO-8601 UTC run time" \
    "1" \
    "$(printf '%s\n' "$stamps" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')"

# --- --list writes nothing -------------------------------------------------

list_dir="$work/list-reports"
"$ping_sh" --list --file "$work/hosts.txt" --reports-dir "$list_dir" >/dev/null 2>&1

check "--list writes no report" \
    "0" \
    "$(find "$list_dir" -type f 2>/dev/null | grep -c .)"

# --- csv quoting -----------------------------------------------------------

cat > "$work/comma.txt" <<'EOF'
127.0.0.1        (SIMCARD - Kuala Lumpur, Selangor)
EOF

quote_dir="$work/quote-reports"
WEBHOOK_URL="http://127.0.0.1:9/sink" \
    "$ping_sh" --file "$work/comma.txt" --reports-dir "$quote_dir" >/dev/null 2>&1

quote_report=$(find "$quote_dir" -type f 2>/dev/null | head -1)

check "quotes a location containing a comma" \
    '127.0.0.1,"Kuala Lumpur, Selangor",simcard,reachable' \
    "$([ -n "$quote_report" ] && cut -d, -f2- "$quote_report" | tail -1)"

# --- summary ---------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    printf '\nall tests passed\n'
    exit 0
fi

printf '\n%d test(s) failed\n' "$failures"
exit 1
