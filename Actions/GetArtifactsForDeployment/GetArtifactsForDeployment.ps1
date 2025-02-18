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
$artifactsToDownload = @("Apps","TestApps","Dependencies","PowerPlatformSolution")

Write-Host "Get artifacts for version: '$artifactsVersion' for these projects: '$projects' to folder: '$artifactsFolder'"

$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
if (!(Test-Path $artifactsFolder)) {
    New-Item $artifactsFolder -ItemType Directory | Out-Null
}
$searchArtifacts = $false
$downloadArtifacts = $false
$allArtifacts = @()
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
        $artifactsToDownload | ForEach-Object {
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
elseif ($artifactsVersion -like "PR_*") {
    $prId = $artifactsVersion -replace "PR_", ""
    if (!($prId -as [int])) {
        throw "Invalid PR id: $prId"
    }
    $prLatestCommitSha = GetLatestCommitShaFromPRId -repository $ENV:GITHUB_REPOSITORY -prId $prId -token $token
    if (!($prLatestCommitSha)) {
        throw "Unable to locate commit sha for PR $prId"
    }
    $latestPRBuildId = FindLatestPRRun -repository $ENV:GITHUB_REPOSITORY -commitSha $prLatestCommitSha -token $token
    if ($latestPRBuildId -eq 0) {
        $prLink = "https://github.com/$($ENV:GITHUB_REPOSITORY)/pull/$prId"
        throw "Latest PR build for PR $prId not found, not completed or not successful - Please re-run this workflow when you have a successful build on PR_$prId ($prLink)"
    }

    $expiredArtifacts = @()
    $artifactsToDownload | ForEach-Object {
        $allArtifacts += GetArtifactsFromWorkflowRun -workflowRun $latestPRBuildId -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $_ -projects $projects -expiredArtifacts ([ref]$expiredArtifacts)
    }
    if ($expiredArtifacts) {
        $prBuildLink = "https://github.com/$($ENV:GITHUB_REPOSITORY)/actions/runs/$latestPRBuildId"
        $shortLivedRetentionSettingLink = "https://aka.ms/algosettings#shortLivedArtifactsRetentionDays"
        throw "Build artifacts are expired, please re-run the pull request build ($prBuildLink) - Hint: you can control the retention days of short-lived artifacts in the AL-Go settings ($shortLivedRetentionSettingLink)"
    }
    $downloadArtifacts = $true
}
else {
    $searchArtifacts = $true
}

if ($searchArtifacts) {
    $artifactsToDownload | ForEach-Object {
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $_ -projects $projects -version $artifactsVersion -branch $ENV:GITHUB_REF_NAME)
    }
    $downloadArtifacts = $true
}

if ($downloadArtifacts) {
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
