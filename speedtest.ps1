# Usage:  .\speedtest.ps1 "Room name"     (or run it with no argument and it asks)
#
# Windows version of speedtest.sh. Runs Ookla speedtest on every MacBook in
# hosts.txt at the same time and appends one row per MacBook to results.csv.
# Laptops that are off or not on the network are skipped; Concurrent Clients
# is the number that actually ran. Needs only what Windows 10/11 already has (OpenSSH client).
param([string]$Location)
while (-not $Location) { $Location = Read-Host "Room / location for this test" }

Set-Location $PSScriptRoot
$machines = @(Get-Content hosts.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' })
if ($machines.Count -eq 0) { Write-Host "hosts.txt has no laptops in it."; exit 1 }
$inv = [cultureinfo]::InvariantCulture    # always write 123.45, never 123,45
$now   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$trial = Get-Date -Format 'MMdd-HHmmss'    # e.g. 1006-092003 (short enough for chart labels)
$tmp = (New-Item -ItemType Directory -Force (Join-Path $env:TEMP "speedtest-$trial")).FullName

# Start all MacBooks at once; give up on any that are still running after 3 minutes.
$remote = 'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json'
$procs = @{}
foreach ($m in $machines) {
  $procs[$m] = Start-Process ssh -ArgumentList "-o ConnectTimeout=8 -o BatchMode=yes $m `"$remote`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\$m.json" -RedirectStandardError "$tmp\$m.err"
}
$procs.Values | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
$procs.Values | Where-Object { -not $_.HasExited } | Stop-Process -Force

# One row per MacBook that was reachable.
$rows = foreach ($m in $machines) {
  $err = ((Get-Content "$tmp\$m.err" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ').Trim()
  if ($procs[$m].ExitCode -eq 255) {          # ssh could not connect
    Write-Host "[$m] skipped: $(if ($err) { $err } else { 'not reachable' })"
    continue
  }
  $row = [ordered]@{
    'Date / Time' = $now; 'Location' = $Location; 'Trial ID' = $trial; 'Concurrent Clients' = 0
    'Device ID' = $m.Split('@')[-1]; 'Download (Mbps)' = ''; 'Upload (Mbps)' = ''
    'Idle Ping (ms)' = ''; 'Loaded Ping Down (ms)' = ''; 'Loaded Ping Up (ms)' = ''; 'Result URL' = ''; 'Notes' = ''
  }
  try {
    $d = Get-Content "$tmp\$m.json" -Raw | ConvertFrom-Json
    if (-not $d.download) { throw 'no result' }
    $row['Download (Mbps)'] = ($d.download.bandwidth * 8 / 1e6).ToString('F2', $inv)
    $row['Upload (Mbps)']   = ($d.upload.bandwidth * 8 / 1e6).ToString('F2', $inv)
    $ms = { param($v) if ($null -ne $v) { ([double]$v).ToString('F1', $inv) } else { '' } }
    $row['Idle Ping (ms)']        = & $ms $d.ping.latency
    $row['Loaded Ping Down (ms)'] = & $ms $d.download.latency.iqm    # latency while downloading
    $row['Loaded Ping Up (ms)']   = & $ms $d.upload.latency.iqm      # latency while uploading
    $row['Result URL']      = $d.result.url
    Write-Host "[$m] OK  $($row['Download (Mbps)']) down / $($row['Upload (Mbps)']) up Mbps"
  } catch {
    $row['Notes'] = if ($err) { $err } else { 'speedtest returned no result (or timed out)' }
    Write-Host "[$m] FAILED: $($row['Notes'])"
  }
  [pscustomobject]$row
}
Remove-Item $tmp -Recurse -Force

$rows = @($rows)
Write-Host ""
if ($rows.Count -eq 0) { Write-Host "No laptops responded; nothing written."; exit 1 }
$ok = @($rows | Where-Object { $_.'Download (Mbps)' }).Count
$rows | ForEach-Object { $_.'Concurrent Clients' = $ok }
$rows | Export-Csv results.csv -Append -NoTypeInformation -Encoding UTF8
Write-Host "Added $($rows.Count) row(s) to results.csv (trial $trial, $ok concurrent)."
