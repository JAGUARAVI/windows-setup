$ErrorActionPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\debloat\verification.txt'
$lines = @()
$lines += "Verification: $(Get-Date -Format o)"
$lines += ''
$lines += '--- Disk ---'
$lines += (Get-Volume -DriveLetter C | Select-Object DriveLetter, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,2)}} | Format-List | Out-String)
$lines += '--- Telemetry services ---'
$lines += (Get-Service DiagTrack, dmwappushservice, WerSvc, InventorySvc, MapsBroker, RetailDemo, Fax, RemoteRegistry -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-String)
$lines += '--- Telemetry tasks ---'
$lines += (Get-ScheduledTask | Where-Object {
    $_.TaskPath -match 'Application Experience|Customer Experience|Feedback|Windows Error Reporting|Disk Diagnostic' -and $_.State -ne 'Disabled'
} | Select-Object TaskName, TaskPath, State | Format-Table -AutoSize | Out-String)
$lines += '--- Privacy registry ---'
$privacy = [ordered]@{
    AllowTelemetry              = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry).AllowTelemetry
    ConsumerFeatures            = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures).DisableWindowsConsumerFeatures
    Copilot                     = (Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name TurnOffWindowsCopilot).TurnOffWindowsCopilot
    Recall                      = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name DisableAIDataAnalysis).DisableAIDataAnalysis
    Widgets                     = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name AllowNewsAndInterests).AllowNewsAndInterests
    WebSearch                   = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name DisableWebSearch).DisableWebSearch
    SearchBoxSuggestions        = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name DisableSearchBoxSuggestions).DisableSearchBoxSuggestions
    TailoredExperiences         = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name TailoredExperiencesWithDiagnosticDataEnabled).TailoredExperiencesWithDiagnosticDataEnabled
    AdvertisingID               = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled).Enabled
    ActivityFeed                = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableActivityFeed).EnableActivityFeed
    EdgeSidebar                 = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name HubsSidebarEnabled).HubsSidebarEnabled
    EdgeCopilotPageContext      = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name CopilotPageContext).CopilotPageContext
    EdgeMetrics                 = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name MetricsReportingEnabled).MetricsReportingEnabled
    StartRecommendations        = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_IrisRecommendations).Start_IrisRecommendations
    StartTrackProgs             = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_TrackProgs).Start_TrackProgs
    TaskbarWidgets              = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarDa).TaskbarDa
    TaskbarCopilot              = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ShowCopilotButton).ShowCopilotButton
}
$privacy.GetEnumerator() | ForEach-Object { $lines += ("{0}: {1}" -f $_.Key, $_.Value) }
$lines += ''
$lines += '--- Removed apps check (should be empty) ---'
$checkApps = @('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.PowerAutomateDesktop','Microsoft.Todos','Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.ZuneVideo','Microsoft.OutlookForWindows','Clipchamp.Clipchamp','4DF9E0F8.Netflix','AppleInc.AppleMusicWin','AppleInc.AppleTVWin','Microsoft.Windows.DevHome','MicrosoftCorporationII.QuickAssist','MicrosoftCorporationII.MicrosoftFamily','Microsoft.StartExperiencesApp','Microsoft.WidgetsPlatformRuntime','MicrosoftTeams','Microsoft.Edge.GameAssist','Microsoft.Copilot')
$lines += (Get-AppxPackage -AllUsers -Name $checkApps | Select-Object Name, Version | Format-Table -AutoSize | Out-String)
$lines += '--- Copilot folder ---'
$lines += (Get-ChildItem 'C:\Program Files (x86)\Microsoft\Copilot' -ErrorAction SilentlyContinue | Select-Object Name | Format-Table -AutoSize | Out-String)
$lines += '--- Startup entries ---'
$lines += (Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, User | Format-Table -AutoSize | Out-String)
$lines += '--- Driver versions ---'
$lines += (Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate | Format-Table -AutoSize | Out-String)
$lines += (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription, DriverVersion, DriverDate | Format-Table -AutoSize | Out-String)
$lines += '--- Pending reboot ---'
$lines += "Pending: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')"
$lines += "WindowsUpdate pending: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')"
$lines += ''
$lines += '--- Windows Update available (if scan has run) ---'
if (Test-Path 'C:\Users\Public\debloat\windows-updates-available.csv') {
    $lines += (Import-Csv 'C:\Users\Public\debloat\windows-updates-available.csv' | Select-Object Title, Type, DriverClass, SecurityBulletin | Format-Table -AutoSize | Out-String)
}
$lines | Set-Content $out -Encoding UTF8
Get-Content $out
