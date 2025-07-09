#!/bin/sh

## @file ping.sh
## @brief Ping a list of IPs (with optional aliases) from a file.
## @description
## This script reads a list of IP addresses from a text file (ips.txt),
## optionally with aliases in parentheses (e.g. "1.1.1.1 (cloudflare)"),
## and pings each one. Results are printed in an aligned, readable format.
## Press Ctrl+C to stop execution at any time.

# ===============================
# Configuration
# ===============================

ip_file="ips.txt"
interrupted=0

# ANSI color codes
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

# ===============================
# Signal Handling
# ===============================

trap 'interrupted=1; echo "\nInterrupted. Exiting..."; exit 1' INT

# ===============================
# Functions
# ===============================

ping_ip() {
    ip="$1"
    alias="$2"

    if [ "$interrupted" -eq 1 ]; then
        exit 1
    fi

    if [ -n "$alias" ]; then
        printf "ping %-15s %-18s: " "$ip" "($alias)"
    else
        printf "ping %-15s %-18s: " "$ip" ""
    fi

    if ping -c 1 -W 1 "$ip" > /dev/null 2>&1; then
        printf "${COLOR_GREEN}reachable${COLOR_RESET}\n"
    else
        printf "${COLOR_RED}unreachable${COLOR_RESET}\n"
    fi
}

# ===============================
# Main Execution
# ===============================

if [ -f "$ip_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ "$interrupted" -eq 1 ] && break
        [ -z "$line" ] && continue

        ip=$(echo "$line" | sed -E 's/\s*\(.*\)//')
        alias=$(echo "$line" | sed -nE 's/.*\(([^)]*)\).*/\1/p')

        ping_ip "$ip" "$alias"
    done < "$ip_file"
else
    echo "IP file '$ip_file' not found."
    exit 1
fi
