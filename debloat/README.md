# Debloat scripts

These are the scripts from the original debloat workspace, copied into this
repo for reference and reuse. `HANDOFF.md` is the generic handoff: audit,
changes, verification, backups, and rollback.

**Read `HANDOFF.md` before running anything.** The debloat is destructive:
it removes consumer apps, disables telemetry services/tasks, and applies
privacy and AI policies. No System Restore point was available on the original
setup; make your own backup first.

## Suggested order

```powershell
.\03-backup.ps1
.\04-debloat.ps1
.\08-privacy-extra.ps1
.\10-ai-safe-tweaks.ps1
.\06-verify.ps1
```

`install.ps1 -Debloat` runs 04, 08, 10, and 06 (it does **not** run the
backup step). Run `03-backup.ps1` first if you want the full sequence.

## Notes

- Logs default to `C:\Users\Public\debloat` (`debloat.log`,
  `privacy-extra.log`, `ai-safe-tweaks.log`). Create that folder or edit the
  paths in the scripts.
- Some scripts still contain paths/comments from the original setup; review
  before running on another machine.
- Rollback: `.\07-rollback.ps1`.
- Do not stack other debloat tools on top of these changes; they conflict.
