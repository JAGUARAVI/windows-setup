$ErrorActionPreference = 'SilentlyContinue'
$backup = Get-ChildItem 'C:\Users\Public\debloat' -Directory -Filter 'backup-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $backup) { Write-Error 'No backup folder found.'; return }
Write-Host "Using backup: $($backup.FullName)"

# Restore registry exports.
Get-ChildItem $backup.FullName -Filter 'reg-*.reg' | ForEach-Object {
    Write-Host "Importing $($_.Name)"
    & reg.exe import $_.FullName 2>&1 | Out-Null
}

# Restore service startup types from the pre-change inventory.
$services = Import-Csv (Join-Path $backup.FullName 'services-before.csv')
foreach ($s in $services) {
    if ($s.StartType -in @('Automatic','Manual','Disabled')) {
        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction SilentlyContinue
    }
}

# Re-enable telemetry tasks that were disabled by the debloat script.
$tasks = @(
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser Exp' },
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' },
    @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClient' },
    @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClientOnScenarioDownload' },
    @{ Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting' },
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
    @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
)
foreach ($t in $tasks) {
    if (Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue) {
        Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
    }
}

# Re-enable startup entries that were disabled.
# Add the startup entry names you disabled so rollback can re-enable them.
$startupNames = @()
$approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$enabled = [byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0)
foreach ($n in $startupNames) {
    if (Test-Path $approved) { New-ItemProperty -Path $approved -Name $n -Value $enabled -PropertyType Binary -Force | Out-Null }
}
$approvedFolder = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
# Add startup-folder shortcuts you disabled, e.g. @('App.lnk')
foreach ($n in @()) {
    if (Test-Path $approvedFolder) { New-ItemProperty -Path $approvedFolder -Name $n -Value $enabled -PropertyType Binary -Force | Out-Null }
}

Write-Host 'Registry, services, tasks and startup entries restored.'
Write-Host 'Removed Store apps can be reinstalled from the Microsoft Store. See appx-before.csv for the exact list.'
Write-Host 'A System Restore point (if created) can also be used: rstrui.exe'
