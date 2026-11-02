# tools

## PS-SFTA

`SFTA.ps1` is [PS-SFTA](https://github.com/DanysysTeam/PS-SFTA) by Danysys,
licensed under the MIT license. It can set file and protocol associations
with `Set-FTA` / `Set-PTA`.

It is **not used automatically** on Windows 11 24H2+ because the **UCPD**
(User Choice Protection Driver) blocks writes to the `UserChoice` keys. The
native Settings UI is the supported path there:

```powershell
.\scripts\set-default-browser.ps1
```

That script opens the Zen Browser page in Settings; click **Set default**.
PS-SFTA remains useful on older builds where UCPD is not present.

MIT license: https://github.com/DanysysTeam/PS-SFTA/blob/master/LICENSE
