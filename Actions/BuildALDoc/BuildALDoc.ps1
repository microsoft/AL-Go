Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$projects = '*'
$maxReleases = 2
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"

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

$releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY |
    Where-Object { -not ($_.prerelease -or $_.draft) } |
    Select-Object -First $maxReleases

#            $artifactsFolderCreated = $true
#            DownloadRelease -token $token -projects $deploymentSettings.Projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Apps"
#            DownloadRelease -token $token -projects $deploymentSettings.Projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Dependencies"
#            $apps = @((Get-ChildItem -Path $artifactsFolder) | ForEach-Object { $_.FullName })
#            if (!$apps) {
#                throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
#            }

Write-Host "Apps to build documentation for"
$apps | Out-Host

Write-Host "Dependencies"
$dependencies | Out-Host

Write-Host "Releases"
$releases | Out-Host


throw "Not implemented"
