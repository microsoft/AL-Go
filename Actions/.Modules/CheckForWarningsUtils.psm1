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
    Normalizes a warning description so that volatile substrings do not cause false "new warning" hits.
    .DESCRIPTION
    Some AL diagnostics embed a build version in their message text (e.g. AL0523 references another
    app as 'Base Application by Microsoft (29.0.2147483647.75450)'). Because AL-Go stamps the build
    and revision numbers from the workflow run number, that version differs between the baseline build
    and the pull request build, which would make an otherwise unchanged warning look new. This function
    replaces any four-part version number (major.minor.build.revision) with a stable placeholder so the
    comparison is not affected by build-to-build version differences.
#>
function Get-NormalizedWarningDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string] $Description
    )

    return [regex]::Replace($Description, '\d+\.\d+\.\d+\.\d+', '{version}')
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

    # Warnings appear in one of two formats depending on the compilation method. Both patterns capture
    # the same groups in the same order: 1=File, 2=Line, 3=Col, 4=Id, 5=Description.
    #   Container/compiler-folder: ::warning file=<file>,line=<line>,col=<col>::<Id> <description>
    #   Workspace compilation:     <file>(<line>,<col>): warning <Id>: <description>
    $warningPatterns = @(
        "::warning file=(.+),line=([0-9]{1,5}),col=([0-9]{1,5})::([A-Z]{2}[0-9]{4}) (.+)",
        "^(.+)\(([0-9]{1,7}),([0-9]{1,7})\): warning ([A-Z]{2}[0-9]{4}): (.+)$"
    )

    if (Test-Path $BuildFile) {
        Get-Content $BuildFile | ForEach-Object {
            $line = $_
            foreach ($pattern in $warningPatterns) {
                if ($line -match $pattern) {
                    $warnings += New-Object -Type PSObject -Property @{
                        Id = $Matches[4]
                        File = $Matches[1]
                        Description = $Matches[5]
                        NormalizedDescription = (Get-NormalizedWarningDescription -Description $Matches[5])
                        Line = $Matches[2]
                        Col = $Matches[3]
                    }
                    break
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

    $delta = Compare-Object -ReferenceObject $refWarnings -DifferenceObject $prWarnings -Property Id,File,NormalizedDescription,Col -PassThru |
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
