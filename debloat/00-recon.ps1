$ErrorActionPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\debloat'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
$gpu = Get-CimInstance Win32_VideoController
$secureBoot = try { Confirm-SecureBootUEFI } catch { 'Unknown' }
$tpmReady = try { (Get-Tpm).TpmReady } catch { 'Unknown' }

$summary = [ordered]@{
    Caption        = $os.Caption
    Version        = $os.Version
    Build          = $os.BuildNumber
    Architecture   = $os.OSArchitecture
    InstallDate    = $os.InstallDate
    LastBoot       = $os.LastBootUpTime
    Manufacturer   = $cs.Manufacturer
    Model          = $cs.Model
    RAM_GB         = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    CPU            = $cpu.Name
    Cores          = $cpu.NumberOfCores
    Threads        = $cpu.NumberOfLogicalProcessors
    GPU            = ($gpu | ForEach-Object { $_.Name }) -join ' | '
    GPUDriver      = ($gpu | ForEach-Object { "$($_.Name) $($_.DriverVersion) $($_.DriverDate)" }) -join ' | '
    SecureBoot     = $secureBoot
    TPM            = $tpmReady
    DefAntiSpyware = (Get-MpComputerStatus).AMServiceEnabled
    DefRealTime    = (Get-MpComputerStatus).RealTimeProtectionEnabled
    FirewallDomain = (Get-NetFirewallProfile -Profile Domain).Enabled
    FirewallPublic = (Get-NetFirewallProfile -Profile Public).Enabled
    PowerPlan      = (powercfg /getactivescheme)
}
$summary.GetEnumerator() | ForEach-Object { "{0}: {1}" -f $_.Key, $_.Value } | Set-Content "$out\summary.txt"

Get-AppxPackage -AllUsers | Sort-Object Name |
    Select-Object Name, PackageFullName, Version, Architecture, Publisher, InstallLocation, IsFramework |
    Export-Csv "$out\appx-all.csv" -NoTypeInformation -Encoding UTF8

Get-AppxPackage | Sort-Object Name |
    Select-Object Name, PackageFullName, Version, Architecture, Publisher |
    Export-Csv "$out\appx-current-user.csv" -NoTypeInformation -Encoding UTF8

Get-AppxProvisionedPackage -Online | Sort-Object DisplayName |
    Select-Object DisplayName, PackageName, Version, Architecture |
    Export-Csv "$out\appx-provisioned.csv" -NoTypeInformation -Encoding UTF8

$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $uninstallKeys |
    Where-Object DisplayName |
    Sort-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString |
    Export-Csv "$out\win32-programs.csv" -NoTypeInformation -Encoding UTF8

Get-CimInstance Win32_StartupCommand | Sort-Object Name |
    Select-Object Name, Command, Location, User |
    Export-Csv "$out\startup.csv" -NoTypeInformation -Encoding UTF8

Get-Service |
    Where-Object { $_.Name -in @('DiagTrack','dmwappushservice','WpnService','WSearch','SysMain','MapsBroker','PhoneSvc','RetailDemo','Fax','WerSvc','Spooler','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','BITS','DoSvc','InstallService','WaaSMedicSvc') } |
    Select-Object Name, DisplayName, Status, StartType |
    Export-Csv "$out\services.csv" -NoTypeInformation -Encoding UTF8

Get-ScheduledTask | Where-Object {
    $_.TaskPath -match 'Application Experience|Customer Experience|Feedback|Windows Error Reporting|Disk Diagnostic|Autochk|WindowsUpdate|InstallService|ProgramDataUpdater|CEIP|Inventory|Telemetry|Compatibility|CloudExperienceHost|UnifiedTelemetry'
} | Sort-Object TaskPath, TaskName |
    Select-Object TaskName, TaskPath, State |
    Export-Csv "$out\telemetry-tasks.csv" -NoTypeInformation -Encoding UTF8

Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.DeviceClass -in @('DISPLAY','NET','MEDIA','SYSTEM','USB','BLUETOOTH','HDC','SCSIADAPTER','MOUSE','KEYBOARD') -and $_.DriverDate } |
    Sort-Object DriverDate |
    Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer, DeviceClass |
    Export-Csv "$out\drivers.csv" -NoTypeInformation -Encoding UTF8

Get-PnpDevice | Where-Object { $_.Status -ne 'OK' } |
    Select-Object Status, Class, FriendlyName, InstanceId, Problem |
    Export-Csv "$out\problem-devices.csv" -NoTypeInformation -Encoding UTF8

$privacy = [ordered]@{
    AdvertisingID_Enabled                 = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled).Enabled
    TailoredExperiences                   = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name TailoredExperiencesWithDiagnosticDataEnabled).TailoredExperiencesWithDiagnosticDataEnabled
    FeedbackFrequency                     = (Get-ItemProperty 'HKCU:\Software\Microsoft\Siuf\Rules' -Name NumberOfSIUFInPeriod).NumberOfSIUFInPeriod
    ActivityFeed_EnableActivityFeed       = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableActivityFeed).EnableActivityFeed
    ActivityFeed_PublishUserActivities    = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name PublishUserActivities).PublishUserActivities
    ActivityFeed_UploadUserActivities     = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name UploadUserActivities).UploadUserActivities
    DataCollection_AllowTelemetry         = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry).AllowTelemetry
    DiagTrack_StartType                   = (Get-Service DiagTrack).StartType
    Copilot_Policy                        = (Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name TurnOffWindowsCopilot).TurnOffWindowsCopilot
    Recall_Policy                         = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name DisableAIDataAnalysis).DisableAIDataAnalysis
    ConsumerFeatures                      = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures).DisableWindowsConsumerFeatures
    SearchBoxSuggestions                  = (Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name DisableSearchBoxSuggestions).DisableSearchBoxSuggestions
    Widgets_Policy                        = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name AllowNewsAndInterests).AllowNewsAndInterests
    Start_TrackProgs                      = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_TrackProgs).Start_TrackProgs
    Edge_Sidebar                         = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name HubsSidebarEnabled).HubsSidebarEnabled
}
$privacy.GetEnumerator() | ForEach-Object { "{0}: {1}" -f $_.Key, $_.Value } | Set-Content "$out\privacy-before.txt"

Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Enabled' |
    Select-Object FeatureName |
    Export-Csv "$out\optional-features-enabled.csv" -NoTypeInformation -Encoding UTF8

Get-Volume | Where-Object DriveLetter |
    Select-Object DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} |
    Export-Csv "$out\volumes.csv" -NoTypeInformation -Encoding UTF8

Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn |
    Export-Csv "$out\recent-updates.csv" -NoTypeInformation -Encoding UTF8

"Recon complete: $(Get-Date -Format o)" | Set-Content "$out\recon-done.txt"
