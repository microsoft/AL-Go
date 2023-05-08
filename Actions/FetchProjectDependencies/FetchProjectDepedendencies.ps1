Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [string[]] $dependencyProjects = @(),
    [array] $buildDimensions = @(),
    [string] $baseBranch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

Write-Host "Fetching dependencies for project '$project'. Dependencies: $($dependencyProjects -join ', '), BuildMode: $buildMode, BaseBranch: $baseBranch"

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

            Deownload-DependencyProjectArtifact -project $dependencyProject -buildMode $buildMode -workflowRunId $env:GITHUB_RUN_ID
        }
        'latestBuild' {
            Write-Host "Project '$dependencyProject' is not built in the current worfklow run, fetching artifact from latest build from branch '$baseBranch'"
        
            Deownload-DependencyProjectArtifact -project $dependencyProject -buildMode $buildMode -baseBranch $baseBranch
        }
    }
}
function Deownload-DependencyProjectArtifact {
    pparam(
        [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
        [string] $project,
        [string] $buildMode = 'Default',
        [Parameter(ParameterSetName = 'WorkflowRunId')]
        [string] $workflowRunId,
        [Parameter(ParameterSetName = 'BaseBranch')]
        [string] $baseBranch
    )
    
    $projectName = $project.Replace('\','_').Replace('/','_')
    $branchName = $baseBranch.Replace('\','_').Replace('/','_')

    if($workflowRunId) {
        $artifactName = "thisbuild-$($projectName)-$($buildMode)Apps"
    } else {
        $artifactName = "$($projectName)-$($branchName)-$($buildMode)Apps-*"
    }

    return $artifactsName
}

$fetchedArtifactsJson = ConvertTo-Json $fetchedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=$fetchedArtifactsJson"