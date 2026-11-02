# Send F11 to the focused window (true app fullscreen)
Add-Type -AssemblyName System.Windows.Forms
Start-Sleep -Milliseconds 220
[System.Windows.Forms.SendKeys]::SendWait('{F11}')
