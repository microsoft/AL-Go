Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Write-Host "Starting GitCloneRepository.ps1 with parameters: $([environment]::Newline)actor: $actor$([environment]::Newline)updateBranch: $updateBranch$([environment]::Newline)directCommit: $directCommit"

# Import the helper script
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Cloning the repository into a new folder"
$serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix "pull-powerplatform-changes"
$baseFolder = (Get-Location).Path

Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "clonedRepoPath=$baseFolder"
Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "serverUrl=$serverUrl"
Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "gitHubBranch=$branch"
