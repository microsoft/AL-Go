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

$releases = @()
if ($maxReleases -gt 0) {
    $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY | Where-Object { $_ } | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First $maxReleases
    $releases | Out-Host
}

$docsPath = Join-Path $ENV:GITHUB_WORKSPACE ".aldoc"
New-Item $docsPath -ItemType Directory | Out-Null
$loglevel = 'Info'

$versions = @($releases | ForEach-Object { $_.Name })

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


$dependeciesProbingPaths = @(@{
    "release_status"  = "thisbuild"
    "version"         = "latest"
    "buildMode"       = 'default'
    "projects"        = $projects
    "repo"            = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
    "branch"          = $ENV:GITHUB_REF_NAME
    "baseBranch"      = $ENV:GITHUB_REF_NAME
    "authTokenSecret" = $token
})
$tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -Path $tempFolder -ItemType Directory | Out-Null
try {
    $allApps = GetDependencies -probingPathsJson $dependeciesProbingPaths -saveToPath $tempFolder -masks @('Apps')
    $allDependencies = GetDependencies -probingPathsJson $dependeciesProbingPaths -saveToPath $tempFolder -masks @('Dependencies')
    $version = 'main'
    $header = "Documentation for $ENV:GITHUB_REPOSITORY"
    $releaseNotes = "Documentation for current branch"
    GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -releaseNotes $releaseNotes -header $header -docsPath $docsPath -logLevel $logLevel
}
finally {
    Remove-Item -Path $tempFolder -Recurse -Force
}

#Write-Host "main:"
#Get-ChildItem -Path $artifactsFolder -Recurse -File | ForEach-Object { Write-Host "- $($_.FullName.Substring($artifactsFolder.Length))" }
#$allApps,$allDependencies = CalculateProjectsAndApps -tempFolder $artifactsFolder -projects $projects -refname $ENV:GITHUB_REF_NAME
#$version = 'main'
#$header = "Documentation for $ENV:GITHUB_REPOSITORY"
#$releaseNotes = "Documentation for current branch"
#GenerateDocsSite -version $version -allVersions $versions -allApps $allApps -releaseNotes $releaseNotes -header $header -docsPath $docsPath -logLevel $logLevel
