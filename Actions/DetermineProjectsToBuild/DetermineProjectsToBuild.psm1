. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .Synopsis
        Gets the modified files in a GitHub pull request.
#>
function Get-ModifiedFiles {
    param(
        [Parameter(HelpMessage = "The baseline SHA", Mandatory = $true)]
        [string] $baselineSHA
    )

    Push-Location $ENV:GITHUB_WORKSPACE
    try {
        $ghEvent = Get-Content $env:GITHUB_EVENT_PATH -Encoding UTF8 | ConvertFrom-Json
        if ($ghEvent.PSObject.Properties.name -eq 'pull_request') {
            $headSHA = $ghEvent.pull_request.head.sha
            Write-Host "Using head SHA $headSHA from pull request"
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $headSHA | Out-Host }
            if ($baselineSHA) {
                Write-Host "This is a pull request, but baseline SHA was specified to $baselineSHA"
            }
            else {
                $baselineSHA = $ghEvent.pull_request.base.sha
                Write-Host "This is a pull request, using baseline SHA $baselineSHA from pull request"
            }
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $baselineSHA | Out-Host }
        }
        else {
            $headSHA = git rev-parse HEAD
            Write-Host "Current HEAD is $headSHA"
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $baselineSHA | Out-Host }
            Write-Host "Not a pull request, using baseline SHA $baselineSHA and current HEAD $headSHA"
        }
        Write-Host "git diff --name-only $baselineSHA $headSHA"
        $modifiedFiles = @(RunAndCheck git diff --name-only $baselineSHA $headSHA | ForEach-Object { "$_".Replace('/', [System.IO.Path]::DirectorySeparatorChar) })
        return $modifiedFiles
    }
    finally {
        Pop-Location
    }
}

<#
.Synopsis
    Filters AL-Go projects based on modified files.

.Outputs
    An array of AL-Go projects, filtered based on the modified files.
#>
function ShouldBuildProject {
    param (
        [Parameter(HelpMessage = "An AL-Go project", Mandatory = $true)]
        $project,
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        $baseFolder,
        [Parameter(HelpMessage = "A list of modified files", Mandatory = $true)]
        $modifiedFiles
    )
    Write-Host "Determining whether to build project $project based on modified files"

    $projectFolders = GetProjectFolders -baseFolder $baseFolder -project $project -includeAlGoFolder

    $modifiedProjectFolders = @()
    foreach($projectFolder in $projectFolders) {
        $projectFolder = Join-Path $baseFolder "$projectFolder/*"

        if ($modifiedFiles -like $projectFolder) {
            $modifiedProjectFolders += $projectFolder
        }
    }

    if ($modifiedProjectFolders.Count -gt 0) {
        Write-Host "Modified files found for project $project : $($modifiedProjectFolders -join ', ')"
        return $true
    }

    Write-Host "No modified files found for project $project. Not building project"
    return $false
}

<#
.Synopsis
    Creates buils dimensions for a list of projects.

.Outputs
    An array of build dimensions for the projects and their corresponding build modes.
    Each build dimension is a hashtable with the following keys:
    - project: The name of the AL-Go project
    - buildMode: The build mode to use for the project
#>
function CreateBuildDimensions {
    param(
        [Parameter(HelpMessage = "A list of AL-Go projects for which to generate build dimensions")]
        $projects = @(),
        $baseFolder
    )

    $buildDimensions = @()

    foreach($project in $projects) {
        $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
        $gitHubRunner = $projectSettings.githubRunner.Split(',').Trim() | ConvertTo-Json -compress
        $githubRunnerShell = $projectSettings.githubRunnerShell
        $buildModes = @($projectSettings.buildModes)

        if(!$buildModes) {
            Write-Host "No build modes found for project $project, using default build mode 'Default'."
            $buildModes = @('Default')
        }

        foreach($buildMode in $buildModes) {
            $buildDimensions += @{
                project = $project
                projectName = $projectSettings.projectName
                buildMode = $buildMode
                gitHubRunner = $gitHubRunner
                githubRunnerShell = $githubRunnerShell
            }
        }
    }

    return @(, $buildDimensions) # force array
}

<#
.Synopsis
    Analyzes a folder for AL-Go projects and determines the build order of these projects.

.Description
    Analyzes a folder for AL-Go projects and determines the build order of these projects.
    The build order is determined by the project dependencies and the projects that have been modified.

.Outputs
    The function returns the following values:
    - projects: An array of all projects found in the folder
    - modifiedProjects: An array of projects that have been modified
    - projectsToBuild: An array of projects that need to be built
    - projectDependencies: A hashtable with the project dependencies
    - projectsOrderToBuild: An array of build dimensions, each build dimension contains the following properties:
        - projects: An array of projects to build
        - projectsCount: The number of projects to build
        - buildDimensions: An array of build dimensions, to be used in a build matrix. Properties of the build dimension are:
            - project: The project to build
            - buildMode: The build mode to use
#>
function Get-ProjectsToBuild {
    param (
        [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
        $baseFolder,
        [Parameter(HelpMessage = "Whether a full build is required", Mandatory = $false)]
        [bool] $buildAllProjects = $true,
        [Parameter(HelpMessage = "An array of changed files paths, used to filter the projects to build", Mandatory = $false)]
        [string[]] $modifiedFiles = @(),
        [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
        [int] $maxBuildDepth = 0
    )

    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

    Write-Host "Determining projects to build in $baseFolder"

    Push-Location $baseFolder
    try {
        $settings = $env:Settings | ConvertFrom-Json
        $projects = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $settings.projects)
        Write-Host "Found AL-Go Projects: $($projects -join ', ')"

        $modifiedProjects = @()
        $projectsToBuild = @()
        $projectsOrderToBuild = @()

        if ($projects) {
            # Calculate the full projects order
            $projectBuildInfo = AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects

            if ($modifiedFiles) {
                Write-Host "Calculating modified projects based on the modified files"

                #Include the base folder in the modified files
                $modifiedFilesFullPaths = @($modifiedFiles | ForEach-Object { return Join-Path $baseFolder $_ })
                $modifiedProjects = @($projects |
                                        Where-Object { ShouldBuildProject -baseFolder $baseFolder -project $_ -modifiedFiles $modifiedFilesFullPaths } |
                                        ForEach-Object { $_; if ($projectBuildInfo.AdditionalProjectsToBuild.Keys -contains $_) { $projectBuildInfo.AdditionalProjectsToBuild."$_" } } |
                                        Select-Object -Unique)
            }

            if($buildAllProjects) {
                Write-Host "Calculating full build matrix"
                $projectsToBuild = @($projects)
            }
            else {
                Write-Host "Calculating incremental build matrix"
                $projectsToBuild = @($modifiedProjects)
            }

            # Create a project order based on the projects to build
            foreach($depth in $projectBuildInfo.FullProjectsOrder) {
                $projectsOnDepth = @($depth.projects | Where-Object { $projectsToBuild -contains $_ })

                if ($projectsOnDepth) {
                    # Create build dimensions for the projects on the current depth
                    $buildDimensions = CreateBuildDimensions -baseFolder $baseFolder -projects $projectsOnDepth
                    $projectsOrderToBuild += @{
                        projects = $projectsOnDepth
                        projectsCount = $projectsOnDepth.Count
                        buildDimensions = $buildDimensions
                    }
                }
            }
        }

        if ($projectsOrderToBuild.Count -eq 0) {
            Write-Host "Did not find any projects to add to the build order, adding default values"
            $projectsOrderToBuild += @{
                projects = @()
                projectsCount = 0
                buildDimensions = @()
            }
        }
        Write-Host "Projects to build: $($projectsToBuild -join ', ')"

        if($maxBuildDepth -and ($projectsOrderToBuild.Count -gt $maxBuildDepth)) {
            throw "The build depth is too deep, the maximum build depth is $maxBuildDepth. You need to run 'Update AL-Go System Files' to update the workflows"
        }

        return $projects, $modifiedProjects, $projectsToBuild, $projectBuildInfo.projectDependencies, $projectsOrderToBuild
    }
    finally {
        Pop-Location
    }
}

<#
.Synopsis
    Determines whether a full build is required and whether to publish artifacts from skipped projects based on the event and settings.
.Outputs
    A boolean indicating whether a full build is required and a boolean indicating whether to publish artifacts from skipped projects.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - Deprecated setting alwaysBuildAllProjects is set to true
    - property incrementalBuilds.onPull_Request is set to false for pull_request and pull_request_target events
    - property incrementalBuilds.onPush is set to false for push events
    - property incrementalBuilds.onSchedule is set to false for schedule events
    Skipped projects are published if:
    - The event is not a pull_request or pull_request_target event
#>
function Get-BuildAllProjectsBasedOnEventAndSettings {
    Param(
        [string] $ghEventName,
        [PSCustomObject] $settings
    )
    $buildAllProjects = $true
    $publishSkippedProjects = $true
    if ($ghEventName -eq 'pull_request' -or $ghEventName -eq 'pull_request_target') {
        # DEPRECATION: REMOVE AFTER October 1st 2025 --->
        if ($settings.PSObject.Properties.Name -eq 'alwaysBuildAllProjects' -and $settings.alwaysBuildAllProjects) {
            $buildAllProjects = $settings.alwaysBuildAllProjects
            Trace-DeprecationWarning -Message "alwaysBuildAllProjects is deprecated" -DeprecationTag "alwaysBuildAllProjects"
        }
        # <--- REMOVE AFTER October 1st 2025
        else {
            $buildAllProjects = !$settings.incrementalBuilds.onPull_Request
        }
        $publishSkippedProjects = $false
    }
    else {
        # onPush, onSchedule or onWorkflow_Dispatch
        if ($settings.incrementalBuilds.PSObject.Properties.Name -eq "on$GhEventName") {
            $buildAllProjects = !$settings.incrementalBuilds."on$GhEventName"
        }
    }
    return $buildAllProjects, $publishSkippedProjects
}

<#
.Synopsis
    Determines whether a full build is required.
.Outputs
    A boolean indicating whether a full build is required.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - No files were modified
    - The modified files contain a file that matches one of the fullBuildPatterns
#>
function Get-BuildAllProjects {
    param(
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The modified files", Mandatory = $false)]
        [string[]] $modifiedFiles = @(),
        [Parameter(HelpMessage = "Full build patterns", Mandatory = $false)]
        [string[]] $fullBuildPatterns = @()
    )

    $settings = $env:Settings | ConvertFrom-Json

    if (!$modifiedFiles) {
        Write-Host "No files modified, building everything"
        return $true
    }

    $fullBuildPatterns += @(Join-Path '.github' '*.json')
    if($settings.fullBuildPatterns) {
        $fullBuildPatterns += $settings.fullBuildPatterns
    }

    #Include the base folder in the modified files
    $modifiedFiles = @($modifiedFiles | ForEach-Object { return Join-Path $baseFolder $_ })

    foreach($fullBuildFolder in $fullBuildPatterns) {
        # The Join-Path is needed to make sure the path has the correct slashes
        $fullBuildFolder = Join-Path $baseFolder $fullBuildFolder

        if ($modifiedFiles -like $fullBuildFolder) {
            Write-Host "Changes to $fullBuildFolder, building everything"
            return $true
        }
    }

    Write-Host "No changes to fullBuildPatterns, not building everything"

    return $false
}

<#
.Synopsis
    Determines whether all apps in a project should be built
.Outputs
    A boolean indicating whether a full build is required.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - Get-BuildAllProjects returns true
    - The .AL-Go/settings.json file has been modified
#>
function Get-BuildAllApps {
    param(
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The project", Mandatory = $false)]
        [string] $project = '',
        [Parameter(HelpMessage = "The modified files", Mandatory = $false)]
        [string[]] $modifiedFiles = @()
    )

    if ($project) {
        $ALGoSettingsFile = @(Join-Path $project '.AL-Go/settings.json')
    }
    else {
        $ALGoSettingsFile = @('.AL-Go/settings.json')
    }
    return (Get-BuildAllProjects -baseFolder $baseFolder -modifiedFiles $modifiedFiles -fullBuildPatterns @($ALGoSettingsFile))
}

<#
.Synopsis
    Downloads unmodified artifacts from the baseline workflow run
.Description
    Downloads unmodified artifacts from the baseline workflow run
    - Downloads the artifacts (apps, testapps and bcpttestapps) for the specified project and build mode from the last known good build.
    - Copies the downloaded artifacts to the build artifact folder.
#>
function Get-UnmodifiedAppsFromBaselineWorkflowRun {
    Param(
        [Parameter(HelpMessage = "The GitHub token to use for downloading artifacts", Mandatory = $true)]
        [String] $token,
        [Parameter(HelpMessage = "The resolved AL-Go Project Settings", Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The current project", Mandatory = $false)]
        [string] $project = '',
        [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $true)]
        [string] $baselineWorkflowRunId,
        [Parameter(HelpMessage = "Array of modified files in the repository (all projects)", Mandatory = $true)]
        [string[]] $modifiedFiles,
        [Parameter(HelpMessage = "The build artifact folder", Mandatory = $true)]
        [string] $buildArtifactFolder,
        [Parameter(HelpMessage = "The build mode", Mandatory = $true)]
        [string] $buildMode,
        [Parameter(HelpMessage = "The project path", Mandatory = $true)]
        [string] $projectPath
    )

    $skipFolders = @()
    $unknownDependencies = @()
    $knownApps = @()
    $allFolders = @(GetFoldersFromAllProjects -baseFolder $baseFolder | ForEach-Object { $_.Replace('\', $([System.IO.Path]::DirectorySeparatorChar)).Replace('/', $([System.IO.Path]::DirectorySeparatorChar)) } )
    $modifiedFolders = @($allFolders | Where-Object {
        $modifiedFiles -like "$($_)$([System.IO.Path]::DirectorySeparatorChar)*"
    })
    OutputMessageAndArray -message "Modified folders" -arrayOfStrings $modifiedFolders
    Sort-AppFoldersByDependencies -appFolders $allFolders -baseFolder $baseFolder -skippedApps ([ref] $skipFolders) -unknownDependencies ([ref]$unknownDependencies) -knownApps ([ref] $knownApps) -selectSubordinates $modifiedFolders | Out-Null
    OutputMessageAndArray -message "Skip folders" -arrayOfStrings $skipFolders

    $projectWithSeperator = ''
    if ($project) {
        $projectWithSeperator = "$project$([System.IO.Path]::DirectorySeparatorChar)"
    }

    # AppFolders, TestFolders and BcptTestFolders in settings are always preceded by ./ or .\, so we need to remove that (hence Substring(2))
    $downloadAppFolders = @($settings.appFolders | Where-Object { $skipFolders -contains "$projectWithSeperator$($_.SubString(2))" })
    $downloadTestFolders = @($settings.testFolders | Where-Object { $skipFolders -contains "$projectWithSeperator$($_.SubString(2))" })
    $downloadBcptTestFolders = @($settings.bcptTestFolders | Where-Object { $skipFolders -contains "$projectWithSeperator$($_.SubString(2))" })

    OutputMessageAndArray -message "Download appFolders" -arrayOfStrings $downloadAppFolders
    OutputMessageAndArray -message "Download testFolders" -arrayOfStrings $downloadTestFolders
    OutputMessageAndArray -message "Download bcptTestFolders" -arrayOfStrings $downloadBcptTestFolders

    if ($project) { $projectName = $project } else { $projectName = $env:GITHUB_REPOSITORY -replace '.+/' }
    # Download missing apps - or add then to build folders if the artifact doesn't exist
    $appsToDownload = [ordered]@{
        "appFolders" = @{
            "Mask" = "Apps"
            "Downloads" = $downloadAppFolders
            "Downloaded" = 0
        }
        "testFolders" = @{
            "Mask" = "TestApps"
            "Downloads" = $downloadTestFolders
            "Downloaded" = 0
        }
        "bcptTestFolders" = @{
            "Mask" = "TestApps"
            "Downloads" = $downloadBcptTestFolders
            "Downloaded" = 0
        }
    }
    $additionalDataForTelemetry = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
    $appsToDownload.Keys | ForEach-Object {
        $appType = $_
        $mask = $appsToDownload."$appType".Mask
        $downloads = $appsToDownload."$appType".Downloads
        $thisArtifactFolder = Join-Path $buildArtifactFolder $mask
        if (!(Test-Path $thisArtifactFolder)) {
            New-Item $thisArtifactFolder -ItemType Directory | Out-Null
        }
        if ($downloads) {
            Write-Host "Downloading from $mask"
            $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            New-Item $tempFolder -ItemType Directory | Out-Null
            if ($buildMode -eq 'Default') {
                $artifactMask = $mask
            }
            else {
                $artifactMask = "$buildMode$mask"
            }
            $runArtifact = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $artifactMask -projects $projectName
            if ($runArtifact) {
                if ($runArtifact -is [Array]) {
                    throw "Multiple artifacts found with mask $artifactMask for project $projectName"
                }
                $file = DownloadArtifact -path $tempFolder -token $token -artifact $runArtifact
                $artifactFolder = Join-Path $tempFolder $mask
                Expand-Archive -Path $file -DestinationPath $artifactFolder -Force
                Remove-Item -Path $file -Force
                $downloads | ForEach-Object {
                    $appJsonPath = Join-Path $projectPath "$_/app.json"
                    $appJson = Get-Content -Encoding UTF8 -Path $appJsonPath -Raw | ConvertFrom-Json
                    $appName = ("$($appJson.Publisher)_$($appJson.Name)".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '') + "_*.*.*.*.app"
                    $appPath = Join-Path $artifactFolder $appName
                    if (Test-Path $appPath) {
                        $item = Get-Item -Path $appPath
                        Write-Host "Copy $($item.Name) to build folders"
                        Copy-Item -Path $item.FullName -Destination $thisArtifactFolder -Force
                        $appsToDownload."$appType".Downloaded++
                    }
                }
            }
            Remove-Item -Path $tempFolder -Recurse -force
        }
        $additionalDataForTelemetry.Add("$($appType)ToDownload", $appsToDownload."$appType".Downloads.Count)
        $additionalDataForTelemetry.Add("$($appType)Downloaded", $appsToDownload."$appType".Downloaded)
    }
    Trace-Information -Message "Incremental builds (apps)" -AdditionalData $additionalDataForTelemetry
}

Export-ModuleMember *-*
