$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\debloat\updates.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}

Write-Log '=== Windows Update scan started ==='
foreach ($svc in @('wuauserv','bits','cryptsvc')) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}

try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 0
    Write-Log 'Searching Windows Update...'
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
    Write-Log "Found $($result.Updates.Count) update(s)."
    $rows = foreach ($u in $result.Updates) {
        [pscustomobject]@{
            Title            = $u.Title
            Type             = if ($u.Type -eq 2) { 'Driver' } else { 'Software' }
            BrowseOnly       = $u.BrowseOnly
            DriverClass      = $u.DriverClass
            DriverModel      = $u.DriverModel
            DriverProvider   = $u.DriverProvider
            DriverVersion    = $u.DriverVerDate
            Categories       = ($u.Categories | ForEach-Object { $_.Name }) -join '; '
            SecurityBulletin = $u.SecurityBulletinID
            MsrcSeverity     = $u.MsrcSeverity
            IsDownloaded     = $u.IsDownloaded
            RebootRequired   = $u.RebootRequired
        }
    }
    $rows | Export-Csv 'C:\Users\Public\debloat\windows-updates-available.csv' -NoTypeInformation -Encoding UTF8
    $rows | Format-Table -AutoSize | Out-String -Width 300 | Write-Host

    $selected = @()
    foreach ($u in $result.Updates) {
        $isDriver = ($u.Type -eq 2)
        $cats = ($u.Categories | ForEach-Object { $_.Name }) -join '; '
        $isSecurity = ($cats -match 'Security Updates|Critical Updates|Definition Updates|Update Rollup') -and (-not $u.BrowseOnly)
        $isFeature = $cats -match 'Upgrades|Feature packs'
        if ($isDriver -or ($isSecurity -and -not $isFeature)) {
            $selected += $u
        }
    }
    Write-Log "Selected $($selected.Count) driver/security update(s) for installation."

    if ($selected.Count -gt 0) {
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $selected) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }
            $coll.Add($u) | Out-Null
        }
        Write-Log 'Downloading selected updates...'
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $coll
        $dl = $downloader.Download()
        Write-Log "Download result code: $($dl.ResultCode) (2=Succeeded, 3=SucceededWithErrors)"

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $coll
        Write-Log 'Installing selected updates...'
        $install = $installer.Install()
        Write-Log "Install result code: $($install.ResultCode) (2=Succeeded, 3=SucceededWithErrors)"
        Write-Log "Reboot required: $($install.RebootRequired)"
        for ($i = 0; $i -lt $coll.Count; $i++) {
            $u = $coll.Item($i)
            $r = $install.GetUpdateResult($i)
            Write-Log ("  {0} -> result {1}" -f $u.Title, $r.ResultCode)
        }
    } else {
        Write-Log 'No driver/security updates selected.'
    }
} catch {
    Write-Log "Windows Update error: $($_.Exception.Message)"
}

Write-Log '=== Windows Update scan finished ==='
