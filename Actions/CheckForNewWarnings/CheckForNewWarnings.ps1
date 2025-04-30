Param(
    [string] $token,
    [string] $project,
    [object] $settings,
    [string] $targetBranch,
    [string] $buildMode,
    [string] $prBuildOutputFile,
    [string] $baselineWorkflowRunId
)

function GetArtifactMask
{
    param (
        [string] $buildOutputFile,
        [string] $buildMode
    )

    $mask = Get-Item $prBuildOutputFile | Select-Object -ExpandProperty BaseName
    if ($buildMode -ne 'Default')
    {
        $mask = "$buildMode$mask"
    }

    return $mask
}

function GetProjectName
{
    param (
        [string] $project
    )

    if ($project)
    {
        return $project
    }
    else
    {
        return $env:GITHUB_REPOSITORY -replace '.+/' 
    }
}

try
{
    Write-Host "::group::Analyzing build for new warnings..."

    if (-not $ENV:GITHUB_BASE_REF)
    {
        Write-Host "Checking for warnings only runs on pull requests."
        return
    }

    if (-not $settings.failOnNewWarnings)
    {
        Write-Host "Checking for new warnings is not enabled in the settings."
        return
    }

    Import-Module (Join-Path $PSScriptRoot "..\Github-Helper.psm1" -Resolve) -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot ".\CheckForWarningsUtils.psm1" -Resolve) -DisableNameChecking

    Write-Host "Downloading build logs from previous good build."

    $mask = GetArtifactMask -buildOutputFile $prBuildOutputFile -buildMode $buildMode
    $projectName = GetProjectName -project $project

    Write-Host "Downloading build output for project '$projectName' with mask '$mask'."
    $artifact = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $mask -projects $projectName | Select-Object -First 1

    if (-not $artifact)
    {
        Write-Host "No artifacts found for project '$projectName', skipping check for new warnings."
        return
    }

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
