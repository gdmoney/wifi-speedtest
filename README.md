# WiFi speed test

One script. Runs speedtest on all the test laptops at once and appends the
results to the Google Sheet.

## Set up each test laptop (once)

1. System Settings > General > Sharing > turn on **Remote Login**.
2. In Terminal: `brew tap teamookla/speedtest && brew install speedtest`
3. Note the laptop's name from the Sharing screen (e.g. `wifi-test-01`).

## Set up the sheet (once, 2 minutes)

1. Open the sheet (**WiFi Speedtest Log**, in this Drive folder) > Extensions > **Apps Script**.
2. Replace the contents of `Code.gs` with `sheet_script.gs` from this folder. Save.
3. Deploy > New deployment > type: **Web app**. Execute as: **Me**.
   Who has access: **Anyone**. Deploy, approve the permissions, copy the URL.

The URL is long and random; anyone who has it could append rows, nothing more.

## Set up the control laptop (once)

1. Put this folder somewhere, e.g. `~/wifi-speedtest`.
2. Edit `hosts.txt`: one test laptop per line, as `name.local` (or an IP).
3. At the top of `speedtest_all.sh`, set `SSH_USER` (login name on the test
   laptops) and `SHEET_URL` (from step 3 above).
4. In Terminal:
   ```
   chmod +x ~/wifi-speedtest/speedtest_all.sh
   for h in $(grep -v '^#' ~/wifi-speedtest/hosts.txt); do ssh-copy-id USERNAME@$h; done
   ```
   (type each laptop's password once; after that, no prompts.)

## Run a test

```
~/wifi-speedtest/speedtest_all.sh "Ballroom A"
```

It prints each laptop's result, appends the rows to the sheet, and keeps a
copy in `results/<timestamp>.csv`. All laptops in a run share one Trial ID
(the timestamp); type it into the Summary tab to see the stats.

## If something fails

- A row with blank numbers and an error in Notes means that laptop couldn't be
  reached or speedtest isn't installed on it. The rest of the run is fine.
- `name.local` not found: the laptop is on a different subnet. Put its IP in
  `hosts.txt` instead (System Settings > Wi-Fi > Details).
- Sheet line shows an error instead of "added N row(s)": check `SHEET_URL`.
  The CSV copy in `results/` has the data either way.
