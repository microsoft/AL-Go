Param(
    [string] $token,
    [string] $project,
    [object] $settings,
    [string] $targetBranch,
    [string] $prBuildOutputFile
)

if (-not $settings.checkForNewWarnings)
{
    Write-Host "Checking for new warnings is disabled in the settings."
    return
}

Write-Host "Analyzing PR build for new warnings..."

Import-Module (Join-Path $PSScriptRoot "..\Github-Helper.psm1" -Resolve) -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot ".\CheckForWarningsUtils.psm1" -Resolve) -DisableNameChecking

$baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $targetBranch -token $token -retention $settings.incrementalBuilds.retentionDays
if ($project) { $projectName = $project } else { $projectName = $env:GITHUB_REPOSITORY -replace '.+/' }
    
$mask = Get-Item $prBuildOutputFile | Select-Object -ExpandProperty BaseName 
$artifacts = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $mask -projects $projectName

Write-Host "Downloading build logs from previous good build."

$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".warnings"
Initialize-Directory -Path $artifactsFolder

$artifacts | ForEach-Object {

    DownloadArtifact -token $token -artifact $_ -path $artifactsFolder -unpack

    "Done downloading artifacts." | Write-Host
    $referenceBuildLog = Get-ChildItem $artifactsFolder -File -Recurse | Select-Object -First 1   # I should check based on the name of $prBuildoutputFile

    Write-Host "Comparing build warnings between '$prBuildOutputFile' and '$($referenceBuildLog.FullName)'."

    $refWarnings =  @(Get-Warnings -BuildFile $referenceBuildLog.FullName)
    $prWarnings = @(Get-Warnings -BuildFile $prBuildOutputFile)

    Write-Host "Found $($refWarnings.Count) warnings in reference build."
    Write-Host "Found $($prWarnings.Count) warnings in PR build."
}
