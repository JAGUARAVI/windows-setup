#Requires -RunAsAdministrator
<#
Sets Zen Browser as the default browser if possible.

Windows 11 24H2+ ships the UCPD driver, which blocks writes to the
UserChoice registry keys. This script:
  1. tries Zen's own `-setDefaultBrowser` flag,
  2. verifies the http association,
  3. if UCPD blocked it, opens the native Settings page for Zen and
     tells you to click "Set default".

No binary, no registry hash patching, no UCPD bypass.
#>

$ErrorActionPreference = 'Stop'
$zenExe = 'C:\Program Files\Zen Browser\zen.exe'

if (-not (Test-Path $zenExe)) {
    Write-Error 'Zen Browser is not installed at C:\Program Files\Zen Browser\zen.exe'
    return
}

# Find Zen's StartMenuInternet registration (e.g. Firefox-F0DC299D809B9700).
$registration = Get-ChildItem 'HKLM:\SOFTWARE\Clients\StartMenuInternet' -ErrorAction SilentlyContinue |
    Where-Object {
        $caps = Join-Path $_.PSPath 'Capabilities'
        (Get-ItemProperty -Path $caps -ErrorAction SilentlyContinue).ApplicationName -eq 'Zen'
    } |
    Select-Object -First 1

if (-not $registration) {
    Write-Error 'Zen is not registered as a StartMenuInternet browser.'
    return
}

$zenKey = $registration.PSChildName
$capsPath = Join-Path $registration.PSPath 'Capabilities\URLAssociations'
$caps = Get-ItemProperty $capsPath -ErrorAction SilentlyContinue
$urlProg = $caps.http

Write-Host "Zen registration: $zenKey"
Write-Host "Zen URL ProgId:   $urlProg"

# Ask Zen itself first. On many Windows 11 builds this only opens Settings.
try {
    Start-Process -FilePath $zenExe -ArgumentList '-setDefaultBrowser' -WindowStyle Hidden
    Start-Sleep -Seconds 3
} catch {}

$choicePath = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
$choice = Get-ItemProperty -Path $choicePath -ErrorAction SilentlyContinue
if ($choice -and $choice.ProgId -eq $urlProg) {
    Write-Host 'Zen is already the default browser.' -ForegroundColor Green
    return
}

# Fallback for older Windows builds without UCPD: PS-SFTA.
$ucpd = Get-Service UCPD -ErrorAction SilentlyContinue
$sfta = Join-Path $PSScriptRoot '..\tools\SFTA.ps1'
if (-not $ucpd -and (Test-Path $sfta)) {
    . $sfta
    Set-PTA $urlProg http
    Set-PTA $urlProg https
    $htmlProg = $urlProg -replace '^FirefoxURL-', 'FirefoxHTML-'
    Set-FTA $htmlProg .html
    Set-FTA $htmlProg .htm
    Write-Host 'Zen associations applied with PS-SFTA.' -ForegroundColor Green
    return
}

# UCPD path: the native Settings page is the only allowed way.
Start-Process "ms-settings:defaultapps?registeredAppUser=$zenKey"
Write-Host ''
Write-Host 'Windows 11 UCPD blocks scripted browser defaults.' -ForegroundColor Yellow
Write-Host 'A Settings page for Zen Browser has been opened.'
Write-Host 'Click "Set default" once and Windows will apply HTTP, HTTPS, .html and .htm.'
