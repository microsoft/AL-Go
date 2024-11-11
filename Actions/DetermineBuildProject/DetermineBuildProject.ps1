Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Compressed JSON string containing the list of projects that should be skipped", Mandatory = $true)]
    [string] $skippedProjectsJson,
    [Parameter(HelpMessage = "Name of the project to build", Mandatory = $true)]
    [string] $project,
    [Parameter(HelpMessage = "Id of the baseline workflow run, from which to download artifacts if build is skipped", Mandatory = $false)]
    [string] $baselineWorkflowRunId
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse

$skippedProjects = $skippedProjectsJson | ConvertFrom-Json
$buildIt = $skippedProjects -notcontains $project
if (!$buildIt) {
    # Download the artifacts from the baseline workflow run
    # Set buildIt to true if the download isn't successful
    $allArtifacts = @()
    'Apps','TestApps','Dependencies','PowerPlatformSolution' | ForEach-Object {
        $allArtifacts += @(GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $_ -projects $project)
    }
    if ($allArtifacts) {
        $allArtifacts | Out-Host
    }
    else {
        $buildIt = $true
    }
}

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildIt=$buildIt"
Write-Host "BuildIt=$buildIt"
