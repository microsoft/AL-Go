Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [string[]] $dependencyProjects = @(),
    [array] $buildDimensions = @(),
    [string] $baseBranch,
    [string] $destinationPath
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
    $fetchBuildMode = $buildMode

    # Check if the dependency project is also built in the current workflow run with the same build mode
    $currentBuild = $buildDimensions | Where-Object { ($_.project -eq $dependencyProject) -and ($_.buildMode -eq $buildMode)  }

    if(!$currentBuild) {
        # Check if the dependency project is also built in the current workflow run with the default build mode
        $currentBuild = $buildDimensions | Where-Object { ($_.project -eq $dependencyProject) -and ($_.buildMode -eq 'Default')  }
    }
    
    if($currentBuild) {
        $fetchFrom = 'currentBuild'
        $fetchBuildMode = $currentBuild.buildMode
    }
    
    return @{
        dependencyProject = $dependencyProject
        buildMode = $fetchBuildMode
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
            Write-Host "Project '$dependencyProject' is also built in the current worfklow run with build mode $buildMode, fetching artifact from current build"

            Download-DependencyProjectArtifact -project $dependencyProject -buildMode $buildMode -workflowRunId $env:GITHUB_RUN_ID
        }
        'latestBuild' {
            Write-Host "Project '$dependencyProject' is not built in the current worfklow run, fetching artifact from latest build from branch '$baseBranch'"
        
            Download-DependencyProjectArtifact -project $dependencyProject -buildMode $buildMode -baseBranch $baseBranch
        }
    }
}

function Download-DependencyProjectArtifact {
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

    $buildModeMask = $buildMode
    if($buildMode -eq 'Default') {
        $buildModeMask = ''
    }

    if($workflowRunId) {
        $artifactName = "thisbuild-$($projectName)-$($buildModeMask)Apps"
        $fallbackArtifactName = "$($projectName)-Apps"
    } else {
        $artifactName = "$($projectName)-$($branchName)-$($buildMode)Apps-*"
        $artifactName = "$($projectName)-$($branchName)-Apps-*"
    }

    $token = $env:gitHubToken

    if(!$token) {
        $token = gh auth token
    }

    $token | gh auth login --with-token

    $page = 0
    $pageSize = 100
    $artifacts = @()

    do {
        $page++

        $res += (gh api `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2022-11-28" `
            /repos/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID/artifacts?per_page=$pageSize`&page=$page) | ConvertFrom-Json

        $artifacts += @($res.artifacts)
    } while ($artifacts.Count -eq ($page * $pageSize))

    $artifact = $artifacts | Where-Object { $_.name -like $artifactName }



    return $artifactsName
}

$fetchedArtifactsJson = ConvertTo-Json $fetchedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=$fetchedArtifactsJson"