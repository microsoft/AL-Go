function Get-FilteredProjectsToBuild($settings, $projects, $baseFolder, $modifiedFiles) {
    if ($settings.alwaysBuildAllProjects) {
        Write-Host "Building all projects because alwaysBuildAllProjects is set to true"
        return $projects
    } 

    if (!$modifiedFiles) {
        Write-Host "No files modified, building all projects"
        return $projects
    }

    if ($modifiedFiles -like '.github/*.json') {
        Write-Host "Changes to repo Settings, building all projects"
        return $projects
    }
    
    if ($modifiedFiles.Count -ge 250) {
        Write-Host "More than 250 files modified, building all projects"
        return $projects
    }

    Write-Host "$($modifiedFiles.Count) modified file(s): $($modifiedFiles -join ', ')"

    Write-Host "Filtering projects to build based on the modified files"

    $filteredProjects = @($projects | Where-Object {
            $checkProject = $_
            $buildProject = $false
            if (Test-Path -Path (Join-Path $baseFolder "$checkProject/.AL-Go/settings.json")) {
                $projectFolders = Get-ProjectFolders -baseFolder $baseFolder -project $checkProject -includeAlGoFolder

                $projectFolders | ForEach-Object {
                    if ($modifiedFiles -like "$_/*") { $buildProject = $true }
                }
            }
            $buildProject
        })

    return $filteredProjects
}

function Get-ProjectsToBuild(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    $baseFolder,
    [Parameter(HelpMessage = "An array of changed files paths, used to filter the projects to build", Mandatory = $false)]
    $modifiedFiles = @()
) 
{
    Write-Host "Determining projects to build in $baseFolder"
    
    Push-Location $baseFolder

    try {
        $settings = ReadSettings -baseFolder $baseFolder -project '.' # Read AL-Go settings for the repo
        
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
                    $buildDimensions = New-BuildDimensions -baseFolder $baseFolder -projects $projectsOnDepth
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

        return $projects, $projectsToBuild, $projectDependencies, $projectsOrderToBuild
    }
    finally {
        Pop-Location
    }
}
