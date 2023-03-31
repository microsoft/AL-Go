Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $Actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $Token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $ParentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [string] $DirectCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $ParentTelemetryScopeJson;
Write-Host "Starting GitCloneRepository.ps1 with parameters: $([environment]::Newline)Actor: $Actor$([environment]::Newline)Token: $Token$([environment]::Newline)ParentTelemetryScopeJson: $ParentTelemetryScopeJson$([environment]::Newline)DirectCommit: $DirectCommit"

# Import the helper script
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)


# IMPORTANT: No code that can fail should be outside the try/catch
try {    
    $gitHubBranch = ""    
    if ($DirectCommit -eq "false") {
        $gitHubBranch = [System.IO.Path]::GetRandomFileName()
        Write-Host "Creating a new branch: $gitHubBranch"
    }
    
    Write-Host "Cloning the repository into a new folder"
    $serverUrl = CloneIntoNewFolder -Actor $Actor -Token $Token -Branch $gitHubBranch
    $baseFolder = (Get-Location).Path

    Add-Content -Path $env:GITHUB_ENV -Value "clonedRepoPath=$baseFolder"
    Add-Content -Path $env:GITHUB_ENV -Value "serverUrl=$serverUrl"
    Add-Content -Path $env:GITHUB_ENV -Value "gitHubBranch=$gitHubBranch"
    #TrackTrace -telemetryScope $telemetryScope
}
catch {
    Write-Error -message "Pull changes failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    # TODO: Why can we not find the trackExceptions function?
    #TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {

}
        
