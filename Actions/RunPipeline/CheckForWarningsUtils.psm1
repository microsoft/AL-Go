<#
    .SYNOPSIS
    Ensures that a specified directory exists. If the directory does not exist, it creates it.
    .DESCRIPTION
    Ensures that a specified directory exists. If the directory does not exist, it creates it.
#>
function Initialize-Directory {
    [CmdletBinding()]
    param (
        [string] $Path
    )

    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory | Out-Null
    }
}

<#
    .SYNOPSIS
    This function parses a build log file and returns the AL warnings found in it.
    .DESCRIPTION
    This function parses a build log file and returns the AL warnings found in it.
#>
function Get-Warnings {
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param (
        [string] $BuildFile
    )

    $warnings = @()

    if (Test-Path $BuildFile) {
        Get-Content $BuildFile | ForEach-Object {
            if ($_  -match "::warning file=(.+),line=([0-9]{1,5}),col=([0-9]{1,5})::([A-Z]{2}[0-9]{4}) (.+)")
            {
                $warnings += New-Object -Type PSObject -Property @{
                    Id = $Matches[4]
                    File= $Matches[1]
                    Description = $Matches[5]
                    Line = $Matches[2]
                    Col = $Matches[3]
                }
            }
        }
    }

    return $warnings
}

<#
    .SYNOPSIS
    Compare 2 build logs and throw if new warnings were added.
    .DESCRIPTION
    Compare 2 build logs and throw if new warnings were added.
#>
function Compare-Files {
    [CmdletBinding()]
    param (
        [string] $referenceBuild,
        [string] $prBuild
    )

    $startTime = Get-Date
    $refWarnings =  @(Get-Warnings -BuildFile $referenceBuild)
    $prWarnings = @(Get-Warnings -BuildFile $prBuild)

    Write-Host "Found $($refWarnings.Count) warnings in reference build."
    Write-Host "Found $($prWarnings.Count) warnings in PR build."

    $delta = Compare-Object -ReferenceObject $refWarnings -DifferenceObject $prWarnings -Property Id,File,Description,Col -PassThru |
        Where-Object { $_.SideIndicator -eq "=>" } |
        Select-Object -Property Id,File,Description,Line,Col -Unique

    $delta | ForEach-Object {
            Write-Host "::error file=$($_.File),line=$($_.Line),col=$($_.Col)::New warning introduced in this PR: [$($_.Id)] $($_.Description)"
        }

    $secondsElapsed = ((Get-Date) - $startTime).TotalSeconds
    Trace-Information -Message "Checking for new warnings took $secondsElapsed seconds. Found $($refWarnings.Count) warnings in reference build and $($prWarnings.Count) warnings in PR build."

    if ($delta) {
        throw "New warnings were introduced in this PR."
    }
}

<#
    .SYNOPSIS
    Tests for new warnings in PR build.
    .DESCRIPTION
    If enabled, will fail if new warnings are found in the PR build compared to the baseline workflow run.
#>
function Test-ForNewWarnings {
    [CmdletBinding()]
    Param(
        [string] $token,
        [string] $project,
        [object] $settings,
        [string] $buildMode,
        [string] $prBuildOutputFile,
        [string] $baselineWorkflowRunId
    )

    function GetArtifactMask {
        param (
            [string] $buildOutputFile,
            [string] $buildMode
        )

        $mask = Get-Item $buildOutputFile | Select-Object -ExpandProperty BaseName
        if ($buildMode -ne 'Default') {
            $mask = "$buildMode$mask"
        }

        return $mask
    }

    function GetProjectName {
        param (
            [string] $project
        )

        if ($project) {
            return $project
        }
        else{
            return $env:GITHUB_REPOSITORY -replace '.+/'
        }
    }

    try {
        Write-Host "::group::Analyzing build for new warnings..."

        if (-not $ENV:GITHUB_BASE_REF) {
            Write-Host "Checking for warnings only runs on pull requests."
            return
        }

        if ($settings.failOn -ne 'newWarning') {
            Write-Host "Checking for new warnings is not enabled in the settings."
            return
        }

        Import-Module (Join-Path $PSScriptRoot "..\Github-Helper.psm1" -Resolve) -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking

        Trace-Information -Message "Analyzing build logs for new warnings."
        Write-Host "Downloading build logs from previous good build."

        $mask = GetArtifactMask -buildOutputFile $prBuildOutputFile -buildMode $buildMode
        $projectName = GetProjectName -project $project

        Write-Host "Downloading build output for project '$projectName' with mask '$mask'."
        $artifact = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $mask -projects $projectName | Select-Object -First 1

        if (-not $artifact){
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
    finally{
        Write-Host "::endgroup::Done analyzing build for new warnings..."
    }
}

Export-ModuleMember -Function Test-ForNewWarnings
