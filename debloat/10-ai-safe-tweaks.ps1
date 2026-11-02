$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $PSScriptRoot 'ai-safe-tweaks.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}
function Set-RegDword($path, $name, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value ([int]$value) -PropertyType DWord -Force | Out-Null
}

Write-Log '=== Safe AI tweaks started ==='

# Policy changes only; no game/anti-cheat processes are touched.

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $PSScriptRoot "ai-policy-backup-$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$keys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
)
$i = 0
foreach ($k in $keys) {
    $i++
    $file = Join-Path $backupDir ("ai-policy-{0:D2}.reg" -f $i)
    & reg.exe export $k $file /y 2>&1 | Out-Null
    if (Test-Path $file) { Write-Log "Backed up $k" }
}

# Official AI policy gaps.
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'RemoveMicrosoftCopilotApp' 1

# Paint AI features.
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 1

# Prevent WSAIFabricSvc from starting automatically, but do not force-stop dependents.
$svc = Get-Service -Name WSAIFabricSvc -ErrorAction SilentlyContinue
if ($svc) {
    Write-Log "WSAIFabricSvc before: $($svc.Status) / $($svc.StartType)"
    Set-Service -Name WSAIFabricSvc -StartupType Manual -ErrorAction SilentlyContinue
    if ((Get-Service -Name WSAIFabricSvc).StartType -ne 'Manual') {
        & sc.exe config WSAIFabricSvc start= demand 2>&1 | Out-Null
    }
    if ((Get-Service -Name WSAIFabricSvc).Status -eq 'Running') {
        Stop-Service -Name WSAIFabricSvc -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    $svc2 = Get-Service -Name WSAIFabricSvc
    Write-Log "WSAIFabricSvc after: $($svc2.Status) / $($svc2.StartType)"
} else {
    Write-Log 'WSAIFabricSvc not found.'
}

Write-Log 'Policies:'
Write-Log "  AllowRecallEnablement = $((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name AllowRecallEnablement).AllowRecallEnablement)"
Write-Log "  RemoveMicrosoftCopilotApp = $((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name RemoveMicrosoftCopilotApp).RemoveMicrosoftCopilotApp)"
Write-Log "  Paint DisableCocreator = $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' -Name DisableCocreator).DisableCocreator)"
Write-Log '=== Safe AI tweaks finished ==='
