Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "List of project names if the repository is setup for multiple projects (* for all projects)", Mandatory = $false)]
    [string] $projects = '*',
    [Parameter(HelpMessage = "The version to update to. Use Major.Minor for absolute change, use +1 to bump to the next major version, use +0.1 to bump to the next minor version", Mandatory = $true)]
    [string] $versionNumber,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct commit?", Mandatory = $false)]
    [bool] $directCommit
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path -path $PSScriptRoot -ChildPath "IncrementVersionNumber.psm1" -Resolve)

    $serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix 'increment-version-number'
    $baseFolder = (Get-Location).path
    DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0076' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $settings = $env:Settings | ConvertFrom-Json
    if ($versionNumber.StartsWith('+')) {
        # Handle incremental version number
        $allowedIncrementalVersionNumbers = @('+1', '+0.1')
        if (-not $allowedIncrementalVersionNumbers.Contains($versionNumber)) {
            throw "Incremental version number $versionNumber is not allowed. Allowed incremental version numbers are: $($allowedIncrementalVersionNumbers -join ', ')"
        }
    }
    else {
        # Handle absolute version number
        $versionNumberFormat = '^\d+\.\d+$' # Major.Minor
        if (-not ($versionNumber -match $versionNumberFormat)) {
            throw "Version number $versionNumber is not in the correct format. The version number must be in the format Major.Minor (e.g. 1.0 or 1.2)"
        }
    }

    # Collect all projects (AL and PowerPlatform Solution)
    $projectList = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $settings.projects -selectProjects $projects)
    $PPprojects = @(GetMatchingProjects -projects @($settings.powerPlatformSolutionFolder) -selectProjects $projects)
    if ($projectList.Count -eq 0 -and $PPprojects.Count -eq 0) {
        throw "No projects matches '$projects'"
    }

    $repositorySettingsPath = Join-Path $baseFolder $RepoSettingsFile # $RepoSettingsFile is defined in AL-Go-Helper.ps1

    # Increment version number in AL Projects
    if ($projectList.Count -gt 0) {
        $allAppFolders = @()
        $repoVersionExistsInRepoSettings = Test-SettingExists -settingsFilePath $repositorySettingsPath -settingName 'repoVersion'
        $repoVersionInRepoSettingsWasUpdated = $false
        foreach($project in $projectList) {
            $projectPath = Join-Path $baseFolder $project
            $projectSettingsPath = Join-Path $projectPath $ALGoSettingsFile # $ALGoSettingsFile is defined in AL-Go-Helper.ps1

            if (Test-SettingExists -settingsFilePath $projectSettingsPath -settingName 'repoVersion') {
                # If 'repoVersion' exists in the project settings, update it there
                Set-VersionInSettingsFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $versionNumber
            } elseif ($repoVersionExistsInRepoSettings) {
                # If 'repoVersion' is not found in project settings but it exists in repo settings, update it there instead
                if (-not $repoVersionInRepoSettingsWasUpdated) {
                    Write-Host "Setting 'repoVersion' not found in $projectSettingsPath. Updating it on repo level instead"
                    Set-VersionInSettingsFile -settingsFilePath $repositorySettingsPath -settingName 'repoVersion' -newValue $versionNumber
                    $repoVersionInRepoSettingsWasUpdated = $true
                }
            } else {
                # If 'repoVersion' is neither found in project settings nor in repo settings, force create it in project settings
                # Ensure the repoVersion setting exists in the project settings. Defaults to 1.0 if it doesn't exist.
                $settings = ReadSettings -baseFolder $baseFolder -project $project
                Set-VersionInSettingsFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $settings.repoVersion -Force
                Set-VersionInSettingsFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $versionNumber
            }

            # Resolve project folders to get all app folders that contain an app.json file
            $projectSettings = ReadSettings -baseFolder $baseFolder -project $project
            ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $projectSettings)

            # Set version in app manifests (app.json files)
            Set-VersionInAppManifests -projectPath $projectPath -projectSettings $projectSettings -newValue $versionNumber

            # Collect all project's app folders
            $allAppFolders += $projectSettings.appFolders | ForEach-Object { Join-Path $projectPath $_ -Resolve }
            $allAppFolders += $projectSettings.testFolders | ForEach-Object { Join-Path $projectPath $_ -Resolve }
            $allAppFolders += $projectSettings.bcptTestFolders | ForEach-Object { Join-Path $projectPath $_ -Resolve }
        }

        # Set dependencies in app manifests
        if($allAppFolders.Count -eq 0) {
            Write-Host "No App folders found for projects $projects"
        }
        else {
            # Set dependencies in app manifests
            Set-DependenciesVersionInAppManifests -appFolders $allAppFolders
        }
    }

    # Increment version number in PowerPlatform Solution
    foreach($PPproject in $PPprojects) {
        $projectPath = Join-Path $baseFolder $PPproject
        Set-PowerPlatformSolutionVersion -powerPlatformSolutionPath $projectPath -newValue $versionNumber
    }

    $commitMessage = "New Version number $versionNumber"
    if ($versionNumber.StartsWith('+')) {
        $commitMessage = "Incremented Version number by $versionNumber"
    }

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $branch | Out-Null

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
