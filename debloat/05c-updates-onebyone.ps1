$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\debloat\updates-onebyone.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}

Write-Log '=== Per-update Windows Update run started ==='

# Reset only the download cache. Update history and installed updates are untouched.
foreach ($svc in @('usosvc','wuauserv','bits')) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
$downloadDir = 'C:\Windows\SoftwareDistribution\Download'
if (Test-Path $downloadDir) {
    Get-ChildItem $downloadDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($svc in @('wuauserv','bits','usosvc')) {
    Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service -Name $svc -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

function Get-UpdateList {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 0
    return $searcher.Search("IsInstalled=0 and IsHidden=0 and BrowseOnly=0")
}

$result = Get-UpdateList
$all = @($result.Updates)
Write-Log "Found $($all.Count) available update(s)."
$rows = foreach ($u in $all) {
    [pscustomobject]@{
        Title       = $u.Title
        Type        = if ($u.Type -eq 2) { 'Driver' } else { 'Software' }
        DriverClass = $u.DriverClass
        Downloaded  = $u.IsDownloaded
        Categories  = ($u.Categories | ForEach-Object { $_.Name }) -join '; '
    }
}
$rows | Export-Csv 'C:\Users\Public\debloat\windows-updates-available.csv' -NoTypeInformation -Encoding UTF8
$rows | Format-Table -AutoSize -Wrap | Out-String -Width 300 | Write-Host

# Skip UEFI/BIOS firmware updates in this automated pass.
$targets = $all | Where-Object {
    $_.DriverClass -ne 'Firmware' -and
    $_.Title -notmatch 'UEFI|BIOS|Firmware'
}
Write-Log "Targeting $($targets.Count) non-firmware update(s)."

foreach ($u in $targets) {
    $title = $u.Title
    if ($u.IsDownloaded) { Write-Log "Already downloaded: $title"; continue }
    Write-Log "Downloading: $title"
    $job = Start-Job -ArgumentList $title -ScriptBlock {
        param($title)
        $ErrorActionPreference = 'Stop'
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServerSelection = 0
        $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $update = @($result.Updates | Where-Object { $_.Title -eq $title }) | Select-Object -First 1
        if (-not $update) { return "NOTFOUND: $title" }
        if ($update.IsDownloaded) { return "ALREADY: $title" }
        if (-not $update.EulaAccepted) { $update.AcceptEula() | Out-Null }
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        $coll.Add($update) | Out-Null
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $coll
        $res = $downloader.Download()
        return "DOWNLOAD RESULT $($res.ResultCode): $title"
    }
    $done = Wait-Job $job -Timeout 900
    if ($done) {
        $out = Receive-Job $job
        Write-Log ($out -join ' | ')
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Write-Log "TIMEOUT after 15 min: $title"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Re-search and install everything that is now downloaded, still excluding firmware.
$result2 = Get-UpdateList
$ready = @($result2.Updates | Where-Object {
    $_.IsDownloaded -and $_.DriverClass -ne 'Firmware' -and $_.Title -notmatch 'UEFI|BIOS|Firmware'
})
Write-Log "Ready to install: $($ready.Count) update(s)."
foreach ($u in $ready) { Write-Log "  READY: $($u.Title)" }

if ($ready.Count -gt 0) {
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $ready) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }
        $coll.Add($u) | Out-Null
    }
    $session = New-Object -ComObject Microsoft.Update.Session
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $coll
    Write-Log 'Installing downloaded updates...'
    $install = $installer.Install()
    Write-Log "Install result code: $($install.ResultCode) (2=Succeeded, 3=SucceededWithErrors)"
    Write-Log "Reboot required: $($install.RebootRequired)"
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $u = $coll.Item($i)
        $r = $install.GetUpdateResult($i)
        Write-Log ("  {0} -> result {1}" -f $u.Title, $r.ResultCode)
    }
} else {
    Write-Log 'No downloaded updates ready to install.'
}

Write-Log '=== Per-update Windows Update run finished ==='
