# WiFi speed test

## Project overview

We need to know whether a venue's WiFi can handle a room full of people on
video calls before we commit to it. Guessing from one laptop's speed test
doesn't answer that, so this project measures the network under realistic
load: up to ten MacBooks run Ookla Speedtest at the same moment, from the
same room, and we look at how the total and per-laptop throughput hold up as
the number of clients grows.

How it works: a control laptop (Mac or Windows) connects to each test MacBook
over SSH, starts speedtest on all of them simultaneously, collects the JSON
results, and appends one row per MacBook to `results.csv`. The tester commits
and pushes that file after each round. GitHub Pages serves `index.html`,
which reads the CSV and renders the charts, so the
[stats page](https://gdmoney.github.io/wifi-speedtest/) is always current
without any build step.

## Set up each test MacBook (once)

1. System Settings > General > Sharing > turn on **Remote Login**.
2. Install Homebrew if the MacBook doesn't have it yet (one command, from
   https://brew.sh), then in Terminal:
   `brew tap teamookla/speedtest && brew install speedtest`
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
2. Check that `hosts.txt` lists every test MacBook, one per line as
   `login@name.local` (or `login@<ip address>`), where `login` is the account
   name on that MacBook. The file is shared through the repo, so if one is
   missing, add it and commit; don't keep local edits to it.

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

As each MacBook finishes, its download and upload are printed. When the run
is complete the script prints a summary: Trial ID, Location, Concurrent
Clients, Average Download and Average Upload. That's the number to check
before moving to the next room.

You don't have to use every laptop in `hosts.txt`. Bring any 3, 5 or 10 of
them; the ones that are off or not on the network are skipped (the script
prints `skipped` for them), and `Concurrent Clients` is the number the script
reached. A reached laptop counts even if its speedtest failed or timed out,
because it was still loading the network during the test.

Laptops you aren't using must be powered off (or at least off the conference
WiFi). One left on in a bag and still connected will run the test and count
as a client.

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

After each round, commit `results.csv` and push (GitHub Desktop: write a
summary, Commit to main, Push origin). Before starting a round, Fetch origin
and Pull so you have the other testers' rows; one round at a time and this
never conflicts.

For a quick look, open `results.csv` in Excel or Numbers and filter or sort
by `Location` or `Trial ID`.

## Stats page

`index.html` is a one-page dashboard built from `results.csv`: headline
cards, download/upload by room, a total-vs-per-client capacity chart, and a
sortable table with one row per trial. It is published with GitHub Pages at

https://gdmoney.github.io/wifi-speedtest/

and refreshes itself a minute or two after every push; there is nothing to
build or run. It has to be opened from that address, not double-clicked from
the folder, because browsers won't let a local page read a local CSV.

To turn Pages on (once): repo on github.com > Settings > Pages > Build and
deployment > Source: **Deploy from a branch** > Branch: **main**, folder
**/ (root)** > Save.

## If something fails

- `[name] skipped: ...` on screen means the script couldn't log in to that
  MacBook (off, not on the network, or SSH not set up). It gets no row in
  `results.csv`; the rest of the run is fine.
- A row with blank numbers and an error in Notes means the MacBook was reached
  but speedtest isn't installed on it, failed, or took longer than 3 minutes.
- `skipped: Host key verification failed`: the MacBook was reinstalled or
  renamed. Run `ssh-keygen -R name.local` to forget the old key, then
  `ssh login@name.local` once by hand and answer `yes`.
- `skipped: ... name.local: nodename nor servname provided` (or similar "not
  found"): the MacBook is on a different subnet. Put its IP in `hosts.txt`
  instead (System Settings > Wi-Fi > Details).
- `skipped: Permission denied`: the SSH key wasn't copied to that MacBook, or
  the login name in `hosts.txt` is wrong. Redo the key step for that machine.
