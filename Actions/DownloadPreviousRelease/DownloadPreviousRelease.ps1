Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$baseFolder = (Get-BasePath)
$projectFolder = Join-Path $baseFolder $project
$previousAppsPath = Join-Path $projectFolder ".previousRelease"

OutputGroupStart -Message "Locating previous release"
try {
    $branchForRelease = if ($ENV:GITHUB_BASE_REF) { $ENV:GITHUB_BASE_REF } else { $ENV:GITHUB_REF_NAME }
    $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $branchForRelease
    if ($latestRelease) {
        Write-Host "Using $($latestRelease.name) (tag $($latestRelease.tag_name)) as previous release"
        New-Item $previousAppsPath -ItemType Directory -Force | Out-Null
        DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $previousAppsPath -mask "Apps"
        $previousApps = @(Get-ChildItem -Path $previousAppsPath -Recurse -Filter "*.app" | ForEach-Object { $_.FullName })
        Write-Host "Downloaded $($previousApps.Count) previous release app(s)"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "PreviousAppsPath=$previousAppsPath"
    }
    else {
        OutputWarning -message "No previous release found"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "PreviousAppsPath="
    }
}
catch {
    OutputWarning -message "Error trying to locate previous release: $($_.Exception.Message). Continuing without baseline."
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "PreviousAppsPath="
}
finally {
    OutputGroupEnd
}
