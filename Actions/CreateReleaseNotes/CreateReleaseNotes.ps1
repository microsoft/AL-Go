Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "App Version", Mandatory = $true)]
    [string] $appVersion,
    [Parameter(HelpMessage = "Tag name", Mandatory = $true)]
    [string] $tag_name,
    [Parameter(HelpMessage = "Last commit to include in release notes", Mandatory = $false)]
    [string] $target_commitish
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1")
DownloadAndImportBcContainerHelper

Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

# Check that tag is SemVer
$SemVerObj = SemVerStrToSemVerObj -semVerStr $tag_name

# Calculate release version
$releaseVersion = "$($SemVerObj.Prefix)$($SemVerObj.Major).$($SemVerObj.Minor)"
if ($SemVerObj.Patch -or $SemVerObj.addt0 -ne 'zzz') {
    $releaseVersion += ".$($SemVerObj.Patch)"
    if ($SemVerObj.addt0 -ne 'zzz') {
        $releaseVersion += "-$($SemVerObj.addt0)"
        1..4 | ForEach-Object {
            if ($SemVerObj."addt$($_)" -ne 'zzz') {
                $releaseVersion += ".$($SemVerObj."addt$($_)")"
            }
        }
    }
}
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "releaseVersion=$releaseVersion"
Write-Host "releaseVersion=$releaseVersion"

$latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $ENV:GITHUB_REF_NAME
if ($latestRelease -and $latestRelease.PSobject.Properties.name -eq "target_commitish") {
    if ($latestRelease.target_commitish -eq $target_commitish) {
        throw "The latest release is based on the same commit as this release is targetting."
    }
}

$latestReleaseTag = ""
if ($latestRelease -and $latestRelease.PSobject.Properties.name -eq "tag_name") {
    $latestReleaseTag = $latestRelease.tag_name
    Write-Host "Latest release tag: $latestReleaseTag"
    try {
        $compareResult = CompareSemVerStrs -semVerStr1 $tag_name -semVerStr2 $latestReleaseTag
        if ($compareResult -eq 0) {
            OutputError "The release tag is the same as the latest release tag."
        }
        elseif ($compareResult -eq -1) {
            if ($appVersion -eq 'latest') {
                OutputError -message "The release tag is older than the latest release tag."
            }
            else {
                OutputWarning -message "The release tag is older than the latest release tag. The app version is set to $appVersion, so the action will continue."
            }
        }
    }
    catch {
        OutputWarning "Unable to compare the release tag $tag_name with the latest release tag $latestReleaseTag. The release might have been created manually."
    }
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
