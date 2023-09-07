<#
.Synopsis
    Creates buils dimensions for a list of projects.

.Outputs
    An array of build dimensions for the projects and their corresponding build modes.
    Each build dimension is a hashtable with the following keys:
    - project: The name of the AL-Go project
    - buildMode: The build mode to use for the project
#>
function CreateBuildDimensions(
    [Parameter(HelpMessage = "A list of AL-Go projects for which to generate build dimensions")]
    $projects = @(),
    $baseFolder
)
{
    $buildDimensions = @()

    foreach($project in $projects) {
        $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
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
            }
        }
    }

    return @(, $buildDimensions) # force array
}

<#
.Synopsis
    Filters AL-Go projects based on modified files.

.Outputs
    An array of AL-Go projects to build.
#>
function Get-FilteredProjectsToBuild($settings, $projects, $baseFolder, $modifiedFiles) {
    if ($settings.alwaysBuildAllProjects) {
        Write-Host "Building all projects because alwaysBuildAllProjects is set to true"
        return $projects
    }

    if (!$modifiedFiles) {
        Write-Host "No files modified, building all projects"
        return $projects
    }

    Write-Host "$($modifiedFiles.Count) modified file(s): $($modifiedFiles -join ', ')"

    if ($modifiedFiles.Count -ge 250) {
        Write-Host "More than 250 files modified, building all projects"
        return $projects
    }

    $fullBuildPatterns = @( Join-Path '.github' '*.json')
    if($settings.fullBuildPatterns) {
        $fullBuildPatterns += $settings.fullBuildPatterns
    }

    #Include the base folder in the modified files
    $modifiedFiles = @($modifiedFiles | ForEach-Object { return Join-Path $baseFolder $_ })

    foreach($fullBuildFolder in $fullBuildPatterns) {
        # The Join-Path is needed to make sure the path has the correct slashes
        $fullBuildFolder = Join-Path $baseFolder $fullBuildFolder

        if ($modifiedFiles -like $fullBuildFolder) {
            Write-Host "Changes to $fullBuildFolder, building all projects"
            return $projects
        }
    }

    Write-Host "Filtering projects to build based on the modified files"

    $filteredProjects = @()
    foreach($project in $projects)
    {
        if (Test-Path -Path (Join-Path $baseFolder "$project/.AL-Go/settings.json")) {
            $projectFolders = GetProjectFolders -baseFolder $baseFolder -project $project -includeAlGoFolder

            $modifiedProjectFolders = @($projectFolders | Where-Object {
                $projectFolder = Join-Path $baseFolder "$_/*"

                return $($modifiedFiles -like $projectFolder)
            })

            if ($modifiedProjectFolders.Count -gt 0) {
                # The project has been modified, add it to the list of projects to build
                $filteredProjects += $project
            }
        }
    }

    return $filteredProjects
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
    - projectsToBuild: An array of projects that need to be built
    - projectDependencies: A hashtable with the project dependencies
    - projectsOrderToBuild: An array of build dimensions, each build dimension contains the following properties:
        - projects: An array of projects to build
        - projectsCount: The number of projects to build
        - buildDimensions: An array of build dimensions, to be used in a build matrix. Properties of the build dimension are:
            - project: The project to build
            - buildMode: The build mode to use
#>
function Get-ProjectsToBuild(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    $baseFolder,
    [Parameter(HelpMessage = "An array of changed files paths, used to filter the projects to build", Mandatory = $false)]
    $modifiedFiles = @(),
    [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
    $maxBuildDepth = 0
)
{
    Write-Host "Determining projects to build in $baseFolder"

    Push-Location $baseFolder

    try {
        $settings = $env:Settings | ConvertFrom-Json

        if ($settings.projects) {
            Write-Host "Projects specified in settings"
            $projects = $settings.projects
        }
        else {
            # Get all projects that have a settings.json file
            $projects = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })

            # If the repo has a settings.json file, add it to the list of projects to build
            if (Test-Path (Join-Path ".AL-Go" "settings.json") -PathType Leaf) {
                $projects += @(".")
            }
        }

        Write-Host "Found AL-Go Projects: $($projects -join ', ')"

        $projectsToBuild = @()
        $projectDependencies = @{}
        $projectsOrderToBuild = @()

        if ($projects) {
            $projectsToBuild += Get-FilteredProjectsToBuild -baseFolder $baseFolder -settings $settings -projects $projects -modifiedFiles $modifiedFiles

            if($settings.useProjectDependencies) {
                $buildAlso = @{}

                # Calculate the full projects order
                $fullProjectsOrder = AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects -buildAlso ([ref]$buildAlso) -projectDependencies ([ref]$projectDependencies)

                $projectsToBuild = @($projectsToBuild | ForEach-Object { $_; if ($buildAlso.Keys -contains $_) { $buildAlso."$_" } } | Select-Object -Unique)
            }
            else {
                # Use a flatten build order (all projects on the same level)
                $fullProjectsOrder = @(@{ 'projects' = $projectsToBuild; 'projectsCount' = $projectsToBuild.Count})
            }

            # Create a project order based on the projects to build
            foreach($depth in $fullProjectsOrder) {
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

        return $projects, $projectsToBuild, $projectDependencies, $projectsOrderToBuild
    }
    finally {
        Pop-Location
    }
}
