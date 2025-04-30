Param(
    [string] $token,
    [string] $project,
    [object] $settings,
    [string] $targetBranch,
    [string] $prBuildOutputFile
)

if (-not $ENV:GITHUB_BASE_REF)
{
    Write-Host "Checking for warnings only runs on pull requests."
    return
}

if (-not $settings.failOnNewWarnings)
{
    Write-Host "Failing on new warnings is disabled in the settings."
    return
}

try
{
    Write-Host "::group::Analyzing build for new warnings..."

    Import-Module (Join-Path $PSScriptRoot "..\Github-Helper.psm1" -Resolve) -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot ".\CheckForWarningsUtils.psm1" -Resolve) -DisableNameChecking

    $baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $targetBranch -token $token -retention $settings.incrementalBuilds.retentionDays
    if ($project) { $projectName = $project } else { $projectName = $env:GITHUB_REPOSITORY -replace '.+/' }

    $mask = Get-Item $prBuildOutputFile | Select-Object -ExpandProperty BaseName
    $artifact = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $mask -projects $projectName | Select-Object -First 1

    Write-Host "Downloading build logs from previous good build."

    $artifactsFolder = Join-Path $ENV:RUNNER_TEMP ".warnings"
    Initialize-Directory -Path $artifactsFolder
    DownloadArtifact -token $token -artifact $artifact -path $artifactsFolder -unpack

    "Done downloading artifacts." | Write-Host
    $referenceBuildLog = Get-ChildItem $artifactsFolder -File -Recurse | Select-Object -First 1

    Write-Host "Comparing build warnings between '$prBuildOutputFile' and '$($referenceBuildLog.FullName)'."
    Compare-Files -referenceBuild $referenceBuildLog.FullName -prBuild $prBuildOutputFile
}
finally
{
    Write-Host "::endgroup::Done analyzing build for new warnings..."
}




