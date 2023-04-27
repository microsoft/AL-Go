Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $Actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $Token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $ParentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "The name of the environment as defined in GitHub", Mandatory = $false)]
    [string] $PowerPlatformSolutionName,
    [Parameter(HelpMessage = "The name of the environment as defined in GitHub", Mandatory = $false)]
    [string] $EnvironmentName,
    [Parameter(HelpMessage = "The current location for files to be checked in", Mandatory = $false)]
    [string] $Location,
    [Parameter(HelpMessage = "The current location for files to be checked in", Mandatory = $false)]
    [string] $ServerUrl,
    [Parameter(HelpMessage = "The current location for files to be checked in", Mandatory = $false)]
    [string] $GitHubBranch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $ParentTelemetryScopeJson;
Write-Host "Starting GitHubCommitChanges.ps1 with parameters: $([environment]::Newline)Actor: $Actor$([environment]::Newline)Token: $Token$([environment]::Newline)ParentTelemetryScopeJson: $ParentTelemetryScopeJson$([environment]::Newline)EnvironmentName: $EnvironmentName$([environment]::Newline)Location: $Location$([environment]::Newline)ServerUrl: $ServerUrl$([environment]::Newline)GitHubBranch: $GitHubBranch"

# Import the helper script
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)


# IMPORTANT: No code that can fail should be outside the try/catch
try {
    Set-Location -Path $Location

    # Environment variables for hub commands
    $env:GITHUB_USER = $Actor
    $env:GITHUB_TOKEN = $Token

    # Commit from the new folder
    write-host "Committing changes from the new folder $Location\$PowerPlatformSolutionName to branch $GitHubBranch"
    CommitFromNewFolder -ServerUrl $serverUrl -CommitMessage "Update solution: $PowerPlatformSolutionName with latest from environment: $EnvironmentName" -Branch $GitHubBranch
    # TODO: Why can we not find the trackTrace function?
    #TrackTrace -telemetryScope $telemetryScope
}
catch {
    Write-Error -message "Pull changes failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    # TODO: Why can we not find the trackExceptions function?
    #TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {

}        
