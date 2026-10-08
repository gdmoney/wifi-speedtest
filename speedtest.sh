#!/bin/bash
# Usage:  ./speedtest.sh "Room name"     (or run it with no argument and it asks)
#
# Runs Ookla speedtest on every laptop in hosts.txt at the same time and
# appends one row per laptop to results.csv. Laptops that are off or not on
# the network are skipped; Concurrent Clients is the number that actually ran.
set -euo pipefail
cd "$(dirname "$0")"

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
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$h" \
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

# One row per laptop that was reachable, appended to results.csv.
echo
python3 - "$TMP" "$NOW" "$LOCATION" "$TRIAL" $HOSTS <<'PY'
import csv, json, os, sys
tmp, now, location, trial, *hosts = sys.argv[1:]
def ms(v): return f"{v:.1f}" if v is not None else ""
rows = []
for h in hosts:
    rc  = open(f"{tmp}/{h}.rc").read().strip()
    err = open(f"{tmp}/{h}.err").read().strip().replace("\n", " ")
    if rc == "255":
        print(f"[{h}] skipped: {err or 'not reachable'}")
        continue
    row = [now, location, trial, 0, h.split('@')[-1], "", "", "", "", "", "", ""]
    try:
        d = json.load(open(f"{tmp}/{h}.json"))
        row[5]  = f"{d['download']['bandwidth'] * 8 / 1e6:.2f}"
        row[6]  = f"{d['upload']['bandwidth'] * 8 / 1e6:.2f}"
        row[7]  = ms(d['ping'].get('latency'))
        row[8]  = ms(d['download'].get('latency', {}).get('iqm'))   # latency while downloading
        row[9]  = ms(d['upload'].get('latency', {}).get('iqm'))     # latency while uploading
        row[10] = d.get('result', {}).get('url', '')
        print(f"[{h}] OK  {row[5]} down / {row[6]} up Mbps")
    except Exception:
        row[11] = err or "speedtest returned no result (or timed out)"
        print(f"[{h}] FAILED: {row[11]}")
    rows.append(row)
if not rows:
    print("\nNo laptops responded; nothing written.")
    sys.exit()
ok = sum(1 for r in rows if r[5])
for r in rows: r[3] = ok
new = not os.path.exists("results.csv")
with open("results.csv", "a", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    if new:
        w.writerow(["Date / Time", "Location", "Trial ID", "Concurrent Clients", "Device ID", "Download (Mbps)", "Upload (Mbps)",
                    "Idle Ping (ms)", "Loaded Ping Down (ms)", "Loaded Ping Up (ms)", "Result URL", "Notes"])
    w.writerows(rows)
print(f"\nAdded {len(rows)} row(s) to results.csv (trial {trial}, {ok} concurrent).")
PY
