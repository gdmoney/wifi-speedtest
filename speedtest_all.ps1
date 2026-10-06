# Usage:  .\speedtest_all.ps1 "Room name"
#
# Windows version of speedtest_all.sh. Runs Ookla speedtest on every MacBook in
# hosts.txt at the same time, saves a CSV in results\, and appends the rows to
# the Google Sheet. Needs only what Windows 10/11 already has (OpenSSH client).
param([Parameter(Mandatory = $true)][string]$Location)

$SshUser  = "CHANGE_ME"    # login username on the test MacBooks (same on all)
$SheetUrl = "CHANGE_ME"    # Apps Script web app URL (see README, ends in /exec)

Set-Location $PSScriptRoot
$machines = Get-Content hosts.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' }
$count = @($machines).Count
$now   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$trial = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force results | Out-Null
$out = "results\$trial.csv"

# Start all MacBooks at once.
$remote = 'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json'
$procs = foreach ($m in $machines) {
  Start-Process ssh -ArgumentList "-o ConnectTimeout=8 -o BatchMode=yes $SshUser@$m `"$remote`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput "results\.$m.json" -RedirectStandardError "results\.$m.err"
}
$procs | Wait-Process

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
    $row['Download (Mbps)'] = '{0:F2}' -f ($d.download.bandwidth * 8 / 1e6)
    $row['Upload (Mbps)']   = '{0:F2}' -f ($d.upload.bandwidth * 8 / 1e6)
    $row['Ping']            = '{0:F1}' -f $d.ping.latency
    $row['Jitter']          = $d.ping.jitter
    $row['Result URL']      = $d.result.url
    Write-Host "[$m] OK  $($row['Download (Mbps)']) down / $($row['Upload (Mbps)']) up Mbps"
  } catch {
    $err = (Get-Content "results\.$m.err" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' '
    if (-not $err -or -not $err.Trim()) { $err = 'speedtest returned no result' }
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
