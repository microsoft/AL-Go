Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [string[]] $dependencyProjects = @(),
    [array] $buildDimensions = @(),
    [string] $BaseVersion
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

Write-Host "Fetching dependencies for project '$project'. Dependencies: $($dependencyProjects -join ', '), BuildMode: $buildMode, BaseVersion: $BaseVersion"

if(!$dependencyProjects -or $dependencyProjects.Count -eq 0) {
    Write-Host "No dependencies to fetch for project '$project'"

    Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=[]"
    return
}

$fetchedArtifacts= @()

# Determine if we need to fetch the artifact from the current build or from the latest build on the same branch
$fetchArtifacts= @( $dependencyProjects | ForEach-Object {
    $dependencyProject = $_
    $fetchFrom = 'latestBuild'

    $buildDimensions | ForEach-Object {
        $buildDimension = $_
        if($buildDimension.project -eq $dependencyProject) {
            # The dependency project is also built in the current workflow run
            $fetchFrom = 'currentBuild'
        }
    }
    
    return @{
        dependencyProject = $dependencyProject
        buildMode = $buildMode
        fetchFrom = $fetchFrom
    }
})

# Fetch the artifacts
foreach($fetchArtifact in $fetchArtifacts) {
    $dependencyProject = $fetchArtifact.dependencyProject
    $buildMode = $fetchArtifact.buildMode
    $fetchFrom = $fetchArtifact.fetchFrom
    
    switch ($fetchFrom) {
        'currentBuild' {
            Write-Host "Project '$dependencyProject' is also built in the current worfklow run, fetching artifact from current build"

            # Verify that the artifact is available
        }
        'latestBuild' {
            Write-Host "Project '$dependencyProject' is not built in the current worfklow run, fetching artifact from latest build with base version $BaseVersion"
        }
    }
}

$fetchedArtifactsJson = ConvertTo-Json $fetchedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=$fetchedArtifactsJson"