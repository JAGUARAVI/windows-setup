# start komorebi + whkd + masir (hover focus) at logon, hidden
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$config = Join-Path $env:USERPROFILE '.config\komorebi\komorebi.json'
Start-Process -FilePath 'C:\Program Files\komorebi\bin\komorebic.exe' `
    -ArgumentList @('start', '--config', $config, '--whkd', '--masir') `
    -WindowStyle Hidden
