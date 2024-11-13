Param(
    [Parameter(HelpMessage = "The project for which to download dependencies", Mandatory = $true)]
    [string] $project,
    [string] $baseFolder,
    [string] $buildMode = 'Default',
    [string] $projectsDependenciesJson,
    [string] $baselineWorkflowRunID = '0',
    [string] $destinationPath,
    [string] $token
)

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
        return GetDependencies -probingPathsJson $settings.appDependencyProbingPaths -saveToPath $destinationPath | Where-Object { $_ }
    }
}

function DownloadDependenciesFromCurrentBuild {
    param(
        $baseFolder,
        $project,
        $projectsDependencies,
        $buildMode,
        $baselineWorkflowRunID,
        $destinationPath,
        $token
    )

    Write-Host "Downloading dependencies for project '$project'"

    $dependencyProjects = @()
    if ($projectsDependencies.Keys -contains $project) {
        $dependencyProjects = @($projectsDependencies."$project")
    }

    Write-Host "Dependency projects: $($dependencyProjects -join ', ')"

    # For each dependency project, calculate the corresponding probing path
    $dependeciesProbingPaths = @()
    foreach($dependencyProject in $dependencyProjects) {
        Write-Host "Reading settings for project '$dependencyProject'"
        $dependencyProjectSettings = ReadSettings -baseFolder $baseFolder -project $dependencyProject

        $dependencyBuildMode = $buildMode
        if ($dependencyBuildMode -ne 'Default' -and !($dependencyProjectSettings.buildModes -contains $dependencyBuildMode)) {
            # Download the default build mode if the specified build mode is not supported for the dependency project
            Write-Host "Build mode '$dependencyBuildMode' is not supported for project '$dependencyProject'. Using the default build mode."
            $dependencyBuildMode = 'Default';
        }

        $headBranch = $ENV:GITHUB_HEAD_REF
        # $ENV:GITHUB_HEAD_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
        if (!$headBranch) {
            $headBranch = $ENV:GITHUB_REF_NAME
        }

        $baseBranch = $ENV:GITHUB_BASE_REF
        # $ENV:GITHUB_BASE_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
        if (!$baseBranch) {
            $baseBranch = $ENV:GITHUB_REF_NAME
        }

        $dependeciesProbingPaths += @(@{
            "release_status"  = "thisBuild"
            "version"         = "latest"
            "buildMode"       = $dependencyBuildMode
            "projects"        = $dependencyProject
            "repo"            = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
            "branch"          = $headBranch
            "baseBranch"      = $baseBranch
            "baselineWorkflowID" = $baselineWorkflowRunID
            "authTokenSecret" = $token
        })
    }

    # For each probing path, download the dependencies
    $downloadedDependencies = @()
    foreach($probingPath in $dependeciesProbingPaths) {
        $buildMode = $probingPath.buildMode
        $project = $probingPath.projects
        $branch = $probingPath.branch
        $baseBranch = $probingPath.baseBranch
        $baselineWorkflowRunID = $probingPath.baselineWorkflowID

        Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Branch: $branch, Base Branch: $baseBranch, Baseline Workflow ID: $baselineWorkflowRunID"

        $dependency = GetDependencies -probingPathsJson $probingPath -saveToPath $destinationPath | Where-Object { $_ }
        $downloadedDependencies += $dependency
    }

    return $downloadedDependencies
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Base Folder: $baseFolder, Destination Path: $destinationPath"

$downloadedDependencies = @()

Write-Host "::group::Downloading project dependencies from current build"
Write-Host $projectsDependenciesJson
$projectsDependencies = $projectsDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
$downloadedDependencies += DownloadDependenciesFromCurrentBuild -baseFolder $baseFolder -project $project -projectsDependencies $projectsDependencies -buildMode $buildMode -baselineWorkflowRunID $baselineWorkflowRunID -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading project dependencies from probing paths"
$downloadedDependencies += DownloadDependenciesFromProbingPaths -baseFolder $baseFolder -project $project -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "Downloaded dependencies: $($downloadedDependencies -join ', ')"

$downloadedApps = @()
$downloadedTestApps = @()

# Split the downloaded dependencies into apps and test apps
$downloadedDependencies | ForEach-Object {
    # naming convention: app, (testapp)
    if ($_.startswith('(')) {
        $DownloadedTestApps += $_
    }
    else {
        $DownloadedApps += $_
    }
}

Write-Host "Downloaded dependencies apps: $($DownloadedApps -join ', ')"
Write-Host "Downloaded dependencies test apps: $($DownloadedTestApps -join ', ')"

$DownloadedAppsJson = ConvertTo-Json $DownloadedApps -Depth 99 -Compress
$DownloadedTestAppsJson = ConvertTo-Json $DownloadedTestApps -Depth 99 -Compress

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedApps=$DownloadedAppsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedTestApps=$DownloadedTestAppsJson"
