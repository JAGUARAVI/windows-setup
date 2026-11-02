$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\debloat\updates-reset-retry.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}

Write-Log '=== Windows Update reset + fresh per-update run ==='

# Standard Windows Update component reset.
foreach ($svc in @('usosvc','wuauserv','bits','cryptsvc','msiserver')) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 5
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sd = 'C:\Windows\SoftwareDistribution'
$cat = 'C:\Windows\System32\catroot2'
if (Test-Path $sd) {
    Rename-Item -LiteralPath $sd -NewName "SoftwareDistribution.old-$stamp" -Force -ErrorAction SilentlyContinue
    Write-Log "Renamed SoftwareDistribution -> SoftwareDistribution.old-$stamp"
}
if (Test-Path $cat) {
    Rename-Item -LiteralPath $cat -NewName "catroot2.old-$stamp" -Force -ErrorAction SilentlyContinue
    Write-Log "Renamed catroot2 -> catroot2.old-$stamp"
}
foreach ($svc in @('cryptsvc','wuauserv','bits','usosvc')) {
    Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service -Name $svc -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 10

function Get-UpdateList {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 0
    return $searcher.Search("IsInstalled=0 and IsHidden=0")
}

$result = Get-UpdateList
$all = @($result.Updates)
Write-Log "Found $($all.Count) available update(s) after reset."

# Hide UEFI/BIOS firmware so Windows Update cannot install it automatically.
foreach ($u in $all) {
    if ($u.DriverClass -eq 'Firmware' -or $u.Title -match 'UEFI|BIOS|Firmware') {
        try {
            $u.IsHidden = $true
            Write-Log "Hidden firmware/BIOS update: $($u.Title)"
        } catch {
            Write-Log "Could not hide firmware update: $($u.Title) - $($_.Exception.Message)"
        }
    }
}

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

# Order: drivers first, other software next, cumulative update last.
$targets = @($all | Where-Object { $_.DriverClass -ne 'Firmware' -and $_.Title -notmatch 'UEFI|BIOS|Firmware' } |
    Sort-Object @{ Expression = { if ($_.Title -match 'KB5127648') { 2 } elseif ($_.Type -eq 2) { 0 } else { 1 } } })
Write-Log "Targeting $($targets.Count) update(s)."

foreach ($u in $targets) {
    $title = $u.Title
    Write-Log "Downloading fresh: $title"
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
    $done = Wait-Job $job -Timeout 1200
    if ($done) { Write-Log ((Receive-Job $job) -join ' | ') }
    else { Stop-Job $job -ErrorAction SilentlyContinue; Write-Log "DOWNLOAD TIMEOUT 20 min: $title" }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

foreach ($u in $targets) {
    $title = $u.Title
    Write-Log "Installing: $title"
    $job = Start-Job -ArgumentList $title -ScriptBlock {
        param($title)
        $ErrorActionPreference = 'Stop'
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServerSelection = 0
        $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $update = @($result.Updates | Where-Object { $_.Title -eq $title }) | Select-Object -First 1
        if (-not $update) { return "NOTFOUND/ALREADY INSTALLED: $title" }
        if (-not $update.IsDownloaded) { return "NOT DOWNLOADED: $title" }
        if (-not $update.EulaAccepted) { $update.AcceptEula() | Out-Null }
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        $coll.Add($update) | Out-Null
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $coll
        $res = $installer.Install()
        return "INSTALL RESULT $($res.ResultCode), reboot=$($res.RebootRequired): $title"
    }
    $done = Wait-Job $job -Timeout 1200
    if ($done) { Write-Log ((Receive-Job $job) -join ' | ') }
    else { Stop-Job $job -ErrorAction SilentlyContinue; Write-Log "INSTALL TIMEOUT 20 min: $title" }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

$pend = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$pend2 = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
Write-Log "Pending reboot: CBS=$pend, WU=$pend2"
Write-Log '=== Windows Update reset + fresh run finished ==='
