Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Projects to include in the documentation", Mandatory = $false)]
    [string] $projects = '*'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "BuildALDoc.HelperFunctions.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$maxReleases = 2
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"

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
            DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask $mask -unpack
        }
        Write-Host "Version: $($release.Name):"
        Get-ChildItem -Path $tempFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($tempFolder.Length+1))" }
        $allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $tempFolder -projects $projects -refname $ENV:GITHUB_REF_NAME
        $version = $release.Name
        $header = "Documentation for $ENV:GITHUB_REPOSITORY $version"
        $releaseNotes = $release.body
        GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -releaseNotes $releaseNotes -header $header -docsPath $docsPath -logLevel $logLevel
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
$allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $artifactsFolder -projects $projects -refname $ENV:GITHUB_REF_NAME
$header = "Documentation for $ENV:GITHUB_REPOSITORY"
Write-Host "Latest release tag: $latestReleaseTag"
Write-Host "Commitish: $ENV:GITHUB_SHA"
$releaseNotes = GetReleaseNotes -token $token -tag_name 'vnext' -previous_tag_name $latestReleaseTag -target_commitish $ENV:GITHUB_SHA | ConvertFrom-Json
GenerateDocsSite -version '' -allVersions $versions -allApps $allApps -releaseNotes $releaseNotes -header $header -docsPath $docsPath -logLevel $logLevel
