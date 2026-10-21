#!/bin/sh

## @file parse_test.sh
## @brief Tests for ping.sh's parsing and row formatting.
## @description
## Exercises `ping.sh --list`, which parses the IP file and prints the rows it
## would ping without sending any packets or webhooks. Run: ./tests/parse_test.sh

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ping_sh="$test_dir/../ping.sh"
fixture="$test_dir/fixtures/sample_ips.txt"

failures=0

# Collapse runs of spaces so content assertions don't depend on column widths;
# alignment is checked separately below.
squeeze() {
    tr -s ' '
}

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

out=$("$ping_sh" --list --file "$fixture" 2>&1)

# --- content, field order, and filtering ----------------------------------

check "lists ip, location, then network type" \
    "121.120.41.25 Taman Bandar simcard" \
    "$(printf '%s\n' "$out" | squeeze | grep 'Taman Bandar')"

check "skips OFFICE entries" \
    "" \
    "$(printf '%s\n' "$out" | grep -i 'office')"

check "skips comment and blank lines" \
    "" \
    "$(printf '%s\n' "$out" | grep -e '^#' -e '^[[:space:]]*$')"

check "drops the trailing port field from the location" \
    "121.120.38.219 Dataran PPJ Male simcard" \
    "$(printf '%s\n' "$out" | squeeze | grep 'Dataran PPJ Male')"

check "drops a disabled port field too" \
    "121.120.209.108 MBSA Tasik Barat WB01 simcard" \
    "$(printf '%s\n' "$out" | squeeze | grep 'MBSA')"

check "keeps slashes inside a location" \
    "183.171.15.14 Souq Kanan / Medan Selera Putra OKU simcard" \
    "$(printf '%s\n' "$out" | squeeze | grep 'Medan Selera')"

check "accepts a hostname in place of an ip" \
    "mps-gym.local Gym Selayang vpn" \
    "$(printf '%s\n' "$out" | squeeze | grep 'Gym Selayang')"

check "lowercases the network type" \
    "10.21.3.151 B13 Male vpn" \
    "$(printf '%s\n' "$out" | squeeze | grep 'B13 Male')"

check "emits one row per non-OFFICE entry" \
    "6" \
    "$(printf '%s\n' "$out" | grep -c .)"

# --- alignment ------------------------------------------------------------

check "aligns the network type into a single column" \
    "1" \
    "$(printf '%s\n' "$out" | awk 'match($0, /[a-z]+$/) { print RSTART }' | sort -u | grep -c .)"

# --- summary --------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    printf '\nall tests passed\n'
    exit 0
fi

printf '\n%d test(s) failed\n' "$failures"
exit 1
