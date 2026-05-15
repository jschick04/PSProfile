# PSProfile

A PowerShell 7+ profile with a fast posh-git prompt and a Copilot CLI statusline that mirrors the prompt's bracket aesthetic.

## What's included

- **`src/Microsoft.PowerShell_profile.ps1`** - the profile script. Provides:
  - Admin detection (`$isAdmin`)
  - PSReadLine config (history search, prediction, Ctrl+Backspace fix in Windows Terminal)
  - Custom posh-git prompt: `[time][duration]<error/space><short-path><git-status>>` with admin/path/date in window title
  - `New-Tab` / `New-SplitTab` Windows Terminal helpers
  - `Get-RecommendedModules` to list/check installed modules
  - `dotnet` argument completion shim
- **`src/copilot/statusline.cmd`** + **`src/copilot/statusline.ps1`** - GitHub Copilot CLI statusline renderer. Reads the JSON Copilot sends on stdin and prints `[cwd] [git: branch] [ctx N/N] [gauge] [duration] [+/-lines]` (ANSI-colored, no Oh My Posh required).
- **`src/copilot/settings.example.json`** - reference for what `install.ps1` merges into `%USERPROFILE%\.copilot\settings.json`.
- **`install.ps1`** - one-shot installer for a fresh OS install. See below.

## Quick install (fresh OS)

```powershell
# from an elevated or normal PS7 prompt
git clone https://github.com/jschick04/PSProfile "$env:USERPROFILE\PSProfile"
cd "$env:USERPROFILE\PSProfile"
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` is idempotent (safe to re-run) and supports:

- `-Profile` only (skip Copilot statusline)
- `-Copilot` only (skip profile)
- `-InstallModules` (also install posh-git, Terminal-Icons, etc. - **off by default**)
- `-Force` (overwrite existing profile / statusline files without prompting)

By default it copies the profile to `$PROFILE.CurrentUserCurrentHost` and sets up the Copilot CLI statusline. Pass `-InstallModules` to also install the recommended PowerShell modules in `CurrentUser` scope.

After install: open a new pwsh window, and run `/restart` inside Copilot CLI if it's already open.

## Requirements

- Windows 10 / 11
- PowerShell 7 (`pwsh`)
- Git
- Optional: Windows Terminal (for `New-Tab` / `New-SplitTab` and ANSI colors)
- Optional: GitHub Copilot CLI (for the statusline)

## Manual install

If you'd rather not run the installer:

```powershell
Copy-Item .\src\Microsoft.PowerShell_profile.ps1 $PROFILE
Copy-Item .\src\copilot\* $env:USERPROFILE\.copilot\
# then merge src\copilot\settings.example.json into %USERPROFILE%\.copilot\settings.json
```
