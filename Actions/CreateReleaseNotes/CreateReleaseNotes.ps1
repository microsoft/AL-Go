Param(
    [string] $actor,
    [string] $token,
    [string] $workflowToken,
    [string] $tag_name
    )
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$releaseNotes = ""

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")
    Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY 

    $latestReleaseTag = ""
    if ([bool]($latestRelease.PSobject.Properties.name -match "tag_name")) {
        $latestReleaseTag = $latestRelease.tag_name
    }

    $releaseNotes = GetReleaseNotes -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY  -tag_name $tag_name -previous_tag_name $latestReleaseTag

    Write-Host "::set-output name=releaseNotes::$releaseNotes"
}
catch {
    OutputWarning -message "::Error:: Couldn't create release notes. Error was $($_.Exception.Message)"
    OutputWarning -message "You can modify the release note from the release page later."

    $releaseNotes = ""
    Write-Host "::set-output name=releaseNotes::$releaseNotes"
}
    
return $releaseNotes
