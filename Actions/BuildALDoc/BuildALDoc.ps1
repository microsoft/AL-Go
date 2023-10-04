Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$projects = '*'
$maxReleases = 2
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"

# locate all artifacts folders in .artifacts
$apps = @()
$dependencies = @()
if (Test-Path $artifactsFolder -PathType Container) {
    $projects.Split(',') | ForEach-Object {
        $project = $_.Replace('\','_').Replace('/','_')
        $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
        Write-Host "project '$project'"
        $apps += @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-Apps-*.*.*.*") | ForEach-Object { $_.FullName })
        if (!($apps)) {
            throw "There are no build artifacts present in .artifacts matching $project-$refname-Apps-<version>."
        }
        $dependencies += @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-Dependencies-*.*.*.*") | ForEach-Object { $_.FullName })
    }
}
else {
    throw "No build artifacts present in .artifacts."
}

# locate all apps in the artifacts folders
$allApps = @{}
foreach($folder in $apps) {
    $projectName = [System.IO.Path]::GetFileName($folder).Split("-$refname-Apps-")[0]
    $allApps."$projectName" = @(Get-ChildItem -Path (Join-Path $folder '*.app') | Select-Object -ExpandProperty FullName)
}

$releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY |
    Where-Object { -not ($_.prerelease -or $_.draft) } |
    Select-Object -First $maxReleases

foreach($release in $releases) {
    Write-Hosty $release.Name
    $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -Path $tempFolder -ItemType Directory | Out-Null
    DownloadRelease -token $token -projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask "Apps"
    DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask "Dependencies"
    Get-ChildItem -Path $tempFolder | ForEach-Object { $_.FullName } | Out-Host
}

Write-Host "Apps to build documentation for"
$apps | Out-Host

Write-Host "Dependencies"
$dependencies | Out-Host

Write-Host "Releases"
$releases | Out-Host


throw "Not implemented"
