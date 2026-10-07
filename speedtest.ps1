# Usage:  .\speedtest.ps1 "Room name"     (or run it with no argument and it asks)
#
# Windows version of speedtest.sh. Runs Ookla speedtest on every MacBook in
# hosts.txt at the same time, saves a CSV in results\, and appends the rows to
# the Google Sheet. Needs only what Windows 10/11 already has (OpenSSH client).
param([string]$Location)
while (-not $Location) { $Location = Read-Host "Room / location for this test" }

Set-Location $PSScriptRoot
if (-not (Test-Path config.txt)) { Write-Host "Missing config.txt - copy config.example.txt to config.txt and fill it in."; exit 1 }
$cfg = @{}
Get-Content config.txt | Where-Object { $_ -match '^\s*([^#=]+)=(.*)$' } | ForEach-Object { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
$SshUser  = $cfg['SSH_USER']
$SheetUrl = $cfg['SHEET_URL']
if (-not $SshUser -or -not $SheetUrl -or $SshUser -eq 'CHANGE_ME' -or $SheetUrl -eq 'CHANGE_ME') { Write-Host "Fill in SSH_USER and SHEET_URL in config.txt."; exit 1 }

$machines = @(Get-Content hosts.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' })
$count = $machines.Count
if ($count -eq 0) { Write-Host "hosts.txt has no laptops in it."; exit 1 }
$inv = [cultureinfo]::InvariantCulture    # always write 123.45, never 123,45
$now   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$trial = Get-Date -Format 'MMdd-HHmmss'    # e.g. 1006-092003 (short enough for chart labels)
New-Item -ItemType Directory -Force results | Out-Null
$out = "results\$trial.csv"

# Start all MacBooks at once; give up on any that are still running after 3 minutes.
$remote = 'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json'
$procs = foreach ($m in $machines) {
  Start-Process ssh -ArgumentList "-o ConnectTimeout=8 -o BatchMode=yes $SshUser@$m `"$remote`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput "results\.$m.json" -RedirectStandardError "results\.$m.err"
}
$procs | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
$procs | Where-Object { -not $_.HasExited } | Stop-Process -Force

# One CSV row per MacBook.
$rows = foreach ($m in $machines) {
  $row = [ordered]@{
    'Date / Time' = $now; 'Location' = $Location; 'Trial ID' = $trial; 'Concurrent Clients' = $count
    'Device Type' = 'Laptop'; 'Device ID' = $m; 'Download (Mbps)' = ''; 'Upload (Mbps)' = ''
    'Ping' = ''; 'Jitter' = ''; 'Test Site' = 'https://www.speedtest.net/'; 'Result URL' = ''; 'Notes' = ''
  }
  try {
    $d = Get-Content "results\.$m.json" -Raw | ConvertFrom-Json
    if (-not $d.download) { throw 'no result' }
    $row['Download (Mbps)'] = ($d.download.bandwidth * 8 / 1e6).ToString('F2', $inv)
    $row['Upload (Mbps)']   = ($d.upload.bandwidth * 8 / 1e6).ToString('F2', $inv)
    $row['Ping']            = ([double]$d.ping.latency).ToString('F1', $inv)
    $row['Jitter']          = ([double]$d.ping.jitter).ToString('F1', $inv)
    $row['Result URL']      = $d.result.url
    Write-Host "[$m] OK  $($row['Download (Mbps)']) down / $($row['Upload (Mbps)']) up Mbps"
  } catch {
    $err = (Get-Content "results\.$m.err" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' '
    if (-not $err -or -not $err.Trim()) { $err = 'speedtest returned no result (or timed out)' }
    $row['Notes'] = $err.Trim()
    Write-Host "[$m] FAILED: $($row['Notes'])"
  }
  Remove-Item "results\.$m.json", "results\.$m.err" -ErrorAction SilentlyContinue
  [pscustomobject]$row
}
$rows | Export-Csv $out -NoTypeInformation -Encoding UTF8

# Append to the Google Sheet.
Write-Host ""
try {
  $resp = Invoke-RestMethod -Uri $SheetUrl -Method Post -ContentType 'text/plain' -Body (Get-Content $out -Raw)
  Write-Host "Sheet: $resp"
} catch {
  Write-Host "Sheet: FAILED - $($_.Exception.Message)"
}
Write-Host "Saved copy: $out"
