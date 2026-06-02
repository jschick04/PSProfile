#region Check for Admin

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

#endregion

#region PSReadLine Config

Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView

# Fix for Windows Terminal Ctrl + Backspace removing only single character
if ($null -ne $env:WT_SESSION) { Set-PSReadLineKeyHandler -key Ctrl+h -Function BackwardKillWord }

#endregion

#region Git Console Settings

if (!(Import-Module -Name Terminal-Icons -PassThru -ErrorAction SilentlyContinue)) {
    Write-Warning 'Terminal-Icons is not installed'
}

if (Import-Module -Name posh-git -PassThru -ErrorAction SilentlyContinue) {
    function PromptWriteErrorInfo([System.Text.StringBuilder]$StringBuilder) {
        if ($global:GitPromptValues.DollarQuestion) {
            return Write-Prompt ' ' -StringBuilder $StringBuilder
        }

        $code = $global:GitPromptValues.LastExitCode
        $text = $code ? (' 0x{0:X} ' -f $code) : ' ! '
        Write-Prompt $text -ForegroundColor $host.PrivateData.ErrorForegroundColor -StringBuilder $StringBuilder
    }

    function PromptWriteHistoryInfo([Microsoft.PowerShell.Commands.HistoryInfo]$PrevCommand, [System.Text.StringBuilder]$StringBuilder) {
        $time = $PrevCommand.EndExecutionTime - $PrevCommand.StartExecutionTime

        if ($time.TotalMinutes -ge 1) {
            Write-Prompt ('{0,5:f1}m' -f $time.TotalMinutes) -ForegroundColor $host.PrivateData.ErrorForegroundColor -StringBuilder $StringBuilder
        } elseif ($time.TotalSeconds -ge 1) {
            Write-Prompt ('{0,5:f1}s' -f $time.TotalSeconds) -ForegroundColor $host.PrivateData.WarningForegroundColor -StringBuilder $StringBuilder
        } else {
            Write-Prompt ('{0,4:f1}ms' -f $time.TotalMilliseconds) -ForegroundColor $host.PrivateData.FormatAccentColor -StringBuilder $StringBuilder
        }
    }

    function prompt {
        $dollarQuestion = $global:?
        $lastExit = $global:LASTEXITCODE

        if (!$global:GitPromptValues) { $global:GitPromptValues = [PoshGitPromptValues]::new() }

        $global:GitPromptValues.DollarQuestion = $dollarQuestion
        $global:GitPromptValues.LastExitCode = $lastExit
        $global:GitPromptValues.IsAdmin = $isAdmin

        $now = Get-Date
        $sb = [System.Text.StringBuilder]::new(256)

        Write-Prompt ('[{0}]' -f $now.ToString('t')) -StringBuilder $sb | Out-Null

        $prevCommand = Get-History -Count 1 -ErrorAction Ignore
        if ($prevCommand) {
            Write-Prompt '[' -StringBuilder $sb | Out-Null
            PromptWriteHistoryInfo $prevCommand $sb | Out-Null
            Write-Prompt ']' -StringBuilder $sb | Out-Null
        }

        PromptWriteErrorInfo $sb | Out-Null

        $rootPath = $null
        try {
            $providerPath = $pwd.ProviderPath
            if ($providerPath.StartsWith('\\')) {
                $segments = $providerPath.Split('\', [StringSplitOptions]::RemoveEmptyEntries)
                $rootPath = '\\' + ($segments[0..1] -join '\')
                $leaf = $segments[-1]
                Write-Prompt (".\$leaf") -StringBuilder $sb | Out-Null
            } elseif ($pwd.Drive -and $providerPath -eq $pwd.Drive.Root) {
                $rootPath = $pwd.Drive.Root
                Write-Prompt $providerPath -StringBuilder $sb | Out-Null
            } else {
                $rootPath = if ($pwd.Drive) { $pwd.Drive.Root } else { $providerPath }
                $leaf = [System.IO.Path]::GetFileName($providerPath)
                Write-Prompt (".\$leaf") -StringBuilder $sb | Out-Null
            }
        } catch {
            $rootPath = $pwd.Path
            Write-Prompt '[Path Error]' -StringBuilder $sb | Out-Null
        }

        $sb.Append((Write-VcsStatus)) | Out-Null

        if ($PSDebugContext) { Write-Prompt ' [DBG]' -ForegroundColor Magenta -StringBuilder $sb | Out-Null }

        Write-Prompt '> ' -StringBuilder $sb | Out-Null

        $today = $now.ToString('D')
        $host.UI.RawUI.WindowTitle = $isAdmin ?
            "[Admin] [$rootPath] [$today]" :
            "[$rootPath] [$today]"

        $sb.ToString()
    }
} else {
    Write-Warning 'Posh-Git is not installed'
}

#endregion

#region Terminal Shortcuts

function New-Tab { wt -w 0 nt -d . }

function New-SplitTab { wt -w 0 sp -H -d . }

#endregion

#region Recommended Module

function Get-RecommendedModules {
    [cmdletbinding(DefaultParameterSetName = "Install")]
    param(
        [Parameter(ParameterSetName = "Install")][switch]$IsInstalled,
        [Parameter(ParameterSetName = "Update")][switch]$IsUpdateAvailable
    )
    begin {
        $appList = @("DockerCompletion", "dbatools", "posh-git", "posh-sshell", "Terminal-Icons", "PSScriptAnalyzer")

        foreach ($app in $appList) {
            if ($IsInstalled -or $IsUpdateAvailable) {
                $installedApp = Get-InstalledModule -Name $app -ErrorAction Ignore

                if ([string]::IsNullOrEmpty($installedApp)) {
                    Write-Warning "$app is not installed"
                } elseif ($IsUpdateAvailable) {
                    $update = Find-Module -Name $app
                    if ($update.Version -gt $installedApp.Version) {
                        Write-Output "Update is available for $app - $($installedApp.Version) -> $($update.Version)"
                    } else {
                        Write-Output "No update available for $app"
                    }
                } else {
                    Write-Output "$app is installed"
                }
            } else {
                Write-Output $app
            }
        }
    }
}

#endregion

#region Copilot CLI

function autopilot {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'FullCompact', Mandatory = $true)]
        [switch]$Full,

        [Parameter(ParameterSetName = 'Compact', Mandatory = $true)]
        [Parameter(ParameterSetName = 'FullCompact', Mandatory = $true)]
        [switch]$Compact,

        # Optional session ID / name / 7+ char ID prefix to resume; defaults to most recent.
        # Named-only (no positional) to avoid binding-time collision with passthrough args
        # like --model that PowerShell would otherwise try to bind to Position 0.
        [Parameter(ParameterSetName = 'Compact')]
        [Parameter(ParameterSetName = 'FullCompact')]
        [string]$SessionId,

        # Captures any extra args (e.g. --model, --plan) and forwards them to copilot.
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Remaining
    )

    # [string[]] cast prevents PowerShell from auto-unwrapping a single-element array to a
    # scalar string (which would then splat character-by-character on call).
    [string[]] $permFlags = if ($Full) {
        @('--allow-all')
    } else {
        @('--allow-all-paths', '--allow-all-urls', '--allow-tool', 'write')
    }

    if ($Compact) {
        # Path-agnostic: the agent re-discovers its own nested-AGENTS.md / custom-instruction
        # files from the system-prompt block, so this works on any machine and any repo.
        $compactPrompt = '/compact On resume, the FIRST tool call MUST be to re-read every AGENTS.md / custom-instruction file listed in this session''s nested-instructions block (especially §0 Git Safety Gates incl. PRE-GIT SENTINEL, §1 phase router, and pre-commit.md disciplines). Preserve in the summary: no `git add .` / -A / --all, no Co-authored-by trailer, single-line commit messages, and that the PR-quality-gate ack block does NOT satisfy §0 user-approval gates.'

        [string[]] $resume = if ($SessionId) { @('--resume', $SessionId) } else { @('--continue') }

        # Permission flags ARE re-applied on resume: copilot --continue / --resume do NOT
        # inherit the prior session's --allow-* state, so -Full must be re-specified
        # alongside -Compact to keep elevated permissions on the resumed session.
        copilot @resume @permFlags -i $compactPrompt @Remaining
        return
    }

    copilot @permFlags @Remaining
}

#endregion

#region Auto Completion

# PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#endregion
