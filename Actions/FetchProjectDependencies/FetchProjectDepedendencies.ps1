Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [string[]] $dependecyProjects = @(),
    [array] $buildDimensions = @(),
    [string] $baseBranch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$fetchedArtifacts= @()
$fetchArtifacts= @()

Write-Host "Fetching dependencies for project '$project'"

if(!$dependecyProjects -or $dependecyProjects.Count -eq 0) {
    Write-Host "No dependencies to fetch for project '$project'"
}
else {
    # Determine if we need to fetch the artifact from the current build or from the latest build on the same branch
    $dependecyProjects | ForEach-Object {
        $dependencyProject = $_
        $fetchFrom = 'latestBuild'

        $buildDimensions | ForEach-Object {
            $buildDimension = $_
            if($buildDimension.project -eq $dependencyProject) {
                $fetchFrom = 'currentBuild'
            }
        }
        
        $fetchArtifacts += @{
            dependencyProject = $dependencyProject
            buildMode = $buildMode
            fetchFrom = $fetchFrom
        }
    }

    # Fetch the artifacts
    foreach($fetchArtifact in $fetchArtifacts) {
        $dependencyProject = $fetchArtifact.dependencyProject
        $buildMode = $fetchArtifact.buildMode
        $fetchFrom = $fetchArtifact.fetchFrom
        
        switch ($fetchFrom) {
            'currentBuild' {
                Write-Host "Project '$dependencyProject' is also built in the current worfklow run, fetching artifact from current build"
            }
            'latestBuild' {
                Write-Host "Project '$dependencyProject' is not built in the current worfklow run, fetching artifact from latest build on branch $baseBranch"
            }
        }
    }
}

$fetchedArtifactsJson = ConvertTo-Json $fetchedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=$fetchedArtifactsJson"