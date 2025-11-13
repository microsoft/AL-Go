Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "The artifacts to build documentation for or a folder in which the artifacts have been downloaded", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "The URL of the BC artifact to download which includes AlDoc", Mandatory = $false)]
    [string] $artifactUrl = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "BuildReferenceDocumentation.HelperFunctions.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$settings = $env:Settings | ConvertFrom-Json
$includeProjects = $settings.alDoc.includeProjects
$excludeProjects = $settings.alDoc.excludeProjects
$maxReleases = $settings.alDoc.maxReleases
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"
$artifactsFolderCreated = $false
if (!(Test-Path $artifactsFolder)) {
    New-Item $artifactsFolder -ItemType Directory | Out-Null
    $artifactsFolderCreated = $true
}
if ($artifacts -ne ".artifacts") {
    Write-Host "::group::Downloading artifacts"
    $allArtifacts = @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects '*' -Version $artifacts -branch $ENV:GITHUB_REF_NAME)
    if ($allArtifacts) {
        $allArtifacts | ForEach-Object {
            $filename = DownloadArtifact -token $token -artifact $_ -path $artifactsFolder
            if (!(Test-Path $filename)) {
                throw "Unable to download artifact $($_.name)"
            }
            $destFolder = Join-Path $artifactsFolder ([System.IO.Path]::GetFileNameWithoutExtension($filename))
            Expand-Archive -Path $filename -DestinationPath $destFolder -Force
            Remove-Item -Path $filename -Force
        }
    }
    Write-Host "::endgroup::"
}

$header = $settings.alDoc.header
$footer = $settings.alDoc.footer
$defaultIndexMD = $settings.alDoc.defaultIndexMD.Replace('\n',"`n")
$defaultReleaseMD = $settings.alDoc.defaultReleaseMD.Replace('\n',"`n")

$releases = @()
if ($maxReleases -gt 0) {
    $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY | Where-Object { $_ } | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First $maxReleases
}

$docsPath = Join-Path $ENV:GITHUB_WORKSPACE ".aldoc"
if (!(Test-Path -path $docsPath)) {
    New-Item $docsPath -ItemType Directory | Out-Null
}
$loglevel = 'Info'

$versions = @($releases | ForEach-Object { $_.Name })
$latestReleaseTag = $releases | Select-Object -First 1 -ExpandProperty tag_name

foreach($release in $releases) {
    $tempFolder = NewTemporaryFolder
    try {
        Write-Host "::group::Release $($release.Name)"
        foreach($mask in 'Apps', 'Dependencies') {
            DownloadRelease -token $token -projects "$($includeProjects -join ',')" -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask $mask -unpack
        }
        Get-ChildItem -Path $tempFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($tempFolder.Length+1))" }
        $allApps, $allDependencies = CalculateProjectsAndApps -tempFolder $tempFolder -includeProjects $includeProjects -excludeProjects $excludeProjects -groupByProject:$settings.alDoc.groupByProject
        $version = $release.Name
        $releaseNotes = $release.body
        GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -repoName $settings.repoName -releaseNotes $releaseNotes -header $header -footer $footer -defaultIndexMD $defaultIndexMD -defaultReleaseMD $defaultReleaseMD -docsPath $docsPath -logLevel $logLevel -groupByProject:$settings.alDoc.groupByProject
        do {
            try {
                $retry = $false
                Start-Sleep -Seconds 2
                Rename-Item -Path (join-Path $docsPath "_site") -NewName $version
            }
            catch {
                $retry = $true
            }
        } while ($retry)
        Write-Host "::endgroup::"
    }
    finally {
        Remove-Item -Path $tempFolder -Recurse -Force
    }
}

$releasesPath = Join-Path $docsPath "_site/releases"
New-Item -Path $releasesPath -ItemType Directory | Out-Null
foreach($version in $versions) {
    Move-Item -Path (join-Path $docsPath $version) -Destination $releasesPath
}

Write-Host "::group::Main"

Get-ChildItem -Path $artifactsFolder -Depth 1 -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($artifactsFolder.Length))" }
$allApps, $allDependencies = CalculateProjectsAndApps -tempFolder $artifactsFolder -includeProjects $includeProjects -excludeProjects $excludeProjects -groupByProject:$settings.alDoc.groupByProject
$releaseNotes = ''
if ($latestReleaseTag) {
    try {
        $releaseNotes = (GetReleaseNotes -token $token -tag_name 'main' -previous_tag_name $latestReleaseTag -target_commitish $ENV:GITHUB_SHA | ConvertFrom-Json).body
    }
    catch {
        $releaseNotes = "## What's new`n`nError creating release notes"
    }
}
else {
    $releaseNotes = ''
}
if ($allApps.Count -gt 0) {
    GenerateDocsSite -version '' -allVersions $versions -allApps $allApps -repoName $settings.repoName -releaseNotes $releaseNotes -header $header -footer $footer -defaultIndexMD $defaultIndexMD -defaultReleaseMD $defaultReleaseMD -docsPath $docsPath -logLevel $logLevel -groupByProject:$settings.alDoc.groupByProject -artifactUrl $artifactUrl
}
else {
    OutputWarning -message "No apps found to generate documentation for"
}
Write-Host "::endgroup::"

if ($artifactsFolderCreated) {
    Remove-Item $artifactsFolder -Recurse -Force
}
