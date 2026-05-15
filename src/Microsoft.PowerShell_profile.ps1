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

#region Auto Completion

# PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#endregion
