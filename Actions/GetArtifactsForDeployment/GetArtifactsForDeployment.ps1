Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Artifacts version to download (current, prerelease, draft, latest or version number)", Mandatory = $true)]
    [string] $artifactsVersion,
    [Parameter(HelpMessage = "Folder in which the artifacts will be downloaded", Mandatory = $true)]
    [string] $artifactsFolder
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

# Get artifacts for all projects
$projects = "*"

Write-Host "Get artifacts for version: '$artifactsVersion' for these projects: '$projects' to folder: '$artifactsFolder'"

$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
if (!(Test-Path $artifactsFolder)) {
    New-Item $artifactsFolder -ItemType Directory | Out-Null
}
$searchArtifacts = $false
if ($artifactsVersion -eq "current" -or $artifactsVersion -eq "prerelease" -or $artifactsVersion -eq "draft") {
    Write-Host "Getting $artifactsVersion release artifacts"
    $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
    if ($releases) {
        if ($artifactsVersion -eq "current") {
            $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
        }
        elseif ($artifactsVersion -eq "prerelease") {
            $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
        }
        elseif ($artifactsVersion -eq "draft") {
            $release = $releases | Select-Object -First 1
        }
        if (!($release)) {
            throw "Unable to locate $artifactsVersion release"
        }
        'Apps','Dependencies','PowerPlatformSolution' | ForEach-Object {
            DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask $_ -unpack
        }
    }
    else {
        if ($artifactsVersion -eq "current") {
            Write-Host "::Warning::Current release was specified, but no releases were found. Searching for latest build artifacts instead."
            $artifactsVersion = "latest"
            $searchArtifacts = $true
        }
        else {
            throw "Artifact $artifactsVersion was not found on any release."
        }
    }
}
else {
    $searchArtifacts = $true
}

if ($searchArtifacts) {
    $allArtifacts = @()
    'Apps','Dependencies','PowerPlatformSolution' | ForEach-Object {
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $_ -projects $projects -version $artifactsVersion -branch $ENV:GITHUB_REF_NAME)
    }

    if ($allArtifacts) {
        $allArtifacts | ForEach-Object {
            $folder = DownloadArtifact -token $token -artifact $_ -path $artifactsFolder -unpack
            if (!(Test-Path $folder)) {
                throw "Unable to download artifact $($_.name)"
            }
        }
    }
    else {
        throw "Could not find any artifacts for projects: '$projects', version: '$artifactsVersion'"
    }
}
