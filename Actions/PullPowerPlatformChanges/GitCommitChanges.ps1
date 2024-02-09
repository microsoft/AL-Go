Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "The name of the environment as defined in GitHub", Mandatory = $false)]
    [string] $powerPlatformSolutionName,
    [Parameter(HelpMessage = "The name of the environment as defined in GitHub", Mandatory = $false)]
    [string] $environmentName,
    [Parameter(HelpMessage = "The current location for files to be checked in", Mandatory = $false)]
    [string] $location,
    [Parameter(HelpMessage = "ServerUrl for Git Push", Mandatory = $false)]
    [string] $serverUrl,
    [Parameter(HelpMessage = "Branch to update", Mandatory = $false)]
    [string] $gitHubBranch
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Write-Host "Starting GitHubCommitChanges.ps1 with parameters: $([environment]::Newline)actor: $Actor$([environment]::Newline)Token: $Token$([environment]::Newline)$([environment]::Newline)EnvironmentName: $EnvironmentName$([environment]::Newline)Location: $Location$([environment]::Newline)ServerUrl: $ServerUrl$([environment]::Newline)GitHubBranch: $GitHubBranch"

# Import the helper script
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Set-Location -Path $location

# Environment variables for hub commands
$env:GITHUB_USER = $actor
$env:GITHUB_TOKEN = $token

# Commit from the new folder
write-host "Committing changes from the new folder $Location\$PowerPlatformSolutionName to branch $GitHubBranch"
CommitFromNewFolder -ServerUrl $serverUrl -CommitMessage "Update solution: $PowerPlatformSolutionName with latest from environment: $EnvironmentName" -Branch $GitHubBranch
