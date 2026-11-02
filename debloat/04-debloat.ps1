$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $PSScriptRoot 'debloat.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}
function Set-RegDword($path, $name, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value ([int]$value) -PropertyType DWord -Force | Out-Null
}
function Set-RegString($path, $name, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null
}
function Remove-AppxByName($name) {
    $found = Get-AppxPackage -AllUsers -Name $name
    if (-not $found) { Write-Log "Appx not installed: $name"; return }
    foreach ($pkg in $found) {
        if ($pkg.NonRemovable) { Write-Log "SKIP non-removable: $($pkg.PackageFullName)"; continue }
        Write-Log "Removing appx: $($pkg.PackageFullName)"
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        if (Get-AppxPackage -AllUsers -Name $name) {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }
    }
    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $name -or $_.PackageName -like "$name*" }
    foreach ($p in $prov) {
        Write-Log "Removing provisioned appx: $($p.PackageName)"
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
    if (Get-AppxPackage -AllUsers -Name $name) { Write-Log "Still present after removal: $name" }
}

Write-Log '=== Debloat started ==='

# Stop Copilot and Teams before removing them.
foreach ($proc in @('copilotapp','Copilot','ms-teams','Teams','Widgets','WidgetService')) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# --- Remove the Copilot desktop app -----------------------------------------
$copilotSetup = Get-ChildItem 'C:\Program Files (x86)\Microsoft\Copilot' -Filter 'copilot_setup.exe' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($copilotSetup) {
    Write-Log "Uninstalling Copilot via $($copilotSetup.FullName)"
    $copilotArgs = @('--uninstall','--mscopilot','--channel=stable','--system-level','--verbose-logging')
    $proc = Start-Process -FilePath $copilotSetup.FullName -ArgumentList $copilotArgs -PassThru -WindowStyle Hidden
    $proc | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
    $proc.Refresh()
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Write-Log 'Copilot uninstall timed out after 180 seconds; process stopped.'
    } else {
        Write-Log "Copilot uninstall exit code: $($proc.ExitCode)"
    }
} else {
    Write-Log 'Copilot setup executable not found; checking appx package.'
}
Remove-AppxByName 'Microsoft.Copilot'

# --- Remove Microsoft consumer/slop appx packages ---------------------------
$removeApps = @(
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.Todos',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.ZuneVideo',
    'Microsoft.OutlookForWindows',
    'Clipchamp.Clipchamp',
    '4DF9E0F8.Netflix',
    'AppleInc.AppleMusicWin',
    'AppleInc.AppleTVWin',
    'Microsoft.Windows.DevHome',
    'Microsoft.Windows.DevHomeGitHubExtension',
    'MicrosoftCorporationII.QuickAssist',
    'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.StartExperiencesApp',
    'Microsoft.WidgetsPlatformRuntime',
    'MicrosoftTeams',
    'Microsoft.Edge.GameAssist'
)
foreach ($app in $removeApps) { Remove-AppxByName $app }

# --- Remove OEM trialware / unwanted Win32 apps -----------------------------
$amdPrivacy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{D8E24EA6-807B-48D0-86D6-A9C5E74B8F2C}'
if (Test-Path $amdPrivacy) {
    Write-Log 'Uninstalling AMD Privacy View'
    Start-Process msiexec.exe -ArgumentList '/X{D8E24EA6-807B-48D0-86D6-A9C5E74B8F2C}','/qn','/norestart' -Wait -WindowStyle Hidden
}

# --- Disable telemetry / inventory services ---------------------------------
$disableServices = @('DiagTrack','dmwappushservice','WerSvc','InventorySvc','MapsBroker','RetailDemo','Fax','RemoteRegistry')
foreach ($svc in $disableServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        if ((Get-Service -Name $svc).StartType -ne 'Disabled') {
            & sc.exe config $svc start= disabled 2>&1 | Out-Null
        }
        Write-Log "Service $svc -> $((Get-Service -Name $svc).StartType)"
    }
}

# --- Disable telemetry scheduled tasks --------------------------------------
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
    $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Disabled task: $($t.Path)$($t.Name)"
    }
}

# --- Telemetry and privacy policies -----------------------------------------
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDumpCollection' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DisableOneSettingsDownloads' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'LoggingDisabled' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messaging' 'AllowMessageSync' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
Set-RegDword 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0

# --- Start menu, taskbar, search, widgets, Copilot, Recall -------------------
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Set-RegDword 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWebOverMeteredConnection' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0

$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-RegDword $adv 'TaskbarDa' 0
Set-RegDword $adv 'TaskbarMn' 0
Set-RegDword $adv 'ShowCopilotButton' 0
Set-RegDword $adv 'SearchboxTaskbarMode' 1
Set-RegDword $adv 'Start_IrisRecommendations' 0
Set-RegDword $adv 'Start_AccountNotifications' 0
Set-RegDword $adv 'Start_TrackProgs' 0
Set-RegDword $adv 'Start_TrackDocs' 0
Set-RegDword $adv 'ShowSyncProviderNotifications' 0

Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
Set-RegDword $cdm 'ContentDeliveryAllowed' 0
Set-RegDword $cdm 'OemPreInstalledAppsEnabled' 0
Set-RegDword $cdm 'PreInstalledAppsEnabled' 0
Set-RegDword $cdm 'SilentInstalledAppsEnabled' 0
Set-RegDword $cdm 'SoftLandingEnabled' 0
Set-RegDword $cdm 'SystemPaneSuggestionsEnabled' 0
Set-RegDword $cdm 'RotatingLockScreenEnabled' 0
Set-RegDword $cdm 'RotatingLockScreenOverlayEnabled' 0
foreach ($id in @('338387','338388','338389','338392','338393','353694','353696','310093','880001')) {
    Set-RegDword $cdm "SubscribedContent-$id`Enabled" 0
}

# --- Edge: Copilot, sidebar, shopping, recommendations, telemetry -----------
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-RegDword $edge 'HubsSidebarEnabled' 0
Set-RegDword $edge 'CopilotPageContext' 0
Set-RegDword $edge 'CopilotCDPPageContext' 0
Set-RegDword $edge 'DiscoverPageContextEnabled' 0
Set-RegDword $edge 'EdgeShoppingAssistantEnabled' 0
Set-RegDword $edge 'PersonalizationReportingEnabled' 0
Set-RegDword $edge 'ShowRecommendationsEnabled' 0
Set-RegDword $edge 'UserFeedbackAllowed' 0
Set-RegDword $edge 'MetricsReportingEnabled' 0
Set-RegDword $edge 'SendSiteInfoToImproveServices' 0
Set-RegDword $edge 'WebWidgetAllowed' 0
Set-RegDword $edge 'StartupBoostEnabled' 0
Set-RegDword $edge 'BackgroundModeEnabled' 0
Set-RegDword $edge 'ShowMicrosoftRewards' 0
Set-RegDword $edge 'PromotionalTabsEnabled' 0
Set-RegDword $edge 'TrackingPrevention' 2
Set-RegDword $edge 'ConfigureDoNotTrack' 1
Set-RegDword $edge 'PaymentMethodQueryEnabled' 0

# --- Office telemetry -------------------------------------------------------
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' 'DisableTelemetry' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' 'SendTelemetry' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Feedback' 'Enabled' 0

# --- Reduce unwanted device metadata / delivery optimization ----------------
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 1

# --- Startup app cleanup (reversible via StartupApproved) -------------------
function Disable-StartupRun($hive, $name) {
    $approved = "Registry::$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $run = "Registry::$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $prop = (Get-ItemProperty -Path $run -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Name.Trim() -eq $name } | Select-Object -First 1
    if ($prop) {
        if (-not (Test-Path $approved)) { New-Item -Path $approved -Force | Out-Null }
        $bytes = [byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0)
        New-ItemProperty -Path $approved -Name $prop.Name -Value $bytes -PropertyType Binary -Force | Out-Null
        Write-Log "Disabled startup: $hive $($prop.Name)"
    }
}
# Startup cleanup is opt-in: add the Run entry names you want to disable.
$userStartup = @()
foreach ($n in $userStartup) { Disable-StartupRun 'HKCU' $n }
# HKLM startup entries are intentionally not changed here.

$startupFolderApproved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
if (-not (Test-Path $startupFolderApproved)) { New-Item -Path $startupFolderApproved -Force | Out-Null }
# Add startup-folder shortcut names here, e.g. @('App.lnk')
$startupFolderShortcuts = @()
foreach ($shortcut in $startupFolderShortcuts) {
    $bytes = [byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0)
    New-ItemProperty -Path $startupFolderApproved -Name $shortcut -Value $bytes -PropertyType Binary -Force | Out-Null
    Write-Log "Disabled startup folder item: $shortcut"
}

Write-Log '=== Debloat complete ==='
Write-Log 'A reboot is recommended before verifying taskbar/search changes.'
