# ping_ips

Pings the Smart Toilet hosts and reports reachability per site.

## Usage

```sh
./ping.sh                      # ping every host
./ping.sh --list               # show the parsed rows, ping nothing
./ping.sh --file other.txt     # read a different list
./ping.sh --reports-dir DIR    # write the report somewhere else
```

Output is one row per site — ip, location, network type, status:

```
121.120.41.25    Taman Bandar                             simcard  reachable
10.21.3.151      B13 Male                                 vpn      unreachable

31 reachable, 23 unreachable
Report: /app/reports/ping-20261021-031720.csv
```

Press Ctrl+C to stop at any time.

## Results

Every run writes a CSV to `reports/ping-<YYYYMMDD>-<HHMMSS>.csv`, stamped in
UTC, one file per run:

```csv
timestamp,ip,location,network,status
2026-10-21T03:17:20Z,121.120.41.25,Taman Bandar,simcard,reachable
2026-10-21T03:17:20Z,10.21.3.151,B13 Male,vpn,unreachable
```

Every row in a file carries the same `timestamp`, so runs stay distinguishable
once the files are concatenated for trending. Fields are quoted only when they
contain a comma or a quote.

`reports/` is gitignored — a report lists every endpoint and its status. The
pattern has no leading path, so it matches at any depth, covering both this
directory and `device_status/reports/`.

`--list` pings nothing, so it writes no report.

## Source list

Hosts come from `device_status/ips.txt`, one entry per line:

```
<ip> (<TYPE> - <Location>[ - port NNNN])
```

`TYPE` is `SIMCARD`, `VPN`, or `OFFICE`. Blank lines and `#` comments are
skipped, and an unparseable line is reported on stderr rather than silently
dropped.

Two things about the list are worth knowing:

- **`OFFICE` entries are never pinged.** They are `192.168.1.x` addresses
  reachable only from on-site, so an off-site run would report all 14 as down
  and alert on each. `gen_inventory.py` excludes them for the same reason.
- **A recorded port is not shown.** It is an SSH port-forward; ping is ICMP and
  has no port. Sites that share one public IP on different ports therefore
  produce identical pings — one row each, so every site still gets a line.

## Alerts

An unreachable host POSTs to a Microsoft Teams incoming webhook with the
location, network type, and ip. Override the target with `WEBHOOK_URL` in the
environment — useful for testing without alerting the real channel:

```sh
WEBHOOK_URL="http://127.0.0.1:9/sink" ./ping.sh
```

## Tests

```sh
./tests/parse_test.sh     # parsing and row formatting, via --list
./tests/report_test.sh    # the CSV report
```

`parse_test.sh` runs through `--list`, so it sends no packets at all.
`report_test.sh` has to ping, so it only touches loopback and a TEST-NET-1
blackhole address, with `WEBHOOK_URL` pointed at a closed local port — no real
host is contacted and no Teams alert is sent.
