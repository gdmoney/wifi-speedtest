#!/bin/bash
# Usage:  ./speedtest.sh "Room name"     (or run it with no argument and it asks)
#
# Runs Ookla speedtest on every laptop in hosts.txt at the same time, saves a
# CSV in results/, and appends the rows to the Google Sheet.
set -euo pipefail
cd "$(dirname "$0")"

SSH_USER="CHANGE_ME"      # login username on the test laptops (same on all)
SHEET_URL="CHANGE_ME"     # Apps Script web app URL (see README, ends in /exec)

LOCATION="${1:-}"
while [[ -z "$LOCATION" ]]; do read -rp "Room / location for this test: " LOCATION; done
HOSTS=$(grep -v '^#' hosts.txt | grep -v '^[[:space:]]*$')
COUNT=$(echo "$HOSTS" | wc -l | tr -d ' ')
NOW=$(date '+%Y-%m-%d %H:%M:%S')
TRIAL=$(date '+%m%d-%H%M%S')          # e.g. 1006-092003 (short enough for chart labels)
OUT="results/$TRIAL.csv"
mkdir -p results

echo "Date / Time,Location,Trial ID,Concurrent Clients,Device Type,Device ID,Download (Mbps),Upload (Mbps),Ping,Jitter,Test Site,Result URL,Notes" > "$OUT"

# Start all laptops at once.
for h in $HOSTS; do
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$SSH_USER@$h" \
    'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json' \
    > "results/.$h.json" 2> "results/.$h.err" &
done
wait

# One CSV row per laptop.
for h in $HOSTS; do
  python3 - "$h" "results/.$h.json" "results/.$h.err" "$NOW" "$LOCATION" "$TRIAL" "$COUNT" >> "$OUT" <<'PY'
import csv, json, sys
host, jsonfile, errfile, now, location, trial, count = sys.argv[1:]
row = [now, location, trial, count, "Laptop", host, "", "", "", "", "https://www.speedtest.net/", "", ""]
try:
    d = json.load(open(jsonfile))
    row[6]  = f"{d['download']['bandwidth'] * 8 / 1e6:.2f}"
    row[7]  = f"{d['upload']['bandwidth'] * 8 / 1e6:.2f}"
    row[8]  = f"{d['ping']['latency']:.1f}"
    row[9]  = d['ping'].get('jitter', '')
    row[11] = d.get('result', {}).get('url', '')
    print(f"[{host}] OK  {row[6]} down / {row[7]} up Mbps", file=sys.stderr)
except Exception:
    err = open(errfile).read().strip().replace("\n", " ") or "speedtest returned no result"
    row[12] = err
    print(f"[{host}] FAILED: {err}", file=sys.stderr)
csv.writer(sys.stdout).writerow(row)
PY
  rm -f "results/.$h.json" "results/.$h.err"
done

# Append to the Google Sheet.
echo
echo "Sheet: $(curl -sS -L -X POST --data-binary @"$OUT" "$SHEET_URL")"
echo "Saved copy: $OUT"
