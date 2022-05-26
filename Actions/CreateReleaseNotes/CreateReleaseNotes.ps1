Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "A GitHub token with permissions to modify workflows", Mandatory = $false)]
    [string] $workflowToken,
    [Parameter(HelpMessage = "Tag name", Mandatory = $true)]
    [string] $tag_name
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1")
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0074' -parentTelemetryScopeJson $parentTelemetryScopeJson
    
    $releaseNotes = ""

    Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

    SemVerStrToSemVerObj -semVerStr $tag_name | Out-Null

    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY 

    $latestReleaseTag = ""
    if ($latestRelease -and ([bool]($latestRelease.PSobject.Properties.name -match "tag_name"))){
        $latestReleaseTag = $latestRelease.tag_name
    }

    $releaseNotes = GetReleaseNotes -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY  -tag_name $tag_name -previous_tag_name $latestReleaseTag | ConvertFrom-Json
    $releaseNotes = $releaseNotes.body -replace '%','%25' -replace '\n','%0A' -replace '\r','%0D' # supports a multiline text

    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    Write-Host "set-output name=releaseNotes::$releaseNotes"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputWarning -message "Couldn't create release notes. $([environment]::Newline) $($_.Exception.Message)"
    OutputWarning -message "You can modify the release note from the release page later."

    $releaseNotes = ""
    Write-Host "::set-output name=releaseNotes::$releaseNotes"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}

return $releaseNotes
