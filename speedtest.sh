#!/bin/bash
# Usage:  ./speedtest.sh "Room name"     (or run it with no argument and it asks)
#
# Runs Ookla speedtest on every laptop in hosts.txt at the same time, saves a
# CSV in results/, and appends the rows to the Google Sheet.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f config.txt ]] || { echo "Missing config.txt - copy config.example.txt to config.txt and fill it in."; exit 1; }
SSH_USER=$(sed -n 's/^SSH_USER=//p' config.txt | tr -d '\r' | head -1)
SHEET_URL=$(sed -n 's/^SHEET_URL=//p' config.txt | tr -d '\r' | head -1)
[[ -z "$SSH_USER" || -z "$SHEET_URL" || "$SSH_USER" == CHANGE_ME || "$SHEET_URL" == CHANGE_ME ]] && { echo "Fill in SSH_USER and SHEET_URL in config.txt."; exit 1; }

LOCATION="${1:-}"
while [[ -z "$LOCATION" ]]; do read -rp "Room / location for this test: " LOCATION; done
HOSTS=$(grep -v '^#' hosts.txt | grep -v '^[[:space:]]*$' || true)
[[ -z "$HOSTS" ]] && { echo "hosts.txt has no laptops in it."; exit 1; }
COUNT=$(echo "$HOSTS" | wc -l | tr -d ' ')
NOW=$(date '+%Y-%m-%d %H:%M:%S')
TRIAL=$(date '+%m%d-%H%M%S')          # e.g. 1006-092003 (short enough for chart labels)
OUT="results/$TRIAL.csv"
mkdir -p results

echo "Date / Time,Location,Trial ID,Concurrent Clients,Device Type,Device ID,Download (Mbps),Upload (Mbps),Ping,Jitter,Test Site,Result URL,Notes" > "$OUT"

# Start all laptops at once; give up on any that are still running after 3 minutes.
PIDS=()
for h in $HOSTS; do
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$SSH_USER@$h" \
    'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json' \
    > "results/.$h.json" 2> "results/.$h.err" &
  PIDS+=($!)
done
( sleep 180; kill "${PIDS[@]}" 2>/dev/null ) 2>/dev/null & KILLER=$!
for p in "${PIDS[@]}"; do wait "$p" || true; done
kill "$KILLER" 2>/dev/null || true

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
    row[9]  = f"{d['ping']['jitter']:.1f}" if d['ping'].get('jitter') is not None else ''
    row[11] = d.get('result', {}).get('url', '')
    print(f"[{host}] OK  {row[6]} down / {row[7]} up Mbps", file=sys.stderr)
except Exception:
    err = open(errfile).read().strip().replace("\n", " ") or "speedtest returned no result (or timed out)"
    row[12] = err
    print(f"[{host}] FAILED: {err}", file=sys.stderr)
csv.writer(sys.stdout).writerow(row)
PY
  rm -f "results/.$h.json" "results/.$h.err"
done

# Append to the Google Sheet.
echo
echo "Sheet: $(curl -sS -L -H 'Content-Type: text/plain' --data-binary @"$OUT" "$SHEET_URL")"
echo "Saved copy: $OUT"
