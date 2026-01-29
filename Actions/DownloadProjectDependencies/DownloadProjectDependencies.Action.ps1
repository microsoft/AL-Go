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
        $projectDependencies,
        $buildMode,
        $baselineWorkflowRunID,
        $destinationPath,
        $token
    )

    Write-Host "Downloading dependencies for project '$project'"

    $dependencyProjects = @()
    if ($projectDependencies.Keys -contains $project) {
        $dependencyProjects = @($projectDependencies."$project")
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
        GetDependencies -probingPathsJson $probingPath -saveToPath $destinationPath | Where-Object { $_ } | ForEach-Object {
            $dependencyFileName = [System.IO.Path]::GetFileName($_.Trim('()'))
            if ($downloadedDependencies | Where-Object { [System.IO.Path]::GetFileName($_.Trim('()')) -eq $dependencyFileName }) {
                Write-Host "Dependency app '$dependencyFileName' already downloaded"
            }
            else {
                Write-Host "Dependency app '$dependencyFileName' downloaded"
                $downloadedDependencies += $_
            }
        }
    }

    return $downloadedDependencies
}

<#
    .Synopsis
        Gets the App IDs for all apps that a project will build.
    .Description
        Reads the app.json files from all app folders in the project and returns an array of App IDs.
        This is used to identify apps that the current project builds, so they can be excluded from
        downloaded dependencies (to avoid overwriting locally-built apps with ones from dependency projects).
#>
function GetProjectAppIds {
    param(
        $baseFolder,
        $project
    )

    $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
    ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $projectSettings)

    Push-Location $baseFolder
    try {
        $folders = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders) |
            Where-Object { $_ } |
            ForEach-Object {
                $resolvedPath = Join-Path $baseFolder "$project/$_"
                if (Test-Path $resolvedPath) {
                    return (Resolve-Path $resolvedPath -Relative)
                }
            } | Where-Object { $_ }
    }
    finally {
        Pop-Location
    }

    if (-not $folders -or $folders.Count -eq 0) {
        return @()
    }

    $unknownDependencies = @()
    $appIds = @()
    Sort-AppFoldersByDependencies -appFolders $folders -baseFolder $baseFolder -WarningAction SilentlyContinue -unknownDependencies ([ref]$unknownDependencies) -knownApps ([ref]$appIds) | Out-Null

    return $appIds
}

<#
    .Synopsis
        Filters downloaded dependencies by excluding apps that the current project builds.
    .Description
        When project B depends on project A, and both projects build an app with the same App ID,
        we should use the one built by project B (the current project) instead of downloading it from project A.
        This function filters out downloaded apps whose App ID matches one that the current project will build.
#>
function FilterDependenciesByAppId {
    param(
        [string[]] $downloadedDependencies,
        [string[]] $excludeAppIds
    )

    if (-not $excludeAppIds -or $excludeAppIds.Count -eq 0) {
        return $downloadedDependencies
    }

    $filteredDependencies = @()
    foreach ($dependency in $downloadedDependencies) {
        $appPath = $dependency.Trim('()')

        if (-not (Test-Path $appPath)) {
            # If the file doesn't exist, keep it in the list (might be a URL or other reference)
            $filteredDependencies += $dependency
            continue
        }

        try {
            $appJson = Get-AppJsonFromAppFile -appFile $appPath
            if ($excludeAppIds -contains $appJson.Id) {
                Write-Host "Excluding downloaded app '$($appJson.Name)' (ID: $($appJson.Id)) - this app is built by the current project"
                # Delete the downloaded file to avoid confusion
                Remove-Item -Path $appPath -Force -ErrorAction SilentlyContinue
                continue
            }
        }
        catch {
            Write-Host "Warning: Could not read app info from $appPath - keeping the dependency. Error: $($_.Exception.Message)"
        }

        $filteredDependencies += $dependency
    }

    return $filteredDependencies
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Base Folder: $baseFolder, Destination Path: $destinationPath"

$downloadedDependencies = @()

Write-Host "::group::Downloading project dependencies from current build"
$projectDependencies = $projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
$downloadedDependencies += DownloadDependenciesFromCurrentBuild -baseFolder $baseFolder -project $project -projectDependencies $projectDependencies -buildMode $buildMode -baselineWorkflowRunID $baselineWorkflowRunID -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading project dependencies from probing paths"
$downloadedDependencies += DownloadDependenciesFromProbingPaths -baseFolder $baseFolder -project $project -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

# Filter out apps that the current project builds (to avoid overwriting locally-built apps with dependency versions)
# This is controlled by the 'skipDependenciesBuiltByCurrentProject' setting (defaults to false for backwards compatibility)
$settings = $env:Settings | ConvertFrom-Json
if ($settings.skipDependenciesBuiltByCurrentProject) {
    Write-Host "::group::Filtering dependencies by App ID (skipDependenciesBuiltByCurrentProject is enabled)"
    $currentProjectAppIds = GetProjectAppIds -baseFolder $baseFolder -project $project
    if ($currentProjectAppIds -and $currentProjectAppIds.Count -gt 0) {
        OutputMessageAndArray -message "App IDs built by current project '$project'" -arrayOfStrings $currentProjectAppIds
        $downloadedDependencies = FilterDependenciesByAppId -downloadedDependencies $downloadedDependencies -excludeAppIds $currentProjectAppIds
    }
    else {
        Write-Host "No apps found in current project '$project' - no filtering needed"
    }
    Write-Host "::endgroup::"
}
else {
    Write-Host "Dependency filtering by App ID is disabled (skipDependenciesBuiltByCurrentProject is false or not set)"
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
