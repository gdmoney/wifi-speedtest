# Usage:  .\speedtest.ps1 "Room name"     (or run it with no argument and it asks)
#
# Windows version of speedtest.sh. Runs Ookla speedtest on every MacBook in
# hosts.txt at the same time and appends the results to the Google Sheet.
# Laptops that are off or not on the network are skipped; Concurrent Clients
# is the number that actually ran. Needs only what Windows 10/11 already has (OpenSSH client).
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
if ($machines.Count -eq 0) { Write-Host "hosts.txt has no laptops in it."; exit 1 }
$inv = [cultureinfo]::InvariantCulture    # always write 123.45, never 123,45
$now   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$trial = Get-Date -Format 'MMdd-HHmmss'    # e.g. 1006-092003 (short enough for chart labels)
$tmp = (New-Item -ItemType Directory -Force (Join-Path $env:TEMP "speedtest-$trial")).FullName

# Start all MacBooks at once; give up on any that are still running after 3 minutes.
$remote = 'PATH=/opt/homebrew/bin:/usr/local/bin:$PATH speedtest --accept-license --accept-gdpr -f json'
$procs = @{}
foreach ($m in $machines) {
  $procs[$m] = Start-Process ssh -ArgumentList "-o ConnectTimeout=8 -o BatchMode=yes $SshUser@$m `"$remote`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\$m.json" -RedirectStandardError "$tmp\$m.err"
}
$procs.Values | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
$procs.Values | Where-Object { -not $_.HasExited } | Stop-Process -Force

# One CSV row per MacBook that was reachable.
$rows = foreach ($m in $machines) {
  $err = ((Get-Content "$tmp\$m.err" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ').Trim()
  if ($procs[$m].ExitCode -eq 255) {          # ssh could not connect
    Write-Host "[$m] skipped: $(if ($err) { $err } else { 'not reachable' })"
    continue
  }
  $row = [ordered]@{
    'Date / Time' = $now; 'Location' = $Location; 'Trial ID' = $trial; 'Concurrent Clients' = 0
    'Device ID' = $m; 'Download (Mbps)' = ''; 'Upload (Mbps)' = ''
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
$rows = @($rows)
$ok = @($rows | Where-Object { $_.'Download (Mbps)' }).Count
$rows | ForEach-Object { $_.'Concurrent Clients' = $ok }

# Append to the Google Sheet.
Write-Host ""
try {
  $body = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`n"
  $resp = Invoke-RestMethod -Uri $SheetUrl -Method Post -ContentType 'text/plain; charset=utf-8' -Body $body
  Write-Host "Sheet: $resp"
} catch {
  Write-Host "Sheet: FAILED - $($_.Exception.Message)"
}
Remove-Item $tmp -Recurse -Force
