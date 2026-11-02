# shibumi / end4 shell
$omp = Join-Path $env:USERPROFILE '.config\ohmyposh\bin\oh-my-posh.exe'
if (Test-Path $omp) {
    & $omp init pwsh --config "$env:USERPROFILE\.config\ohmyposh\shibumi.omp.json" | Invoke-Expression
}

try {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
} catch {}

Set-Alias ll Get-ChildItem
$ff = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\fastfetch.exe'
if (Test-Path $ff) {
    Set-Alias fastfetch $ff
    Set-Alias ff $ff
}

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
