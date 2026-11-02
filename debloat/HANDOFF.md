# Windows 11 debloat — handoff

This is the generic handoff for the debloat scripts in this folder. The
original machine-specific report was removed for privacy. The scripts are the
source of truth for the exact package, service, task, and registry lists; this
document explains the shape of the pass and how to run it safely.

## Scope

- Recent Windows 11 builds (24H2/25H2 family), Home or Pro.
- Administrator PowerShell for the system changes.
- Optional: the debloat is independent of the desktop rice. The rice works
  without it, and the debloat can be applied later.

## Process

1. Audit the current state (OS, apps, services, tasks, startup, drivers).
2. Back up registry keys, app lists, services, tasks, and startup state.
3. Clean safe, regenerable caches.
4. Remove Copilot and selected consumer/inbox Appx packages.
5. Disable telemetry and error-reporting services and scheduled tasks.
6. Apply privacy, advertising, search, Office, Edge, and AI/Recall policies.
7. Optionally disable startup entries (user-selected names).
8. Fix a Task Manager policy if it is present.
9. Verify and write a final state snapshot.

## Scripts

| Script | Purpose |
| --- | --- |
| `00-recon.ps1` | Read-only audit: OS, hardware, apps, services, tasks, startup, drivers |
| `01-sizes.ps1` | Top-level disk usage summary |
| `02-cleanup.ps1` | Safe cache/temp/log cleanup and Recycle Bin |
| `02b-subfolders.ps1` | Per-folder size analysis |
| `03-backup.ps1` | Registry/app/service/task/startup backups |
| `04-debloat.ps1` | Copilot, Appx, telemetry services/tasks, startup cleanup |
| `05-updates.ps1` | Windows Update experiment (not required) |
| `05c-updates-onebyone.ps1` | Per-update download/install experiment |
| `05d-updates-reset-retry.ps1` | Windows Update cache reset and retry |
| `06-verify.ps1` | Verification report |
| `07-rollback.ps1` | Restore backed-up registry/services/tasks/startup |
| `08-privacy-extra.ps1` | Extra privacy/advertising/search policies |
| `10-ai-safe-tweaks.ps1` | AI service state and Recall/Copilot/Paint policies |
| `11-final-state.ps1` | Current-state snapshot |

The GPU driver helper from the original workspace is intentionally not
included; install GPU drivers through the vendor tooling or Windows Update.

## Recommended run

```powershell
cd debloat
.\03-backup.ps1
.\04-debloat.ps1
.\08-privacy-extra.ps1
.\10-ai-safe-tweaks.ps1
.\06-verify.ps1
```

`install.ps1 -Debloat` runs 04, 08, 10, and 06. It does **not** run the backup
or disk-cleanup steps. Scripts write logs/backups to
`C:\Users\Public\debloat` by default; create it or edit the paths.

## Technical changes

### Services disabled

- `DiagTrack` — Connected User Experiences and Telemetry
- `dmwappushservice` — Device Management WAP Push
- `WerSvc` — Windows Error Reporting
- `InventorySvc` — Inventory and Compatibility Appraisal
- `MapsBroker` — Downloaded Maps Manager
- `RetailDemo` — Retail Demo
- `RemoteRegistry` — Remote Registry
- `Fax` — if present

Kept: `WSearch`, `SysMain`, `Spooler`, `WpnService`, `DoSvc`, `BITS`, Xbox
services, security services, and vendor services needed by the hardware.

### Scheduled tasks disabled

- Application Experience — Microsoft Compatibility Appraiser
- Feedback / Siuf — `DmClient`, `DmClientOnScenarioDownload`
- Windows Error Reporting — QueueReporting
- Customer Experience Improvement Program — Consolidator, UsbCeip
- Disk Diagnostic — Microsoft-Windows-DiskDiagnosticDataCollector

The verification script confirms that the targeted telemetry tasks are not
enabled.

### Privacy and policy changes

The scripts apply policies for:

- Diagnostic data / telemetry off, limited diagnostic logs and dumps.
- No feedback prompts, no advertising ID, no tailored experiences.
- No Windows consumer features, Spotlight suggestions, or cloud content.
- No web/Bing search or Cortana; local search remains.
- Office client telemetry disabled.
- Edge sidebar, Copilot, shopping/rewards, background mode, and telemetry off.
- Input/speech personalization restricted.
- Delivery Optimization and device metadata limited.

The exact keys and values live in `08-privacy-extra.ps1` and
`10-ai-safe-tweaks.ps1`.

### Appx / consumer apps

`04-debloat.ps1` removes Copilot and a selected set of inbox/consumer
packages. The list is intentionally explicit in the script so it can be
reviewed and edited. Store, Terminal, Notepad, Paint, Calculator, Photos,
Camera, Snipping Tool, Media Player, and other core apps are kept.

### Startup

Startup cleanup is now **opt-in**: `04-debloat.ps1` has an empty
`$userStartup` array. Add the process/entry names you want to disable. This
keeps the public script from carrying someone else's app list.

### AI / Recall

- `WSAIFabricSvc` (Windows AI Components Host) set to Manual and stopped.
- Windows AI policies for Recall, Click to Do, and data analysis.
- Paint Cocreator, Generative Fill, and Image Creator disabled.

Feature updates may reset these values; recheck after major updates.

### Task Manager

If `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System\DisableTaskMgr`
is set, it is removed so Task Manager opens normally.

### Disk cleanup

`02-cleanup.ps1` only touches regenerable data:

- Windows Update download cache, Windows Temp, user Temp.
- Delivery Optimization cache.
- GPU shader caches.
- Old Windows/CBS logs, crash dumps, Recycle Bin.
- Opt-in browser/app caches; edit the list to match your apps.

### Updates and drivers

`05*` are reference scripts from the update work. They reset the Windows
Update cache and can install updates one by one. They are not run by
`install.ps1 -Debloat`.

BIOS/firmware updates should be installed manually with AC power. Hiding an
offered BIOS update prevents an automatic flash; it does not install one.

## What it leaves alone

- Game clients, anti-cheat, and game libraries.
- WSL and personal files.
- Windows Search, SysMain, Spooler, BITS, and Xbox/Gaming services.
- Defender/security services and vendor services needed by the hardware.
- Store, Terminal, core inbox apps, browser/WebView2, Office, and dev tools.

## Safety and rollback

- **No System Restore point was available on the original setup.** Create a
  restore point or VM snapshot before running.
- `03-backup.ps1` exports registry keys, app lists, services, tasks, and
  startup state. It is not a full disk backup.
- Review paths and app lists in `02b` and `04` before running on a different
  machine. Some comments still describe the original setup.
- Rollback: `07-rollback.ps1` restores the backed-up state. Re-enable the AI
  service with:
  ```powershell
  Set-Service WSAIFabricSvc -StartupType Automatic
  Start-Service WSAIFabricSvc
  ```
- Do not stack other debloat tools on top; they can conflict.

## Verification

`06-verify.ps1` checks:

- Targeted services are stopped/disabled.
- Targeted telemetry tasks are not enabled.
- Removed Appx packages are absent.
- Task Manager opens and the policy is absent.
- AI/privacy policy values are present.
- No pending reboot is reported.

`11-final-state.ps1` writes the current snapshot next to the script.

## Notes

- Some changes may be reverted by Windows feature updates; recheck AI
  services, Recall/Copilot policies, widgets, and taskbar settings after a
  major update.
- The scripts are conservative around security, search, audio, and vendor
  services. Review any additions before adding them.
- The debloat can free several GB depending on caches and installed apps;
  treat that as a range, not a guarantee.
