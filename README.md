# WiFi speed test

One script. Runs speedtest on all the test MacBooks at once and appends the
results to `results.csv`, a spreadsheet you can open in Excel or Numbers, import
into Google Sheets, or commit to this repo. Run it from a Mac (`speedtest.sh`)
or a Windows laptop (`speedtest.ps1`); they do the same thing.

## Set up each test MacBook (once)

1. System Settings > General > Sharing > turn on **Remote Login**.
2. In Terminal: `brew tap teamookla/speedtest && brew install speedtest`
3. Note the laptop's name from the Sharing screen (e.g. `wifi-test-01`) and the
   account name you log in with.

## Set up the control laptop (once)

1. Clone this repo. In GitHub Desktop: File > Clone repository > URL, paste
   `https://github.com/gdmoney/wifi-speedtest.git` and keep the default Local
   path. It lands at:

   - Mac: `/Users/<username>/Documents/GitHub/wifi-speedtest`
   - Windows: `C:\Users\<username>\Documents\GitHub\wifi-speedtest`

   `<username>` is your login name on that laptop. The rest of this README
   uses these paths; adjust them if you cloned somewhere else.
2. Edit `hosts.txt`: one test MacBook per line as `login@name.local` (or
   `login@<ip address>`), where `login` is the account name on that MacBook.

On a Mac control laptop, the script needs `python3`. If running it pops up an
"install the command line developer tools?" dialog, click Install once.

Then copy your SSH key to each MacBook so the script can log in without a
password. You'll type each MacBook's password once; after that, no prompts.

**Mac** (Terminal):
```
chmod +x /Users/<username>/Documents/GitHub/wifi-speedtest/speedtest.sh
for h in $(grep -v '^#' /Users/<username>/Documents/GitHub/wifi-speedtest/hosts.txt); do ssh-copy-id $h; done
```

**Windows** (PowerShell):
```
ssh-keygen -t ed25519            # press Enter at every prompt; skip if you already have a key
foreach ($h in (Get-Content C:\Users\<username>\Documents\GitHub\wifi-speedtest\hosts.txt | ? { $_ -notmatch '^#' -and $_.Trim() })) {
  type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh $h "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
}
```
If PowerShell refuses to run the script ("running scripts is disabled"), run
this once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## Run a test

Mac:
```
/Users/<username>/Documents/GitHub/wifi-speedtest/speedtest.sh
```
Windows:
```
C:\Users\<username>\Documents\GitHub\wifi-speedtest\speedtest.ps1
```
It asks for the room / location, then runs. To skip the question, pass the
room name on the command line instead: `speedtest.sh "Ballroom A"`.

You don't have to use every laptop in `hosts.txt`. Bring any 3, 5 or 10 of
them; the ones that are off or not on the network are skipped (the script
prints `skipped` for them), and `Concurrent Clients` is the number that
actually ran.

## Results

Every run appends one row per MacBook to `results.csv` in this folder (the
file is created on the first run). All MacBooks in a run share one Trial ID
(month, day and time, e.g. `1006-092003`). The columns are:

`Date / Time`, `Location`, `Trial ID`, `Concurrent Clients`, `Device ID`,
`Download (Mbps)`, `Upload (Mbps)`, `Idle Ping (ms)`, `Loaded Ping Down (ms)`,
`Loaded Ping Up (ms)`, `Result URL`, `Notes`.

"Loaded" ping is the latency measured while the download/upload was running;
that's the number that predicts how video calls feel on a busy network. Idle
ping is the baseline to compare it against.

To get the rows into the
[Google Sheet](https://docs.google.com/spreadsheets/d/1QH7NN4goNkNZAscmMheX1F84q-xraeevtTB_Dl4z620):
open the `Test Log` tab, File > Import > Upload > choose `results.csv` >
Import location: **Append to current sheet**. Do this whenever you like (end
of the day, end of the conference); the Summary tab picks up the new rows.

## If something fails

- `[name] skipped: ...` on screen means the script couldn't log in to that
  MacBook (off, not on the network, or SSH not set up). It gets no row in
  `results.csv`; the rest of the run is fine.
- A row with blank numbers and an error in Notes means the MacBook was reached
  but speedtest isn't installed on it, failed, or took longer than 3 minutes.
- "Host key verification failed": the MacBook was reinstalled or renamed. Run
  `ssh-keygen -R name.local` to forget the old key, then `ssh login@name.local`
  once by hand and answer `yes`.
- `name.local` not found: the MacBook is on a different subnet. Put its IP in
  `hosts.txt` instead (System Settings > Wi-Fi > Details).
- "Permission denied": the SSH key wasn't copied to that MacBook, or the login
  name in `hosts.txt` is wrong. Redo the key step for that machine.
