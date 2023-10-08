Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "BuildALDoc.HelperFunctions.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$settings = $env:Settings | ConvertFrom-Json
$projects = $settings.ALDoc.Projects
$excludeProjects = $settings.ALDoc.ExcludeProjects
$maxReleases = $settings.ALDoc.MaxReleases
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"
$header = $settings.ALDoc.Header.Replace('{REPOSITORY}',$ENV:GITHUB_REPOSITORY).Replace('{VERSION}',$version)
$footer = $settings.ALDoc.Footer.Replace('{REPOSITORY}',$ENV:GITHUB_REPOSITORY).Replace('{VERSION}',$version)
$defaultIndexMD = $settings.ALDoc.DefaultIndexMD.Replace('\n',"`n")
$defaultReleaseMD = $settings.ALDoc.DefaultReleaseMD.Replace('\n',"`n")

$releases = @()
if ($maxReleases -gt 0) {
    $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY | Where-Object { $_ } | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First $maxReleases
}

$docsPath = Join-Path $ENV:GITHUB_WORKSPACE ".aldoc"
New-Item $docsPath -ItemType Directory | Out-Null
$loglevel = 'Info'

$versions = @($releases | ForEach-Object { $_.Name })
$latestReleaseTag = $releases | Select-Object -First 1 -ExpandProperty tag_name

foreach($release in $releases) {
    $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -Path $tempFolder -ItemType Directory | Out-Null
    try {
        foreach($mask in 'Apps', 'Dependencies') {
            DownloadRelease -token $token -projects "$($projects -join ',')" -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask $mask -unpack
        }
        Write-Host "Version: $($release.Name):"
        Get-ChildItem -Path $tempFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($tempFolder.Length+1))" }
        $allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $tempFolder -projects $projects -excludeProjects $excludeProjects -refname $ENV:GITHUB_REF_NAME
        $version = $release.Name
        $releaseNotes = $release.body
        GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -repoName $settings.repoName -releaseNotes $releaseNotes -header $header -footer $footer -defaultIndexMD $defaultIndexMD -defaultReleaseMD $defaultReleaseMD -docsPath $docsPath -logLevel $logLevel
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

Get-ChildItem -Path $artifactsFolder -Depth 1 -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($artifactsFolder.Length))" }
$allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $artifactsFolder -projects $projects -excludeProjects $excludeProjects -refname $ENV:GITHUB_REF_NAME
$header = "Documentation for $ENV:GITHUB_REPOSITORY"
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
GenerateDocsSite -version '' -allVersions $versions -allApps $allApps -repoName $settings.repoName -releaseNotes $releaseNotes -header $header -footer $footer -defaultIndexMD $defaultIndexMD -defaultReleaseMD $defaultReleaseMD -docsPath $docsPath -logLevel $logLevel
