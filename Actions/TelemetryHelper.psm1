. (Join-Path -Path $PSScriptRoot -ChildPath ".\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '.\Github-Helper.psm1' -Resolve)

#region Loading telemetry helper
function DownloadNugetPackage($PackageName, $PackageVersion) {
    $nugetPackagePath = Join-Path "$ENV:GITHUB_WORKSPACE" "/.nuget/packages/$PackageName/$PackageVersion/"

    if (-not (Test-Path -Path $nugetPackagePath)) {
        $url = "https://www.nuget.org/api/v2/package/$PackageName/$PackageVersion"

        Write-Host "Downloading Nuget package $PackageName $PackageVersion..."
        New-Item -ItemType Directory -Path $nugetPackagePath | Out-Null
        Invoke-WebRequest -Uri $Url -OutFile "$nugetPackagePath/$PackageName.$PackageVersion.zip"

        # Unzip the package
        Expand-Archive -Path "$nugetPackagePath/$PackageName.$PackageVersion.zip" -DestinationPath "$nugetPackagePath"

        # Remove the zip file
        Remove-Item -Path "$nugetPackagePath/$PackageName.$PackageVersion.zip"
    }

    return $nugetPackagePath
}

function LoadApplicationInsightsDll() {
    $packagePath = DownloadNugetPackage -PackageName "Microsoft.ApplicationInsights" -PackageVersion (GetPackageVersion -PackageName "Microsoft.ApplicationInsights")
    $AppInsightsDllPath = "$packagePath/lib/net46/Microsoft.ApplicationInsights.dll"

    if (-not (Test-Path -Path $AppInsightsDllPath)) {
        throw "Failed to download Application Insights DLL"
    }

    [Reflection.Assembly]::LoadFile($AppInsightsDllPath) | Out-Null
}

function Get-ApplicationInsightsTelemetryClient($TelemetryConnectionString)
{
    # Load the Application Insights DLL
    LoadApplicationInsightsDll

    $TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
    $TelemetryClient.TelemetryConfiguration.ConnectionString = $TelemetryConnectionString

    return $TelemetryClient
}
#endregion

function AddTelemetryEvent()
{
    param(
        [Parameter(Mandatory = $true)]
        [String] $Message,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $Data = @{},
        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Error")]
        [String] $Severity = 'Information'
    )

    try {
        # Add powershell version
        Add-TelemetryProperty -Hashtable $Data -Key 'PowerShellVersion' -Value ($PSVersionTable.PSVersion.ToString())

        $module = Get-Module BcContainerHelper
        if ($module) {
            $versionNoFile = Join-Path -Path (Split-Path $module.Path -Parent) -ChildPath 'Version.txt'
            Add-TelemetryProperty -Hashtable $Data -Key 'BcContainerHelperVersion' -Value (Get-Content -Path $versionNoFile -Encoding UTF8)
        }

        Add-TelemetryProperty -Hashtable $Data -Key 'WorkflowName' -Value $ENV:GITHUB_WORKFLOW
        Add-TelemetryProperty -Hashtable $Data -Key 'RunnerOs' -Value $ENV:RUNNER_OS
        Add-TelemetryProperty -Hashtable $Data -Key 'RunId' -Value $ENV:GITHUB_RUN_ID
        Add-TelemetryProperty -Hashtable $Data -Key 'RunNumber' -Value $ENV:GITHUB_RUN_NUMBER
        Add-TelemetryProperty -Hashtable $Data -Key 'RunAttempt' -Value $ENV:GITHUB_RUN_ATTEMPT

        ### Add GitHub Repository information
        Add-TelemetryProperty -Hashtable $Data -Key 'Repository' -Value $ENV:GITHUB_REPOSITORY_ID

        $repoSettings = ReadSettings
        if ($repoSettings.microsoftTelemetryConnectionString -ne '') {
            Write-Host "Enabling Microsoft telemetry..."
            $MicrosoftTelemetryClient = Get-ApplicationInsightsTelemetryClient -TelemetryConnectionString $repoSettings.microsoftTelemetryConnectionString
            $MicrosoftTelemetryClient.TrackTrace($Message, [Microsoft.ApplicationInsights.DataContracts.SeverityLevel]::$Severity, $Data)
            $MicrosoftTelemetryClient.Flush()
        }

        if ($repoSettings.partnerTelemetryConnectionString -ne '') {
            Write-Host "Enabling partner telemetry..."
            $PartnerTelemetryClient = Get-ApplicationInsightsTelemetryClient -TelemetryConnectionString $repoSettings.partnerTelemetryConnectionString
            $PartnerTelemetryClient.TrackTrace($Message, [Microsoft.ApplicationInsights.DataContracts.SeverityLevel]::$Severity, $Data)
            $PartnerTelemetryClient.Flush()
        }
    } catch {
        Write-Host "Failed to log telemetry event: $_"
    }
}

<#
    .SYNOPSIS
    Logs an information message to telemetry

    .DESCRIPTION
    Logs an information message to telemetry

    .PARAMETER Message
    The message to log to telemetry

    .PARAMETER ActionName
    The name of the action to log to telemetry

    .PARAMETER AdditionalData
    Additional data to log to telemetry

    .EXAMPLE
    Trace-Information -Message "AL-Go action ran: $actionName"
#>
function Trace-Information() {
    param(
        [Parameter(ParameterSetName = 'Message', Mandatory = $true)]
        [String] $Message,
        [Parameter(ParameterSetName = 'ActionName', Mandatory = $true)]
        [String] $ActionName,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    )

    if (-not $Message) {
        $Message = "AL-Go action ran: $ActionName"
    }

    AddTelemetryEvent -Message $Message -Severity 'Information' -Data $AdditionalData
}

<#
    .SYNOPSIS
    Logs an exception message to telemetry

    .DESCRIPTION
    Logs an exception message to telemetry

    .PARAMETER Message
    The message to log to telemetry

    .PARAMETER ActionName
    The name of the action to log to telemetry

    .PARAMETER ErrorRecord
    The error record to log to telemetry

    .PARAMETER AdditionalData
    Additional data to log to telemetry

    .EXAMPLE
    Trace-Exception -ErrorRecord $ErrorRecord
#>
function Trace-Exception() {
    param(
        [Parameter(ParameterSetName = 'Message', Mandatory = $true)]
        [String] $Message,
        [Parameter(ParameterSetName = 'ActionName', Mandatory = $true)]
        [String] $ActionName,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord = $null,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    )

    if ($ErrorRecord -ne $null) {
        Add-TelemetryProperty -Hashtable $AdditionalData -Key 'ErrorMessage' -Value $ErrorRecord.Exception.Message
    }

    if (-not $Message) {
        $Message = "AL-Go action failed: $ActionName"
    }
    AddTelemetryEvent -Message $Message -Severity 'Error' -Data $AdditionalData
}

<#
    .SYNOPSIS
    Adds a key-value pair to a hashtable if the key does not already exist

    .DESCRIPTION
    Adds a key-value pair to a hashtable if the key does not already exist

    .PARAMETER Hashtable
    The hashtable to add the key-value pair to

    .PARAMETER Key
    The key to add to the hashtable

    .PARAMETER Value
    The value to add to the hashtable

    .EXAMPLE
    Add-TelemetryProperty -Hashtable $AdditionalData -Key 'RepoType' -Value 'PTE'
#>
function Add-TelemetryProperty() {
    param(
        [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $Hashtable,
        [String] $Key,
        [String] $Value
    )
    if (-not $Hashtable.ContainsKey($Key) -and ($Value -ne '')) {
        $Hashtable.Add($Key, $Value)
    }
}

Export-ModuleMember -Function Trace-Information, Trace-Exception, Add-TelemetryProperty
