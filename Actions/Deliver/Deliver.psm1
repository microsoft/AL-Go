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
Downloads the artifacts to deliver for a single project into the artifacts folder

.DESCRIPTION
Downloads the artifacts matching the requested version into the artifacts folder.
The version can be a release indicator (current, prerelease or draft), latest or a version number.
If 'current' is requested and the repository doesn't contain any releases, the artifacts from the
latest build are used instead - the same fallback as the one used when deploying to an environment.

.PARAMETER Token
The GitHub token used for accessing releases and artifacts

.PARAMETER Artifacts
The version of the artifacts to download (current, prerelease, draft, latest or a version number)

.PARAMETER ArtifactsFolder
The folder in which the artifacts are downloaded and unpacked

.PARAMETER Project
The name of the project (as used in artifact names)

.PARAMETER Atypes
Comma separated list of artifact types to download (f.ex. Apps,Dependencies,TestApps)

.PARAMETER Branch
The branch from which to get build artifacts

.OUTPUTS
The project name as used in the names of the downloaded artifact folders
#>
function Get-ArtifactsForDelivery {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $Token,

        [Parameter(Mandatory = $true)]
        [string] $Artifacts,

        [Parameter(Mandatory = $true)]
        [string] $ArtifactsFolder,

        [Parameter(Mandatory = $true)]
        [string] $Project,

        [Parameter(Mandatory = $true)]
        [string] $Atypes,

        [Parameter(Mandatory = $true)]
        [string] $Branch
    )

    $searchArtifacts = $false
    $searchArtifactsVersion = $Artifacts
    if ($Artifacts -eq '.artifacts') {
        # Artifacts from this build have already been downloaded
    }
    elseif ($Artifacts -eq "current" -or $Artifacts -eq "prerelease" -or $Artifacts -eq "draft") {
        # latest released version
        $releases = GetReleases -token $Token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        if ($releases) {
            if ($Artifacts -eq "current") {
                $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
            }
            elseif ($Artifacts -eq "prerelease") {
                $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
            }
            else {
                $release = $releases | Select-Object -First 1
            }
            if (!($release)) {
                throw "Unable to locate $Artifacts release"
            }
            # project is the project name as used in release asset names
            $Project = [Uri]::EscapeDataString($Project.Replace(' ', '.')).Replace('%', '')
            foreach ($mask in $Atypes.Split(',')) {
                $artifactFile = DownloadRelease -token $Token -projects $Project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $ArtifactsFolder -mask $mask
                Write-Host "'$artifactFile'"
                if (!$artifactFile -or !(Test-Path $artifactFile)) {
                    if ($mask -eq 'Apps') {
                        throw "Artifact $Artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
                    }
                }
                else {
                    if ($artifactFile -notlike '*.zip') {
                        throw "Downloaded artifact is not a .zip file"
                    }
                    Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0, $artifactFile.Length - 4))
                    Remove-Item $artifactFile -Force
                }
            }
        }
        elseif ($Artifacts -eq "current") {
            # No releases exist in the repository - fall back to the artifacts from the latest build
            Write-Host "::Warning::Current release was specified, but no releases were found. Searching for latest build artifacts instead."
            $searchArtifactsVersion = "latest"
            $searchArtifacts = $true
        }
        else {
            throw "Artifact $Artifacts was not found on any release."
        }
    }
    else {
        $searchArtifacts = $true
    }

    if ($searchArtifacts) {
        foreach ($atype in $Atypes.Split(',')) {
            $allArtifacts = @(GetArtifacts -token $Token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $atype -projects $Project -version $searchArtifactsVersion -branch $Branch)
            if ($allArtifacts) {
                foreach ($artifact in $allArtifacts) {
                    $artifactFile = DownloadArtifact -token $Token -artifact $artifact -path $ArtifactsFolder
                    Write-Host $artifactFile
                    if (!(Test-Path $artifactFile)) {
                        throw "Unable to download artifact $($artifact.name)"
                    }
                    if ($artifactFile -notlike '*.zip') {
                        throw "Downloaded artifact is not a .zip file"
                    }
                    Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0, $artifactFile.Length - 4))
                    Remove-Item $artifactFile -Force
                }
            }
            else {
                if ($atype -eq "Apps") {
                    throw "ERROR: Could not find any $atype artifacts for project $Project, version $searchArtifactsVersion"
                }
                else {
                    Write-Host "WARNING: Could not find any $atype artifacts for project $Project, version $searchArtifactsVersion"
                }
            }
        }
    }

    return $Project
}

Export-ModuleMember -Function Get-ProjectsInDeliveryOrder, Get-ArtifactsForDelivery
