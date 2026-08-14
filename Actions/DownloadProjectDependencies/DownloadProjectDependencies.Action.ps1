Param(
    [Parameter(HelpMessage = "The project for which to download dependencies", Mandatory = $true)]
    [string] $project,
    [string] $baseFolder,
    [string] $buildMode = 'Default',
    [string] $projectDependenciesJson,
    [string] $baselineWorkflowRunID = '0',
    [string] $destinationPath,
    [string] $token
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "DownloadProjectDependencies.psm1" -Resolve) -DisableNameChecking

function DownloadDependenciesFromProbingPaths {
    param(
        $baseFolder,
        $project,
        $destinationPath,
        $token
    )

    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
    $settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project
    if ($settings.ContainsKey('appDependencyProbingPaths') -and $settings.appDependencyProbingPaths) {
        $dependencies = GetDependencies -probingPathsJson $settings.appDependencyProbingPaths -saveToPath $destinationPath | Where-Object { $_ }

        # GetDependencies may return .zip files (from DownloadArtifact/DownloadRelease).
        # Extract .app files from any zips so downstream consumers receive clean .app paths.
        return Resolve-DependencyFiles -Dependencies $dependencies -DestinationPath $destinationPath
    }
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Base Folder: $baseFolder, Destination Path: $destinationPath"

$downloadedDependencies = @()

Write-Host "::group::Downloading project dependencies from current build"
$projectDependencies = $projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
$downloadedDependencies += Get-DependenciesFromCurrentBuild -baseFolder $baseFolder -project $project -projectDependencies $projectDependencies -buildMode $buildMode -baselineWorkflowRunID $baselineWorkflowRunID -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading project dependencies from probing paths"
$downloadedDependencies += DownloadDependenciesFromProbingPaths -baseFolder $baseFolder -project $project -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading dependencies from settings (installApps and installTestApps)"
Push-Location -Path (Join-Path $baseFolder $project)  #Change to the project folder because installApps paths are relative to the project folder
try {
    $settingsDependencies = Get-DependenciesFromInstallApps -DestinationPath $destinationPath
} finally {
    Pop-Location
    Write-Host "::endgroup::"
}

$downloadedApps = @()
$downloadedTestApps = @()

# Split the downloaded dependencies into apps and test apps
$downloadedDependencies | ForEach-Object {
    # naming convention: app, (testapp)
    if ($_.startswith('(')) {
        $downloadedTestApps += $_
    }
    else {
        $downloadedApps += $_
    }
}

# Add dependencies from settings (these are already resolved to .app files)
$downloadedApps += $settingsDependencies.Apps
$downloadedTestApps += $settingsDependencies.TestApps

OutputMessageAndArray -message "Downloaded dependencies (Apps)" -arrayOfStrings $downloadedApps
OutputMessageAndArray -message "Downloaded dependencies (Test Apps)" -arrayOfStrings $downloadedTestApps

# Write the downloaded apps and test apps to temporary JSON files and set them as GitHub Action outputs
$tempPath = NewTemporaryFolder
$downloadedAppsJson = Join-Path $tempPath "DownloadedApps.json"
$downloadedTestAppsJson = Join-Path $tempPath "DownloadedTestApps.json"
ConvertTo-Json $downloadedApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $downloadedAppsJson
ConvertTo-Json $downloadedTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $downloadedTestAppsJson

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedApps=$downloadedAppsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedTestApps=$downloadedTestAppsJson"
