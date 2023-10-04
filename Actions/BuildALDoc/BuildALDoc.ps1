Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "BuildALDoc.HelperFunctions.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$projects = '*'
$maxReleases = 2
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"

Write-Host $artifactsFolder
Write-Host (Test-Path $artifactsFolder)

$releases = @()
if ($maxReleases -gt 0) {
    $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First $maxReleases
}

$docsPath = Join-Path $ENV:GITHUB_WORKSPACE ".aldoc"
New-Item $docsPath -ItemType Directory | Out-Null

Write-Host (Get-Location)
Write-Host (Test-Path -Path (Get-Location))

Write-Host $docsPath

$loglevel = 'Verbose'

$versions = @($releases.Name)

foreach($release in $releases) {
    $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -Path $tempFolder -ItemType Directory | Out-Null
    try {
        foreach($mask in 'Apps', 'Dependencies') {
            DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask $mask -unpack
        }
        Write-Host "$($release.Name):"
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

Write-Host "main:"
Get-ChildItem -Path $artifactsFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($artifactsFolder.Length))" }
$allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $artifactsFolder -projects $projects -refname $ENV:GITHUB_REF_NAME

$version = 'main'
$header = "Documentation for $ENV:GITHUB_REPOSITORY"
$releaseNotes = "Documentation for current branch"
GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -releaseNotes $releaseNotes -header $header -docsPath $docsPath -logLevel $logLevel

## locate all artifacts folders in .artifacts
#Write-Host "CURRENT:"
#Get-ChildItem -Path $artifactsFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName)" }
#$apps = @()
#$dependencies = @()
#if (Test-Path $artifactsFolder -PathType Container) {
#    $projects.Split(',') | ForEach-Object {
#        $project = $_.Replace('\','_').Replace('/','_')
#        $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
#        Write-Host "project '$project'"
#        $apps += @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-Apps-*.*.*.*") | ForEach-Object { $_.FullName })
#        if (!($apps)) {
#            throw "There are no build artifacts present in .artifacts matching $project-$refname-Apps-<version>."
#        }
#        $dependencies += @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-Dependencies-*.*.*.*") | ForEach-Object { $_.FullName })
#    }
#}
#else {
#    throw "No build artifacts present in .artifacts."
#}

# locate all apps in the artifacts folders
#$allApps = @{}
#foreach($folder in $apps) {
#    $projectName = [System.IO.Path]::GetFileName($folder).Split("-$refname-Apps-")[0]
#    $allApps."$projectName" = @(Get-ChildItem -Path (Join-Path $folder '*.app') | Select-Object -ExpandProperty FullName)
#}
#
#$releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY |
#    Where-Object { -not ($_.prerelease -or $_.draft) } |
#    Select-Object -First $maxReleases
#
#foreach($release in $releases) {
#    $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
#    New-Item -Path $tempFolder -ItemType Directory | Out-Null
#    foreach($mask in 'Apps', 'Dependencies') {
#        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $tempFolder -mask $mask -unpack
#    }
#    Write-Host $release.Name
#    Get-ChildItem -Path $tempFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName)" }
#}
#
#$allApps | Out-Host
#
#Write-Host "Apps to build documentation for"
#$apps | Out-Host
#
#Write-Host "Dependencies"
#$dependencies | Out-Host
#
#Write-Host "Releases"
#$releases | Out-Host

throw "Not implemented"
