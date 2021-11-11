Param(
    [string] $actor,
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent correlation Id for the Telemetry signal", Mandatory = $false)]
    [string] $parentCorrelationId,
    [Parameter(HelpMessage = "Specifies the event Id in the telemetry", Mandatory = $false)]
    [string] $telemetryEventId,
    [string] $workflowToken,
    [string] $tag_name
    )
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper 
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId $telemetryEventId -parentCorrelationId $parentCorrelationId

$releaseNotes = ""

try {
    Import-Module (Join-Path $PSScriptRoot '..\Helpers\Github-Helper.psm1' -Resolve)

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
    OutputWarning -message "::Error:: Couldn't create release notes. Error was $($_.Exception.Message)"
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
