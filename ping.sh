#!/bin/sh

## @file ping.sh
## @brief Ping the Smart Toilet hosts and report reachability per site.
## @description
## Reads device_status/ips.txt, whose entries look like
## "121.120.38.219 (SIMCARD - Dataran PPJ Male - port 3000)", and pings each
## one. Results are printed as: ip, location, network type, status.
##
## OFFICE entries are skipped: they are 192.168.1.x addresses reachable only
## from on-site, so off-site runs would report every one of them as down.
## A recorded port is an SSH port-forward and is not shown -- ping is ICMP and
## has no port.
##
## Each run also writes a CSV to reports/ping-<YYYYMMDD>-<HHMMSS>.csv (UTC).
## That directory is gitignored: a report lists every endpoint and its status.
##
## Usage:
##   ./ping.sh                      # ping every host
##   ./ping.sh --list               # show the parsed rows, ping nothing
##   ./ping.sh --file other.txt     # read a different list
##   ./ping.sh --reports-dir DIR    # write the report somewhere else
##
## Press Ctrl+C to stop execution at any time.

# ===============================
# Configuration
# ===============================

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ip_file="$script_dir/device_status/ips.txt"
WEBHOOK_URL="${WEBHOOK_URL:-https://vectolabstech.webhook.office.com/webhookb2/ae84141d-717b-48f1-a1f2-62b862fb49c9@2f93bc5c-a4d9-4282-9997-e0a857264050/IncomingWebhook/a0d93dcf84a340db8332681eac004276/474cd912-c130-4b62-ad2c-e0f699702482/V2e8SI-OInh9H7UhsEZdGLjEocrUuD151XomNhcL2GyiE1}"
reports_dir="$script_dir/reports"
interrupted=0
list_only=0

# One run time, stamped on every row so a report's rows share a key.
run_stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_slug=$(date -u +%Y%m%d-%H%M%S)

# Network types that are never pinged.
SKIP_TYPES="office"

# Column layout for the ip and location fields; the type column follows.
FIELD_FMT='%-16s %-40s '

# ANSI color codes. Built with printf so they hold real escape bytes and can be
# passed as %s arguments rather than spliced into a format string.
COLOR_GREEN=$(printf '\033[0;32m')
COLOR_RED=$(printf '\033[0;31m')
COLOR_RESET=$(printf '\033[0m')

# ===============================
# Signal Handling
# ===============================

trap 'interrupted=1; printf "\nInterrupted. Exiting...\n"; exit 1' INT

# ===============================
# Functions
# ===============================

usage() {
    sed -n 's/^## \{0,1\}//p' "$0" | sed -n '/^Usage:/,/^$/p'
}

## Split an entry body -- "SIMCARD - Dataran PPJ Male - port 3000" -- into a
## lowercase type and a location, dropping any trailing port field.
parse_body() {
    body="$1"

    case "$body" in
        *" - "*) ;;
        *) return 1 ;;
    esac

    type=$(printf '%s' "${body%% - *}" | tr '[:upper:]' '[:lower:]')
    location=$(printf '%s' "${body#* - }" |
        sed -E 's/[[:space:]]*-[[:space:]]*port[[:space:]]+[0-9]+.*$//')

    [ -n "$type" ] && [ -n "$location" ]
}

## Quote a CSV field only when it needs it. The IP list is hand-edited, so a
## comma in a location is a matter of time.
csv_field() {
    case "$1" in
        *,*|*\"*) printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')" ;;
        *) printf '%s' "$1" ;;
    esac
}

append_report() {
    printf '%s,%s,%s,%s,%s\n' \
        "$run_stamp" \
        "$(csv_field "$1")" \
        "$(csv_field "$2")" \
        "$(csv_field "$3")" \
        "$4" >> "$report_file"
}

ping_host() {
    host="$1"
    location="$2"
    type="$3"

    if [ "$interrupted" -eq 1 ]; then
        exit 1
    fi

    printf "$FIELD_FMT%-9s" "$host" "$location" "$type"

    if ping -c 1 -W 1 "$host" > /dev/null 2>&1; then
        printf '%sreachable%s\n' "$COLOR_GREEN" "$COLOR_RESET"
        append_report "$host" "$location" "$type" "reachable"
    else
        printf '%sunreachable%s\n' "$COLOR_RED" "$COLOR_RESET"
        append_report "$host" "$location" "$type" "unreachable"
        sendTeamWebhook "$host" "$location" "$type"
    fi
}

sendTeamWebhook() {
    host="$1"
    location="$2"
    type="$3"

    curl -sS -o /dev/null -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{
            \"title\": \"Feedbackpanel unreachable\",
            \"text\": \"${location} - ${type} - (${host})\",
            \"themeColor\": \"FF0000\"
          }"
}

# ===============================
# Argument Parsing
# ===============================

while [ "$#" -gt 0 ]; do
    case "$1" in
        --list) list_only=1 ;;
        -f|--file)
            [ -n "$2" ] || { echo "$1 needs a file path." >&2; exit 2; }
            ip_file="$2"
            shift
            ;;
        --reports-dir)
            [ -n "$2" ] || { echo "$1 needs a directory path." >&2; exit 2; }
            reports_dir="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ===============================
# Main Execution
# ===============================

if [ ! -f "$ip_file" ]; then
    echo "IP file '$ip_file' not found." >&2
    exit 1
fi

# --list pings nothing, so there is no result to record.
if [ "$list_only" -eq 0 ]; then
    mkdir -p "$reports_dir" || exit 1
    report_file="$reports_dir/ping-$run_slug.csv"
    echo "timestamp,ip,location,network,status" > "$report_file"
fi

while IFS= read -r line || [ -n "$line" ]; do
    [ "$interrupted" -eq 1 ] && break

    # Strip leading whitespace, then drop blanks and comments.
    line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    host=$(printf '%s' "$line" | sed -E 's/^([^[:space:]]+).*/\1/')
    body=$(printf '%s' "$line" | sed -nE 's/^[^(]*\(([^)]*)\).*/\1/p')

    if [ -z "$body" ] || ! parse_body "$body"; then
        echo "warning: cannot parse: $line" >&2
        continue
    fi

    case " $SKIP_TYPES " in *" $type "*) continue ;; esac

    if [ "$list_only" -eq 1 ]; then
        printf "$FIELD_FMT%s\n" "$host" "$location" "$type"
    else
        ping_host "$host" "$location" "$type"
    fi
done < "$ip_file"

if [ "$list_only" -eq 0 ]; then
    printf '\n%s reachable, %s unreachable\n' \
        "$(grep -c ',reachable$' "$report_file")" \
        "$(grep -c ',unreachable$' "$report_file")"
    printf 'Report: %s\n' "$report_file"
fi
