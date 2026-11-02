$ErrorActionPreference = 'SilentlyContinue'
$out = 'C:\Users\Public\debloat\subfolder-sizes.csv'
$results = @()
$roots = @(
    'C:\Program Files',
    'C:\Program Files (x86)',
    'C:\ProgramData',
    $env:USERPROFILE,
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming",
    "$env:USERPROFILE\AppData\LocalLow"
)
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $children = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        $m = Get-ChildItem -LiteralPath $child.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        $results += [pscustomobject]@{
            Root  = $root
            Name  = $child.Name
            Path  = $child.FullName
            GB    = [math]::Round($m.Sum / 1GB, 2)
            Files = $m.Count
        }
    }
}
$results | Sort-Object GB -Descending | Export-Csv $out -NoTypeInformation -Encoding UTF8
$results | Sort-Object GB -Descending | Select-Object -First 80 | Format-Table Root, Name, GB, Files -AutoSize
