# WiFi speed test

One script. Runs speedtest on all the test MacBooks at once and appends the
results to the [Google Sheet](https://docs.google.com/spreadsheets/d/1QH7NN4goNkNZAscmMheX1F84q-xraeevtTB_Dl4z620).
Run it from a Mac (`speedtest_all.sh`) or a Windows laptop (`speedtest_all.ps1`);
they do the same thing.

## Set up each test MacBook (once)

1. System Settings > General > Sharing > turn on **Remote Login**.
2. In Terminal: `brew tap teamookla/speedtest && brew install speedtest`
3. Note the laptop's name from the Sharing screen (e.g. `wifi-test-01`).

## Set up the sheet (once, 2 minutes)

1. Open the sheet > Extensions > **Apps Script**.
2. Replace the contents of `Code.gs` with `sheet_script.gs` from this folder. Save.
3. Deploy > New deployment > type: **Web app**. Execute as: **Me**.
   Who has access: **Anyone**. Deploy, approve the permissions, copy the URL.

The URL is long and random; anyone who has it could append rows, nothing more.

## Set up the control laptop (once)

Both versions: put this folder somewhere (e.g. `~/wifi-speedtest` or
`C:\wifi-speedtest`), edit `hosts.txt` with one test MacBook per line as
`name.local` (or an IP), and set the two values at the top of the script:
`SSH_USER` / `$SshUser` (login name on the MacBooks) and `SHEET_URL` /
`$SheetUrl` (from step 3 above).

Then copy your SSH key to each MacBook so the script can log in without a
password. You'll type each MacBook's password once; after that, no prompts.

**Mac** (Terminal):
```
chmod +x ~/wifi-speedtest/speedtest_all.sh
for h in $(grep -v '^#' ~/wifi-speedtest/hosts.txt); do ssh-copy-id USERNAME@$h; done
```

**Windows** (PowerShell):
```
ssh-keygen -t ed25519            # press Enter at every prompt; skip if you already have a key
foreach ($h in (Get-Content C:\wifi-speedtest\hosts.txt | ? { $_ -notmatch '^#' -and $_.Trim() })) {
  type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh USERNAME@$h "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
}
```
If PowerShell refuses to run the script ("running scripts is disabled"), run
this once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## Run a test

Mac:
```
~/wifi-speedtest/speedtest_all.sh
```
Windows:
```
C:\wifi-speedtest\speedtest_all.ps1
```
It asks for the room / location, then runs. To skip the question, pass the
room name on the command line instead: `speedtest_all.sh "Ballroom A"`.

It prints each MacBook's result, appends the rows to the sheet, and keeps a
copy in `results/<trial id>.csv`. All MacBooks in a run share one Trial ID
(month, day and time, e.g. `1006-092003`); type it into the Summary tab to see the stats.

## If something fails

- A row with blank numbers and an error in Notes means that MacBook couldn't be
  reached or speedtest isn't installed on it. The rest of the run is fine.
- `name.local` not found: the MacBook is on a different subnet. Put its IP in
  `hosts.txt` instead (System Settings > Wi-Fi > Details).
- "Permission denied" in Notes: the SSH key wasn't copied to that MacBook, or
  `SSH_USER` is wrong. Redo the key step for that machine.
- Sheet line shows an error instead of "added N row(s)": check the sheet URL.
  The CSV copy in `results/` has the data either way.
