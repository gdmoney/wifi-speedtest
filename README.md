# WiFi speed test

One script. Runs speedtest on all the test MacBooks at once and appends the
results to the [Google Sheet](https://docs.google.com/spreadsheets/d/1QH7NN4goNkNZAscmMheX1F84q-xraeevtTB_Dl4z620).
Run it from a Mac (`speedtest.sh`) or a Windows laptop (`speedtest.ps1`);
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

If `sheet_script.gs` changes later, paste the new version in and then
Deploy > Manage deployments > edit (pencil) > Version: **New version** > Deploy.
The URL stays the same; without this step the sheet keeps running the old code.

## Set up the control laptop (once)

Both versions: put this folder somewhere (e.g. `~/wifi-speedtest` or
`C:\wifi-speedtest`), edit `hosts.txt` with one test MacBook per line as
`name.local` (or an IP), then copy `config.example.txt` to `config.txt` and
fill in `SSH_USER` (login name on the MacBooks) and `SHEET_URL` (from step 3
above). `config.txt` is ignored by git so the sheet URL never gets committed.

On a Mac control laptop, the script needs `python3`. If running it pops up an
"install the command line developer tools?" dialog, click Install once.

Then copy your SSH key to each MacBook so the script can log in without a
password. You'll type each MacBook's password once; after that, no prompts.

**Mac** (Terminal):
```
chmod +x ~/wifi-speedtest/speedtest.sh
for h in $(grep -v '^#' ~/wifi-speedtest/hosts.txt); do ssh-copy-id USERNAME@$h; done
```

**Windows** (PowerShell):
```
ssh-keygen -t ed25519            # press Enter at every prompt; skip if you already have a key
foreach ($h in (Get-Content C:\wifi-speedtest\hosts.txt | ? { $_ -notmatch '^#' -and $_.Trim() })) {
  type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh USERNAME@$h "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
}
```
If PowerShell refuses to run the script ("running scripts is disabled"), run
this once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## Run a test

Mac:
```
~/wifi-speedtest/speedtest.sh
```
Windows:
```
C:\wifi-speedtest\speedtest.ps1
```
It asks for the room / location, then runs. To skip the question, pass the
room name on the command line instead: `speedtest.sh "Ballroom A"`.

It prints each MacBook's result, appends the rows to the sheet, and keeps a
copy in `results/<trial id>.csv`. All MacBooks in a run share one Trial ID
(month, day and time, e.g. `1006-092003`); type it into the Summary tab to see the stats.

## If something fails

- A row with blank numbers and an error in Notes means that MacBook couldn't be
  reached, speedtest isn't installed on it, or it took longer than 3 minutes.
  The rest of the run is fine.
- "Host key verification failed" in Notes: the MacBook was reinstalled or
  renamed. Run `ssh USERNAME@name.local` once by hand and answer `yes`.
- `name.local` not found: the MacBook is on a different subnet. Put its IP in
  `hosts.txt` instead (System Settings > Wi-Fi > Details).
- "Permission denied" in Notes: the SSH key wasn't copied to that MacBook, or
  `SSH_USER` is wrong. Redo the key step for that machine.
- Sheet line shows `ERROR: ...` instead of "added N row(s)": the message says
  what's wrong (e.g. the tab isn't named `Test Log`). Any other error there
  means the `SHEET_URL` in `config.txt` is wrong. The CSV copy in `results/`
  has the data either way.
