param([string]$Action)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MediaKey {
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
$vks = @{ next = 0xB0; prev = 0xB1; play = 0xB3; mute = 0xAD }
$vk = $vks[$Action]
if ($null -ne $vk) {
    [MediaKey]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
    [MediaKey]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
}
