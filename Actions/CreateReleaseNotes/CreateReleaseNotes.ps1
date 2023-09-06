Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Tag name", Mandatory = $true)]
    [string] $tag_name,
    [Parameter(HelpMessage = "Last commit to include in release notes", Mandatory = $false)]
    [string] $target_commitish
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1")
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0074' -parentTelemetryScopeJson $parentTelemetryScopeJson

    Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

    # Check that tag is SemVer
    $SemVerObj = SemVerStrToSemVerObj -semVerStr $tag_name

    # Calculate release branch
    $releaseBranch = "release/$($SemVerObj.Prefix)$($SemVerObj.Major).$($SemVerObj.Minor)"
    if ($SemVerObj.Patch -or $SemVerObj.addt0 -ne 'zzz') {
        $releaseBranch += ".$($SemVerObj.Patch)"
        if ($SemVerObj.addt0 -ne 'zzz') {
            $releaseBranch += "-$($SemVerObj.addt0)"
            1..4 | ForEach-Object {
                if ($SemVerObj."addt$($_)" -ne 'zzz') {
                    $releaseBranch += ".$($SemVerObj."addt$($_)")"
                }
            }
        }
    }
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "releaseBranch=$releaseBranch"
    Write-Host "releaseBranch=$releaseBranch"

    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $ENV:GITHUB_REF_NAME
    if ($latestRelease -and $latestRelease.PSobject.Properties.name -eq "target_commitish") {
        if ($latestRelease.target_commitish -eq $target_commitish) {
            throw "The latest release is based on the same commit as this release is targetting."
        }
    }

    $latestReleaseTag = ""
    if ($latestRelease -and $latestRelease.PSobject.Properties.name -eq "tag_name") {
        $latestReleaseTag = $latestRelease.tag_name
    }

    try {
        $releaseNotes = GetReleaseNotes -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY  -tag_name $tag_name -previous_tag_name $latestReleaseTag -target_commitish $target_commitish | ConvertFrom-Json
        $releaseNotes = $releaseNotes.body -replace '%','%25' -replace '\n','%0A' -replace '\r','%0D' # supports a multiline text
    }
    catch {
        OutputWarning -message "Couldn't create release notes.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
        OutputWarning -message "You can modify the release note from the release page later."
        $releaseNotes = ""
    }
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "releaseNotes=$releaseNotes"
    Write-Host "releaseNotes=$releaseNotes"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
