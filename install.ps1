#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installs the Shibumi/end4 Windows rice (komorebi + YASB + Windhawk + terminal).

.PARAMETER Debloat
  Also run the debloat scripts (04, 08, 10, 06). Read debloat/HANDOFF.md first.
.PARAMETER Force
  Skip the debloat confirmation prompt.
.PARAMETER SkipWindhawk
  Do not install Windhawk or the taskbar mods.
#>
[CmdletBinding()]
param(
    [switch]$Debloat,
    [switch]$Force,
    [switch]$SkipWindhawk
)

$ErrorActionPreference = 'Stop'
$Repo       = $PSScriptRoot
$HomeDir    = $env:USERPROFILE
$ConfigDir  = Join-Path $HomeDir '.config'
$RiceDir    = Join-Path $ConfigDir 'rice'
$Documents  = [Environment]::GetFolderPath('MyDocuments')
$Terminal   = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$Flow       = Join-Path $env:APPDATA 'FlowLauncher\Settings\Settings.json'

function Write-Step([string]$Text) {
    Write-Host "`n== $Text" -ForegroundColor Cyan
}

function Update-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $bak = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
        Write-Host "  backup: $bak"
    }
}

function Copy-WithBackup([string]$Source, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Backup-File $Destination
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Install-Winget([string]$Id) {
    Write-Host "  winget install $Id"
    $output = winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget returned $LASTEXITCODE for $Id"
        $output | Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" }
    }
}

Write-Step 'Installing packages'
Update-Path
$packages = @(
    'LGUG2Z.komorebi',
    'LGUG2Z.whkd',
    'LGUG2Z.masir',
    'AmN.yasb',
    'Flow-Launcher.Flow-Launcher',
    'DEVCOM.JetBrainsMonoNerdFont',
    'Fastfetch-cli.Fastfetch',
    'Git.Git',
    'Zen-Team.Zen-Browser'
)
foreach ($pkg in $packages) { Install-Winget $pkg }
Update-Path

Write-Step 'Fetching komorebi application rules'
if (Get-Command komorebic -ErrorAction SilentlyContinue) {
    & komorebic fetch-asc 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
}

Write-Step 'Installing Oh My Posh'
$ompBinDir = Join-Path $ConfigDir 'ohmyposh\bin'
New-Item -ItemType Directory -Force -Path $ompBinDir | Out-Null
$ompExe = Join-Path $ompBinDir 'oh-my-posh.exe'
if (-not (Test-Path $ompExe)) {
    Invoke-WebRequest 'https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-windows-amd64.exe' -OutFile $ompExe -UseBasicParsing
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$ompBinDir*") {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $ompBinDir), 'User')
}

if (-not $SkipWindhawk) {
    Write-Step 'Installing Windhawk 2.0 + taskbar mods'
    $cli = 'C:\Program Files\Windhawk\windhawk-cli.exe'
    if (-not (Test-Path $cli)) {
        $setup = Join-Path $env:TEMP 'windhawk_setup_offline.exe'
        & curl.exe -L --retry 5 --retry-all-errors -o $setup `
            'https://github.com/ramensoftware/windhawk/releases/download/2.0.0-alpha.8/windhawk_setup_offline.exe'
        if (Test-Path $setup) {
            Start-Process -FilePath $setup -ArgumentList '/S' -Wait
        }
    }
    if (Test-Path $cli) {
        & $cli mod install windows-11-taskbar-styler
        & $cli mod settings write windows-11-taskbar-styler (Join-Path $Repo 'windhawk\taskbar-styler.json')
        # Drop the old conditional auto-hide mod if upgrading from a previous install.
        & $cli mod remove taskbar-auto-hide-when-maximized --yes 2>$null | Out-Null
        Set-Service Windhawk -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service Windhawk -ErrorAction SilentlyContinue
    } else {
        Write-Warning 'Windhawk CLI not found; taskbar styling was skipped.'
    }
}

Write-Step 'Copying rice configs'
Copy-WithBackup (Join-Path $Repo 'config\komorebi\komorebi.json') (Join-Path $ConfigDir 'komorebi\komorebi.json')
Copy-WithBackup (Join-Path $Repo 'config\whkd\whkdrc') (Join-Path $ConfigDir 'whkdrc')
foreach ($f in @('config.yaml', 'styles.css', 'yasb_colors.css')) {
    Copy-WithBackup (Join-Path $Repo "config\yasb\$f") (Join-Path $ConfigDir "yasb\$f")
}
Copy-WithBackup (Join-Path $Repo 'config\ohmyposh\shibumi.omp.json') (Join-Path $ConfigDir 'ohmyposh\shibumi.omp.json')
foreach ($f in @('config.jsonc', 'logo.txt')) {
    Copy-WithBackup (Join-Path $Repo "config\fastfetch\$f") (Join-Path $ConfigDir "fastfetch\$f")
}
Copy-WithBackup (Join-Path $Repo 'config\terminal\settings.json') $Terminal
Copy-WithBackup (Join-Path $Repo 'config\flow\Settings.json') $Flow

$profileSource = Join-Path $Repo 'config\powershell\Microsoft.PowerShell_profile.ps1'
foreach ($dir in @('WindowsPowerShell', 'PowerShell')) {
    Copy-WithBackup $profileSource (Join-Path $Documents "$dir\Microsoft.PowerShell_profile.ps1")
}

foreach ($script in @('send-f11.ps1', 'send-media.ps1', 'start-komorebi.ps1', 'set-default-browser.ps1')) {
    Copy-WithBackup (Join-Path $Repo "scripts\$script") (Join-Path $RiceDir $script)
}
Copy-WithBackup (Join-Path $Repo 'tools\SFTA.ps1') (Join-Path $RiceDir 'tools\SFTA.ps1')

Write-Step 'Applying Windows tweaks'
$terminalKey = 'HKCU:\Console\%%Startup'
New-Item -Path $terminalKey -Force | Out-Null
Set-ItemProperty $terminalKey -Name DelegationConsole  -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
Set-ItemProperty $terminalKey -Name DelegationTerminal -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'

$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
foreach ($pair in @(
    @('TaskbarAl', 1),
    @('SearchboxTaskbarMode', 1),
    @('ShowTaskViewButton', 0),
    @('TaskbarMn', 0)
)) {
    New-ItemProperty -Path $advanced -Name $pair[0] -Value $pair[1] -PropertyType DWord -Force | Out-Null
}
# TaskbarDa is protected on some builds; ignore failures.
try { New-ItemProperty -Path $advanced -Name TaskbarDa -Value 0 -PropertyType DWord -Force | Out-Null } catch {}

$theme = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-ItemProperty -Path $theme -Name AppsUseLightTheme    -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $theme -Name SystemUsesLightTheme -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $theme -Name EnableTransparency   -Value 1 -PropertyType DWord -Force | Out-Null

# Native taskbar auto-hide: the dock stays hidden and reveals on bottom-edge hover.
$stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
if (Test-Path $stuck) {
    $stuckSettings = (Get-ItemProperty $stuck -Name Settings).Settings
    $stuckSettings[8] = 3
    Set-ItemProperty $stuck -Name Settings -Value $stuckSettings
    Write-Host '  taskbar auto-hide set (applies after explorer restart / logon)'
}

Write-Step 'Configuring Flow Launcher startup'
if (Test-Path $Flow) {
    $flowJson = Get-Content -LiteralPath $Flow -Raw | ConvertFrom-Json
    $flowJson.StartFlowLauncherOnSystemStartup = $true
    $flowJson.IgnoreHotkeysOnFullscreen = $true
    $flowText = $flowJson | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Flow, $flowText, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Step 'Creating komorebi logon task'
$yasbc = 'C:\Program Files\YASB\yasbc.exe'
if (Test-Path $yasbc) { & $yasbc enable-autostart }
$startScript = Join-Path $RiceDir 'start-komorebi.ps1'
$taskRun = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $startScript"
& schtasks.exe /Create /SC ONLOGON /DELAY 0000:15 /TN 'komorebi-shibumi' /TR $taskRun /RL LIMITED /F | Out-Null

Write-Step 'Zen Browser'
if (Test-Path 'C:\Program Files\Zen Browser\zen.exe') {
    & (Join-Path $RiceDir 'set-default-browser.ps1')
} else {
    Write-Warning 'Zen Browser not found. Install it and rerun scripts\set-default-browser.ps1.'
}

if ($Debloat) {
    Write-Step 'Debloat'
    if (-not $Force) {
        $answer = Read-Host 'Debloat removes apps/services and changes policies. Continue? (y/N)'
        if ($answer -ne 'y') {
            Write-Warning 'Debloat skipped.'
            $Debloat = $false
        }
    }
    if ($Debloat) {
        foreach ($script in @('04-debloat.ps1', '08-privacy-extra.ps1', '10-ai-safe-tweaks.ps1', '06-verify.ps1')) {
            Write-Host "  running debloat\$script"
            & (Join-Path $Repo "debloat\$script")
        }
    }
}

Write-Host @"

============================================================
Done.

Next:
  - Log off and back on (komorebi task starts 15 s after logon).
  - Shortcuts: Win+Return terminal, Win+Space Flow, Win+W Zen,
    Win+D maximize, Win+Shift+D monocle, Win+F fullscreen.
  - If Zen is not default: Settings > Apps > Default apps >
    Zen Browser > Set default (Windows 11 UCPD blocks scripts).
  - Read README.md and debloat/HANDOFF.md.

"@ -ForegroundColor Green
