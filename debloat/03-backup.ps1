$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "C:\Users\Public\debloat\backup-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$log = Join-Path $backup 'backup.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}

Write-Log "Backup folder: $backup"
$freeGB = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining / 1GB, 2)
Write-Log "Free space: $freeGB GB"

$regKeys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows',
    'HKCU\SOFTWARE\Policies\Microsoft\Windows',
    'HKLM\SOFTWARE\Policies\Microsoft\Edge',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Search',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy',
    'HKCU\Software\Microsoft\Siuf',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'
)
$i = 0
foreach ($key in $regKeys) {
    $i++
    $file = Join-Path $backup ("reg-{0:D2}.reg" -f $i)
    & reg.exe export $key $file /y 2>&1 | Out-Null
    Write-Log "Exported $key"
}

Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, Version, Architecture, Publisher, NonRemovable |
    Export-Csv (Join-Path $backup 'appx-before.csv') -NoTypeInformation -Encoding UTF8
Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName, Version |
    Export-Csv (Join-Path $backup 'appx-provisioned-before.csv') -NoTypeInformation -Encoding UTF8
Get-Service | Select-Object Name, DisplayName, Status, StartType |
    Export-Csv (Join-Path $backup 'services-before.csv') -NoTypeInformation -Encoding UTF8
Get-ScheduledTask | Select-Object TaskName, TaskPath, State |
    Export-Csv (Join-Path $backup 'tasks-before.csv') -NoTypeInformation -Encoding UTF8
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User |
    Export-Csv (Join-Path $backup 'startup-before.csv') -NoTypeInformation -Encoding UTF8
Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer, DeviceClass |
    Export-Csv (Join-Path $backup 'drivers-before.csv') -NoTypeInformation -Encoding UTF8
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString, QuietUninstallString |
    Export-Csv (Join-Path $backup 'programs-before.csv') -NoTypeInformation -Encoding UTF8
powercfg /list | Out-File (Join-Path $backup 'power-plans.txt') -Encoding utf8
& pnputil.exe /enum-drivers | Out-File (Join-Path $backup 'pnputil-drivers.txt') -Encoding utf8
Get-ComputerRestorePoint | Out-File (Join-Path $backup 'restore-points-before.txt') -Encoding utf8
vssadmin list shadowstorage | Out-File (Join-Path $backup 'shadowstorage-before.txt') -Encoding utf8

if ($freeGB -ge 3) {
    Write-Log 'Enabling System Restore and setting 10 GB max shadow storage.'
    Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
    & vssadmin.exe resize shadowstorage /for=C: /on=C: /maxsize=10GB 2>&1 | Out-Null
    Checkpoint-Computer -Description "Pre-debloat $stamp" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    $rp = Get-ComputerRestorePoint | Select-Object -Last 1
    if ($rp) { Write-Log "Restore point created: $($rp.Description) $($rp.CreationTime)" }
    else { Write-Log 'WARNING: No restore point was created. Registry and inventory backups are still available.' }
} else {
    Write-Log 'WARNING: Not enough free space for a restore point. Registry and inventory backups were created.'
}

Write-Log 'Backup complete.'
Write-Output $backup
