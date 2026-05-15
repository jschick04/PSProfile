# Installs the PSProfile profile script and (optionally) the Copilot CLI statusline.
#
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#
# Switches:
#   -ProfileOnly      Only install the profile (skip Copilot statusline + settings).
#   -CopilotOnly      Only install the Copilot statusline (skip profile + modules).
#   -InstallModules   Also install the recommended PowerShell modules
#                     (posh-git, Terminal-Icons, PSScriptAnalyzer, DockerCompletion,
#                     posh-sshell, dbatools). Off by default.
#   -Force            Overwrite existing profile / statusline files without prompting.
#   -InstallScope     'CurrentUser' (default) or 'AllUsers' for module installation.
#
# Idempotent: safe to re-run.

[CmdletBinding()]
param(
    [switch]$ProfileOnly,
    [switch]$CopilotOnly,
    [switch]$InstallModules,
    [switch]$Force,
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$InstallScope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required (current: $($PSVersionTable.PSVersion)). Install from https://aka.ms/pwsh and re-run with pwsh."
}

if ($ProfileOnly -and $CopilotOnly) {
    throw "-ProfileOnly and -CopilotOnly are mutually exclusive."
}

$repoRoot = Split-Path -Parent $PSCommandPath
$srcDir   = Join-Path $repoRoot 'src'
$profileSrc  = Join-Path $srcDir 'Microsoft.PowerShell_profile.ps1'
$copilotSrc  = Join-Path $srcDir 'copilot'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message){ Write-Host "    $Message" -ForegroundColor Yellow }

function Confirm-Overwrite([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    if ($Force) { return $true }
    $ans = Read-Host "    Overwrite '$Path'? [y/N]"
    return $ans -match '^(y|Y)'
}

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        $bak = "$Path.bak-$stamp"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
        Write-Ok "Backed up to: $bak"
    }
}

function Install-RecommendedModules {
    Write-Step 'Installing recommended modules'
    $modules = @('posh-git', 'Terminal-Icons', 'PSScriptAnalyzer', 'DockerCompletion', 'posh-sshell', 'dbatools')
    foreach ($m in $modules) {
        $installed = Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($installed) {
            Write-Ok "$m already installed (v$($installed.Version))"
            continue
        }
        try {
            Write-Host "    Installing $m ..." -NoNewline
            Install-Module -Name $m -Scope $InstallScope -Force -AcceptLicense -AllowClobber -ErrorAction Stop
            Write-Host " done" -ForegroundColor Green
        } catch {
            Write-Host ''
            Write-Warn2 "Failed to install $m : $($_.Exception.Message)"
        }
    }
}

function Install-Profile {
    Write-Step 'Installing PowerShell profile'

    if (-not (Test-Path -LiteralPath $profileSrc)) {
        throw "Profile source not found: $profileSrc"
    }

    $target = $PROFILE.CurrentUserCurrentHost
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Ok "Created profile directory: $targetDir"
    }

    if (Test-Path -LiteralPath $target) {
        $existingHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        $newHash = (Get-FileHash -LiteralPath $profileSrc -Algorithm SHA256).Hash
        if ($existingHash -eq $newHash) {
            Write-Ok "Profile already up to date: $target"
            return
        }
        if (-not (Confirm-Overwrite $target)) {
            Write-Warn2 "Skipped profile (declined overwrite): $target"
            return
        }
        Backup-File $target
    }

    Copy-Item -LiteralPath $profileSrc -Destination $target -Force
    Write-Ok "Profile installed: $target"
}

function Install-CopilotStatusLine {
    Write-Step 'Installing Copilot CLI statusline'

    if (-not (Test-Path -LiteralPath $copilotSrc)) {
        throw "Copilot source dir not found: $copilotSrc"
    }

    $copilotDir = Join-Path $env:USERPROFILE '.copilot'
    if (-not (Test-Path -LiteralPath $copilotDir)) {
        New-Item -ItemType Directory -Path $copilotDir -Force | Out-Null
        Write-Ok "Created: $copilotDir"
    }

    foreach ($name in @('statusline.cmd', 'statusline.ps1')) {
        $from = Join-Path $copilotSrc $name
        $to   = Join-Path $copilotDir $name
        if (-not (Test-Path -LiteralPath $from)) {
            Write-Warn2 "Source missing, skipping: $from"
            continue
        }
        if (Test-Path -LiteralPath $to) {
            $hOld = (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash
            $hNew = (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
            if ($hOld -eq $hNew) {
                Write-Ok "$name already up to date"
                continue
            }
            if (-not (Confirm-Overwrite $to)) {
                Write-Warn2 "Skipped $name (declined overwrite)"
                continue
            }
            Backup-File $to
        }
        Copy-Item -LiteralPath $from -Destination $to -Force
        Write-Ok "Installed: $to"
    }

    Merge-CopilotSettings -CopilotDir $copilotDir
}

function Merge-CopilotSettings {
    param([Parameter(Mandatory)][string]$CopilotDir)

    $settingsPath = Join-Path $CopilotDir 'settings.json'
    $statusCmd    = Join-Path $CopilotDir 'statusline.cmd'

    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $raw = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $settings = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            }
        } catch {
            Write-Warn2 "settings.json is invalid JSON; backing up and starting fresh."
            Backup-File $settingsPath
        }
    }
    if (-not $settings) { $settings = @{} }

    Backup-File $settingsPath

    $settings['statusLine'] = @{
        type    = 'command'
        command = $statusCmd
        padding = 1
    }
    if (-not $settings.ContainsKey('feature_flags'))             { $settings['feature_flags'] = @{} }
    if (-not $settings['feature_flags'].ContainsKey('enabled'))  { $settings['feature_flags']['enabled'] = @() }

    $enabled = @($settings['feature_flags']['enabled'])
    if ($enabled -notcontains 'STATUS_LINE') { $enabled += 'STATUS_LINE' }
    $settings['feature_flags']['enabled'] = $enabled

    if (-not $settings.ContainsKey('experimental')) { $settings['experimental'] = $true }

    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "Updated: $settingsPath"
}

# --- main ---
Write-Host "PSProfile installer" -ForegroundColor Magenta
Write-Host "Repo:    $repoRoot"
Write-Host "Scope:   $InstallScope"
Write-Host ''

if (-not $CopilotOnly) {
    if ($InstallModules) { Install-RecommendedModules }
    Install-Profile
}

if (-not $ProfileOnly) {
    Install-CopilotStatusLine
}

Write-Host ''
Write-Host "Done. Open a new pwsh window to use the new profile." -ForegroundColor Green
if (-not $ProfileOnly) {
    Write-Host "If GitHub Copilot CLI is already running, run /restart inside it." -ForegroundColor Green
}
