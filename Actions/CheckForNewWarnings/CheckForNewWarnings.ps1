Param(
    [string] $token,
    [string] $project,
    [object] $settings,
    [string] $targetBranch,
    [string] $prBuildOutputFile
)

Write-Host "Analyzing PR build for new warnings..."

Import-Module (Join-Path $PSScriptRoot "..\Github-Helper.psm1" -Resolve) -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot ".\CheckForWarningsUtils.psm1" -Resolve) -DisableNameChecking

$baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $targetBranch -token $token -retention $settings.incrementalBuilds.retentionDays
if ($project) { $projectName = $project } else { $projectName = $env:GITHUB_REPOSITORY -replace '.+/' }
    
$mask = "BuildOutput"  # todo - figure out name of build output file dynmically
$artifacts = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $mask -projects $projectName

Write-Host "Downloading build logs from previous good build."

$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".warnings"
Initialize-Directory -Path $artifactsFolder

$artifacts | ForEach-Object {

    DownloadArtifact -token $token -artifact $_ -path $artifactsFolder -unpack

    "Done downloading artifacts." | Write-Host
    $referenceBuildLog = Get-ChildItem $artifactsFolder -File -Recurse | Select-Object -First 1

    Write-Host "Comparing build warnings between '$prBuildOutputFile' and '$referenceBuildLog'."
}
