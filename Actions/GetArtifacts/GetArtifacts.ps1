Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Type of artifacts to download", Mandatory = $true)]
    [string] $artifactVersion
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# Get artifacts for all projects
$projects = "*"

Write-Host "Get artifacts: '$artifactVersion' for these projects: '$projects'"
# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson
    $artifactVersion = $artifactVersion.Replace('/', ([System.IO.Path]::DirectorySeparatorChar)).Replace('\', ([System.IO.Path]::DirectorySeparatorChar))

    $apps = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"
    
    if ($artifactVersion -eq "current" -or $artifactVersion -eq "prerelease" -or $artifactVersion -eq "draft") {
        Write-Host "Getting $artifactVersion release artifacts"

        $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        if ($artifactVersion -eq "current") {
            $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
        }
        elseif ($artifactVersion -eq "prerelease") {
            $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
        }
        elseif ($artifactVersion -eq "draft") {
            $release = $releases | Select-Object -First 1
        }

        if (!($release)) {
            throw "Unable to locate $artifactVersion release"
        }

        New-Item $artifactsFolder -ItemType Directory | Out-Null
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Apps"
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Dependencies"
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "PowerPlatformsolution"  
        $apps = @((Get-ChildItem -Path $artifactsFolder) | ForEach-Object { $_.FullName })
        
        if (!$apps) {
            throw "Artifact $artifactVersion was not found on any release. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    else {
        write-host "Getting artifacts for version: $artifactVersion"

        if (!(Test-Path $artifactsFolder)) {
            New-Item $artifactsFolder -ItemType Directory | Out-Null
        }

        $allArtifacts = @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects $projects -Version $artifactVersion -branch "main")
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Dependencies" -projects $projects -Version $artifactVersion -branch "main")
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "PowerPlatformSolution" -projects $projects -Version $artifactVersion -branch "main")
        if ($allArtifacts) {
            $allArtifacts | ForEach-Object {
                $appFile = DownloadArtifact -token $token -artifact $_ -path $artifactsFolder
                if (!(Test-Path $appFile)) {
                    throw "Unable to download artifact $($_.name)"
                }
                $apps += @($appFile)
            }
        }
        else {
            throw "Could not find any Apps artifacts for projects $projects"
        }
    }

    Write-Host "Arifacts downloaded to $artifactsFolder"
    write-host "Unzip downloaded artifacts"
    $downloadedArtifacts = (Get-ChildItem -Path $artifactsFolder -Filter "*.zip").FullName
    foreach ($downloadedArtifact in $downloadedArtifacts) {
        Write-Host "Unzipping $downloadedArtifact"
        $downloadedArtifactName = [System.IO.Path]::GetFileNameWithoutExtension($downloadedArtifact)

        # Create a folder with the same name as the artifact
        $downloadedArtifactFolder = Join-Path -Path $artifactsFolder -ChildPath $downloadedArtifactName
        New-Item -ItemType Directory -Path $downloadedArtifactFolder -Force | Out-Null

        Expand-Archive -Path $downloadedArtifact -DestinationPath $downloadedArtifactFolder
        Remove-Item -Path $downloadedArtifact -Force
    }
}
catch {
    OutputError -message "Deploy action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
