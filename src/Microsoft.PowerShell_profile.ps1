#region Check for Admin

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

#endregion

# $host.PrivateData.ErrorForegroundColor = 'green'

# Workaround for 1809 breaking opacity
# Set-ItemProperty -Path HKCU:\Console -Name WindowAlpha -Value 204

# Set-Location "$env:SystemDrive\"

#region PSReadLine Config

Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView

#endregion

# Fix for Windows Terminal Ctrl + Backspace removing only single character
if ($null -ne $env:WT_SESSION) {
    Set-PSReadLineKeyHandler -key Ctrl+h -Function BackwardKillWord
}

#$ErrorView = 'CategoryView'

#region Git Console Settings

if (Import-Module -Name posh-git, posh-sshell, Terminal-Icons -PassThru -ErrorAction SilentlyContinue) {
    function global:PromptWriteErrorInfo() {
        if ($global:GitPromptValues.DollarQuestion) { return }

        if ($global:GitPromptValues.LastExitCode) {
            "`e[31m(" + $global:GitPromptValues.LastExitCode + ") `e[0m"
        }
        else {
            "`e[31m! `e[0m"
        }
    }

    function prompt {
        $origDollarQuestion = $global:?
        $origLastExitCode = $global:LASTEXITCODE

        if (!$global:GitPromptValues) {
            $global:GitPromptValues = [PoshGitPromptValues]::new()
        }

        $global:GitPromptValues.DollarQuestion = $origDollarQuestion
        $global:GitPromptValues.LastExitCode = $origLastExitCode
        $global:GitPromptValues.IsAdmin = $isAdmin

        $prompt = Write-Prompt "[$((Get-Date).ToString('t'))]"

        try {

            $prevCommand = Get-History -Count 1 -ErrorAction Ignore

            if ($prevCommand) {
                $prevCommandTime = New-TimeSpan -Start $prevCommand.StartExecutionTime -End $prevCommand.EndExecutionTime
                $prompt += Write-Prompt "["
                switch ($prevCommandTime) {
                    {$_.TotalMinutes -ge 1} {
                        $prompt += Write-Prompt ('{0,5:f1}m' -f $_.TotalMinutes) -ForegroundColor Red
                    }
                    {$_.TotalMinutes -lt 1 -and $_.TotalSeconds -ge 1} {
                        $prompt += Write-Prompt ('{0,5:f1}s' -f $_.TotalSeconds) -ForegroundColor Yellow
                    }
                    default {
                        $prompt += Write-Prompt ('{0,4:f1}ms' -f $_.Milliseconds) -ForegroundColor Green
                    }
                }
                $prompt += Write-Prompt "] "
            } else {
                $prompt += Write-Prompt ' '
            }
        } catch {
            $prompt += Write-Prompt "[History Error] "
        }

        $prompt += global:PromptWriteErrorInfo

        try {
            if ("$($pwd.Drive):\" -eq "$($pwd.Path)") {
                $rootPath = $pwd.Drive.Root
                $prompt += Write-Prompt $pwd.ProviderPath
            } elseif ($pwd.Path -like '*FileSystem::\\*') {
                $rootPath = "\\$($pwd.ProviderPath.Split('\')[2..3] -join '\')"
                $prompt += Write-Prompt ".\$($pwd.ProviderPath.Split('\')[-1])"
            } else {
                $rootPath = $pwd.Drive.Root
                $prompt += Write-Prompt ".\$($pwd.ProviderPath.Split('\')[-1])"
            }
        } catch {
            $prompt += Write-Prompt "[Path Error]"
        }

        $prompt += Write-VcsStatus

        if ($isAdmin) {
            $host.UI.RawUI.WindowTitle = "[Admin] [$rootPath] [$((Get-Date).ToString('D'))]"
        } else {
            $host.UI.RawUI.WindowTitle = "[$rootPath] [$((Get-Date).ToString('D'))]"
        }

        $prompt += Write-Prompt "$(if ($PSDebugContext) { ' [DBG]:' } else { '' })" -ForegroundColor Magenta
        $prompt += Write-Prompt '> '

        #$global:GitPromptValues.LastPrompt = EscapeAnsiString $prompt

        $global:LASTEXITCODE = $origLastExitCode

        $prompt
    }
} else {
    Write-Warning 'Posh-Git, Posh-SSHell or Terminal-Icons is not installed'
}

if (! (Import-Module -Name DockerCompletion -PassThru -ErrorAction SilentlyContinue)) {
    Write-Warning 'DockerCompletion is not installed'
}

#endregion

function New-Tab { wt -w 0 nt -d . }

function New-SplitTab { wt -w 0 sp -H -d . }

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

#region Labor

function Get-GenAdmin() {
    [cmdletbinding()]
    [alias("gga")]
    param (
        [ValidateRange(0,7)][int]$Hours = 0,
        [ValidateRange(0,59)][int]$Minutes = 0,
        [switch]$IsRemaining
    )
    begin {
        $totalLabor;

        if ($hours -gt 0) {
            $totalLabor = $hours * 60
            $totalLabor += $minutes
        } else {
            $totalLabor = $minutes
        }

        if (!$IsRemaining) {
            $totalLabor = 480 - $totalLabor
        }

        Set-Clipboard -Value $totalLabor

        Write-Output "$totalLabor minutes"
    }
}

#endregion

#region .Net Discoverability Functions

function Get-Type {
    <#
            .SYNOPSIS
            Get exported types in the current session

            .DESCRIPTION
            Get exported types in the current session

            .PARAMETER Module
            Filter on Module.  Accepts wildcard

            .PARAMETER Assembly
            Filter on Assembly.  Accepts wildcard

            .PARAMETER FullName
            Filter on FullName.  Accepts wildcard

            .PARAMETER Namespace
            Filter on Namespace.  Accepts wildcard

            .PARAMETER BaseType
            Filter on BaseType.  Accepts wildcard

            .PARAMETER IsEnum
            Filter on IsEnum.

            .EXAMPLE
            #List the full name of all Enums in the current session
            Get-Type -IsEnum $true | Select -ExpandProperty FullName | Sort -Unique

            .EXAMPLE
            #Connect to a web service and list all the exported types

            #Connect to the web service, give it a namespace we can search on
            $weather = New-WebServiceProxy -uri "http://www.webservicex.net/globalweather.asmx?wsdl" -Namespace GlobalWeather

            #Search for the namespace
            Get-Type -NameSpace GlobalWeather

            IsPublic IsSerial Name                                     BaseType
            -------- -------- ----                                     --------
            True     False    MyClass1ex_net_globalweather_asmx_wsdl   System.Object
            True     False    GlobalWeather                            System.Web.Services.Protocols.SoapHttpClientProtocol
            True     True     GetWeatherCompletedEventHandler          System.MulticastDelegate
            True     False    GetWeatherCompletedEventArgs             System.ComponentModel.AsyncCompletedEventArgs
            True     True     GetCitiesByCountryCompletedEventHandler  System.MulticastDelegate
            True     False    GetCitiesByCountryCompletedEventArgs     System.ComponentModel.AsyncCompletedEventArgs

            .EXAMPLE
            #List the arguments for a .NET type
            (Get-Type -FullName *PSCredential).GetConstructors()[0].GetPerameters()

            .FUNCTIONALITY
            Computers
    #>
    [cmdletbinding()]
    param(
        [string]$Module = '*',
        [string]$Assembly = '*',
        [string]$FullName = '*',
        [string]$Namespace = '*',
        [string]$BaseType = '*',
        [switch]$IsEnum
    )

    #Build up the Where statement
        $WhereArray = @('$_.IsPublic')
        if($Module -ne '*'){$WhereArray += '$_.Module -like $Module'}
        if($Assembly -ne '*'){$WhereArray += '$_.Assembly -like $Assembly'}
        if($FullName -ne '*'){$WhereArray += '$_.FullName -like $FullName'}
        if($Namespace -ne '*'){$WhereArray += '$_.Namespace -like $Namespace'}
        if($BaseType -ne '*'){$WhereArray += '$_.BaseType -like $BaseType'}
        #This clause is only evoked if IsEnum is passed in
        if($PSBoundParameters.ContainsKey('IsEnum')) { $WhereArray += '$_.IsENum -like $IsENum' }

    #Give verbose output, convert where string to scriptblock
        $WhereString = $WhereArray -Join ' -and '
        $WhereBlock = [scriptblock]::Create( $WhereString )
        Write-Verbose "Where ScriptBlock: { $WhereString }"

    #Invoke the search!
        [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
            Write-Verbose "Getting types from $($_.FullName)"
            Try
            {
                $_.GetExportedTypes()
            }
            Catch
            {
                Write-Verbose "$($_.FullName) error getting Exported Types: $_"
                $null
            }

        } | Where-Object -FilterScript $WhereBlock
}

function Get-Constructor {
    <#
        .SYNOPSIS
            Displays the available constructor parameters for a given type

        .DESCRIPTION
            Displays the available constructor parameters for a given type

        .PARAMETER Type
            The type name to list out available contructors and parameters

        .PARAMETER AsObject
            Output the results as an object instead of a formatted table

        .EXAMPLE
            Get-Constructor -Type "adsi"

            DirectoryEntry Constructors
            ---------------------------

            System.String path
            System.String path, System.String username, System.String password
            System.String path, System.String username, System.String password, System.DirectoryServices.AuthenticationTypes aut...
            System.Object adsObject

            Description
            -----------
            Displays the output of the adsi contructors as a formatted table

        .EXAMPLE
            "adsisearcher" | Get-Constructor

            DirectorySearcher Constructors
            ------------------------------

            System.DirectoryServices.DirectoryEntry searchRoot
            System.DirectoryServices.DirectoryEntry searchRoot, System.String filter
            System.DirectoryServices.DirectoryEntry searchRoot, System.String filter, System.String[] propertiesToLoad
            System.String filter
            System.String filter, System.String[] propertiesToLoad
            System.String filter, System.String[] propertiesToLoad, System.DirectoryServices.SearchScope scope
            System.DirectoryServices.DirectoryEntry searchRoot, System.String filter, System.String[] propertiesToLoad, System.D...

            Description
            -----------
            Takes input from pipeline and displays the output of the adsi contructors as a formatted table

        .EXAMPLE
            "adsisearcher" | Get-Constructor -AsObject

            Type                                                        Parameters
            ----                                                        ----------
            System.DirectoryServices.DirectorySearcher                  {}
            System.DirectoryServices.DirectorySearcher                  {searchRoot}
            System.DirectoryServices.DirectorySearcher                  {searchRoot, filter}
            System.DirectoryServices.DirectorySearcher                  {searchRoot, filter, propertiesToLoad}
            System.DirectoryServices.DirectorySearcher                  {filter}
            System.DirectoryServices.DirectorySearcher                  {filter, propertiesToLoad}
            System.DirectoryServices.DirectorySearcher                  {filter, propertiesToLoad, scope}
            System.DirectoryServices.DirectorySearcher                  {searchRoot, filter, propertiesToLoad, scope}

            Description
            -----------
            Takes input from pipeline and displays the output of the adsi contructors as an object

        .INPUTS
            System.Type

        .OUTPUTS
            System.Constructor
            System.String

        .NOTES
            Author: Boe Prox
            Date Created: 28 Jan 2013
            Version 1.0
    #>
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True)]
        [Type]$Type,
        [parameter()]
        [switch]$AsObject
    )
    Process {
        If ($PSBoundParameters['AsObject']) {
            $type.GetConstructors() | ForEach {
                $object = New-Object PSobject -Property @{
                    Type = $_.DeclaringType
                    Parameters = $_.GetParameters()
                }
                $object.pstypenames.insert(0,'System.Constructor')
                Write-Output $Object
            }


        } Else {
            $Type.GetConstructors() | Select-Object @{
		        Label="$($type.Name) Constructors"
		        Expression={($_.GetParameters() | ForEach {$_.ToString()}) -Join ', '}
	        }
        }
    }
}

#endregion
