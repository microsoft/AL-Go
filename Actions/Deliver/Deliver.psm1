. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

<#
.SYNOPSIS
Get projects in dependency order for delivery

.DESCRIPTION
Retrieves projects from the repository and returns them sorted in dependency order,
ensuring that base projects are delivered before dependent projects.

.PARAMETER BaseFolder
The base folder of the repository

.PARAMETER ProjectsFromSettings
Projects specified in settings

.PARAMETER SelectProjects
Projects to select (supports wildcards, default is "*" for all projects)

.OUTPUTS
Array of project paths sorted by dependency order
#>
function Get-ProjectsInDeliveryOrder {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $BaseFolder,

        [Parameter(Mandatory = $false)]
        [string[]] $ProjectsFromSettings = @(),

        [Parameter(Mandatory = $false)]
        [string] $SelectProjects = "*"
    )

    # Get the list of projects from the repository
    $projectList = @(GetProjectsFromRepository -baseFolder $BaseFolder -projectsFromSettings $ProjectsFromSettings -selectProjects $SelectProjects)

    if ($projectList.Count -eq 0) {
        return @()
    }

    if ($projectList.Count -eq 1) {
        return $projectList
    }

    # Analyze project dependencies to determine build order
    $projectBuildInfo = AnalyzeProjectDependencies -baseFolder $BaseFolder -projects $projectList

    # Flatten the build order into a single sorted list
    $sortedProjectList = @()
    foreach($buildOrder in $projectBuildInfo.FullProjectsOrder) {
        $sortedProjectList += $buildOrder.projects
    }

    return $sortedProjectList
}

<#
.SYNOPSIS
Select library app files for an AppSource submission.

.DESCRIPTION
Keeps the highest version of each library app, identified by its app ID.
Excludes packages with the main app's ID and preserves the first package when versions are equal.

.PARAMETER appFile
The main app package being submitted.

.PARAMETER libraryAppFiles
Library app packages from the project's apps and included dependencies.

.OUTPUTS
Paths to library app packages with unique app IDs.
#>
function Get-AppSourceLibraryAppFile {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $appFile,

        [string[]] $libraryAppFiles = @()
    )

    $mainAppId = [guid](Get-AppJsonFromAppFile -appFile $appFile).id
    $selectedApps = [ordered]@{}
    foreach ($libraryAppFile in $libraryAppFiles) {
        $appJson = Get-AppJsonFromAppFile -appFile $libraryAppFile
        $appId = ([guid]$appJson.id).ToString()
        if ([guid]$appId -eq $mainAppId) {
            continue
        }

        $appVersion = [version]$appJson.version
        if (!$selectedApps.Contains($appId) -or $appVersion -gt $selectedApps[$appId].version) {
            $selectedApps[$appId] = @{
                path = $libraryAppFile
                version = $appVersion
            }
        }
    }

    $selectedApps.Values | ForEach-Object { $_.path }
}

Export-ModuleMember -Function Get-ProjectsInDeliveryOrder, Get-AppSourceLibraryAppFile
