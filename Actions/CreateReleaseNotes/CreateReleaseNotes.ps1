Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the Telemetry signal", Mandatory = $true)]
    [string] $parentTelemetryScope, 
    [Parameter(HelpMessage = "A GitHub token with permissions to modify workflows", Mandatory = $false)]
    [string] $workflowToken,
    [Parameter(HelpMessage = "Tag name", Mandatory = $true)]
    [string] $tag_name
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper 
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId 'DO0074' -parentTelemetryScope $parentTelemetryScope

$releaseNotes = ""

try {
    Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY 

    $latestReleaseTag = ""
    if ([bool]($latestRelease.PSobject.Properties.name -match "tag_name")) {
        $latestReleaseTag = $latestRelease.tag_name
    }

    $releaseNotes = GetReleaseNotes -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY  -tag_name $tag_name -previous_tag_name $latestReleaseTag

    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    Write-Host "set-output name=releaseNotes::$releaseNotes"
    
    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputWarning -message "Couldn't create release notes. Error was $($_.Exception.Message)"
    OutputWarning -message "You can modify the release note from the release page later."

    $releaseNotes = ""
    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}

return $releaseNotes
