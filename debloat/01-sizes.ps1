$ErrorActionPreference = 'SilentlyContinue'
$dirs = @(
    'C:\Users',
    'C:\Windows',
    'C:\Program Files',
    'C:\Program Files (x86)',
    'C:\ProgramData',
    'C:\Games',
    'C:\XboxGames',
    'C:\AMD',
    'C:\Recovery',
    'C:\$SysReset',
    'C:\System Volume Information',
    'C:\.cache'
)
$results = foreach ($d in $dirs) {
    if (Test-Path -LiteralPath $d) {
        $m = Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        [pscustomobject]@{
            Path  = $d
            GB    = [math]::Round($m.Sum / 1GB, 2)
            Files = $m.Count
        }
    }
}
$results | Sort-Object GB -Descending | Format-Table -AutoSize
