$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\Public\debloat\cleanup.log'
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}
function Get-FolderSizeGB($path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return [math]::Round($sum / 1GB, 2)
}
function Remove-Contents($path) {
    if (Test-Path -LiteralPath $path) {
        $before = Get-FolderSizeGB $path
        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after = Get-FolderSizeGB $path
        if ($before -gt 0) { Write-Log "Cleaned $path : $before GB -> $after GB" }
    }
}
function Remove-OldFiles($path, $days) {
    if (Test-Path -LiteralPath $path) {
        $cutoff = (Get-Date).AddDays(-$days)
        Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log "Removed files older than $days days from $path"
    }
}

$freeBefore = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining / 1GB, 2)
Write-Log "Free before cleanup: $freeBefore GB"

# Stop update-related services so their caches can be cleared.
foreach ($svc in @('wuauserv','bits','dosvc','usosvc')) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
}

Remove-Contents 'C:\Windows\SoftwareDistribution\Download'
Remove-Contents 'C:\Windows\Temp'
Remove-Contents "$env:LOCALAPPDATA\Temp"
Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\Temp'
Remove-Contents 'C:\Windows\Minidump'
Remove-Contents 'C:\Windows\LiveKernelReports'
Remove-Contents "$env:LOCALAPPDATA\CrashDumps"
Remove-Contents "$env:LOCALAPPDATA\D3DSCache"
Remove-Contents "$env:LOCALAPPDATA\NVIDIA\DXCache"
Remove-Contents "$env:LOCALAPPDATA\NVIDIA\GLCache"
Remove-Contents "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
Remove-Contents "$env:LOCALAPPDATA\AMD\DxCache"
Remove-Contents "$env:LOCALAPPDATA\AMD\GLCache"
Remove-Contents 'C:\ProgramData\NVIDIA Corporation\Downloader'
Remove-Contents 'C:\NVIDIA'
Remove-Contents 'C:\AMD'
Remove-Contents 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
Remove-Contents 'C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache'

# Browser caches only. Profiles, passwords and bookmarks are untouched.
# Add your own app cache paths here if you want.
$cacheDirs = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\DawnCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\ShaderCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\GraphiteDawnCache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\ShaderCache"
)
foreach ($dir in $cacheDirs) { Remove-Contents $dir }

# Firefox cache2 folders.
Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Contents (Join-Path $_.FullName 'cache2')
}

# Old logs only, leave recent ones.
Remove-OldFiles 'C:\Windows\Logs\CBS' 14
Remove-OldFiles 'C:\Windows\Logs' 30

if (Test-Path 'C:\Windows\MEMORY.DMP') {
    $dmp = (Get-Item 'C:\Windows\MEMORY.DMP').Length / 1GB
    Remove-Item 'C:\Windows\MEMORY.DMP' -Force -ErrorAction SilentlyContinue
    Write-Log ("Removed C:\Windows\MEMORY.DMP ({0:N2} GB)" -f $dmp)
}

Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Log 'Emptied Recycle Bin'

foreach ($svc in @('wuauserv','bits','dosvc','usosvc')) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}

$freeAfter = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining / 1GB, 2)
Write-Log "Free after cleanup: $freeAfter GB (freed $([math]::Round($freeAfter - $freeBefore, 2)) GB)"
