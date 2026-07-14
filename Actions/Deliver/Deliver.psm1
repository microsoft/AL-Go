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

Export-ModuleMember -Function Get-ProjectsInDeliveryOrder
