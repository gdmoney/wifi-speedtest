#!/bin/bash
# Usage:  ./speedtest.sh "Room name"     (or run it with no argument and it asks)
#
# Runs Ookla speedtest on every laptop in hosts.txt at the same time and
# appends the results to the Google Sheet. Laptops that are off or not on the
# network are skipped; Concurrent Clients is the number that actually ran.
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
NOW=$(date '+%Y-%m-%d %H:%M:%S')
TRIAL=$(date '+%m%d-%H%M%S')          # e.g. 1006-092003 (short enough for chart labels)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Start all laptops at once; give up on any that are still running after 3 minutes.
PIDS=(); NAMES=()
for h in $HOSTS; do
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$SSH_USER@$h" \
    'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json' \
    > "$TMP/$h.json" 2> "$TMP/$h.err" &
  PIDS+=($!); NAMES+=("$h")
done
( sleep 180; kill "${PIDS[@]}" 2>/dev/null ) 2>/dev/null & KILLER=$!
for i in "${!PIDS[@]}"; do
  wait "${PIDS[$i]}" && rc=0 || rc=$?
  echo "$rc" > "$TMP/${NAMES[$i]}.rc"      # 255 = ssh could not connect
done
kill "$KILLER" 2>/dev/null || true

# Build the CSV (one row per laptop that was reachable) and append it to the sheet.
echo
python3 - "$TMP" "$NOW" "$LOCATION" "$TRIAL" $HOSTS <<'PY' | curl -sS -L -H 'Content-Type: text/plain' --data-binary @- "$SHEET_URL" | sed 's/^/Sheet: /'
import csv, json, sys
tmp, now, location, trial, *hosts = sys.argv[1:]
def ms(v): return f"{v:.1f}" if v is not None else ""
rows = []
for h in hosts:
    rc  = open(f"{tmp}/{h}.rc").read().strip()
    err = open(f"{tmp}/{h}.err").read().strip().replace("\n", " ")
    if rc == "255":
        print(f"[{h}] skipped: {err or 'not reachable'}", file=sys.stderr)
        continue
    row = [now, location, trial, 0, h, "", "", "", "", "", "", ""]
    try:
        d = json.load(open(f"{tmp}/{h}.json"))
        row[5]  = f"{d['download']['bandwidth'] * 8 / 1e6:.2f}"
        row[6]  = f"{d['upload']['bandwidth'] * 8 / 1e6:.2f}"
        row[7]  = ms(d['ping'].get('latency'))
        row[8]  = ms(d['download'].get('latency', {}).get('iqm'))   # latency while downloading
        row[9]  = ms(d['upload'].get('latency', {}).get('iqm'))     # latency while uploading
        row[10] = d.get('result', {}).get('url', '')
        print(f"[{h}] OK  {row[5]} down / {row[6]} up Mbps", file=sys.stderr)
    except Exception:
        row[11] = err or "speedtest returned no result (or timed out)"
        print(f"[{h}] FAILED: {row[11]}", file=sys.stderr)
    rows.append(row)
ok = sum(1 for r in rows if r[5])
for r in rows: r[3] = ok
w = csv.writer(sys.stdout)
w.writerow(["Date / Time", "Location", "Trial ID", "Concurrent Clients", "Device ID", "Download (Mbps)", "Upload (Mbps)",
            "Idle Ping (ms)", "Loaded Ping Down (ms)", "Loaded Ping Up (ms)", "Result URL", "Notes"])
w.writerows(rows)
PY
