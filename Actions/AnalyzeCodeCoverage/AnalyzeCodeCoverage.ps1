<#
.SYNOPSIS
    Creates a focused project or repository code coverage job summary.
.PARAMETER scope
    Summary scope. Supported values are project and repository.
.PARAMETER project
    Project folder used for project-scope settings and display.
.PARAMETER coveragePath
    Path containing the coverage-status.json file or downloaded coverage artifacts.
.PARAMETER buildOrderJson
    Build order JSON containing expected repository coverage dimensions.
#>
Param(
    [Parameter(HelpMessage = "Coverage summary scope (project or repository)", Mandatory = $true)]
    [ValidateSet("project", "repository")]
    [string] $scope,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Path containing downloaded code coverage artifacts", Mandatory = $true)]
    [string] $coveragePath,
    [Parameter(HelpMessage = "Build order JSON used to determine expected repository coverage artifacts", Mandatory = $false)]
    [string] $buildOrderJson = "[]"
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot "AnalyzeCodeCoverage.psm1" -Resolve) -Force -DisableNameChecking

function Write-CoverageAnalysisDetails {
    Param([hashtable] $Model)

    $details = @($Model.Reasons) + @($Model.LineReasons) + @($Model.Notices)
    foreach ($detail in @($details | Select-Object -Unique)) {
        Write-Host "Code coverage analysis detail: $detail"
    }
}

$workspace = $env:GITHUB_WORKSPACE
if ([string]::IsNullOrWhiteSpace($workspace)) {
    $workspace = (Get-Location).Path
}

$resolvedCoveragePath = $coveragePath
if (-not [System.IO.Path]::IsPathRooted($resolvedCoveragePath)) {
    $resolvedCoveragePath = Join-Path $workspace $resolvedCoveragePath
}

$writeSummary = $true
if ($scope -eq "project") {
    $settings = @{}
    if (-not [string]::IsNullOrWhiteSpace($env:Settings)) {
        try {
            $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
        }
        catch {
            Write-Host "::Warning::Code coverage summary settings could not be read. The project summary will be skipped."
            $writeSummary = $false
        }
    }
    else {
        $writeSummary = $false
    }

    if ($writeSummary) {
        $writeSummary = Test-CodeCoverageSummaryRequested -Settings $settings -Scope "project"
    }
    if ($writeSummary) {
        $model = Get-ProjectCoverageModel -CoveragePath $resolvedCoveragePath `
            -Project $project -RepositoryRoot $workspace
        Write-CoverageAnalysisDetails -Model $model
        $summary = New-ProjectCoverageSummary -Model $model
    }
}
else {
    $model = Get-RepositoryCoverageModel -CoveragePath $resolvedCoveragePath `
        -BuildOrderJson $buildOrderJson -RepositoryRoot $workspace
    Write-CoverageAnalysisDetails -Model $model
    $summary = New-RepositoryCoverageSummary -Model $model
}

if ($writeSummary) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        Write-Host "::Warning::GITHUB_STEP_SUMMARY is not set. The code coverage summary could not be appended."
    }
    else {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding UTF8
    }
}
else {
    Write-Host "Code coverage summary is not requested for scope '$scope'."
}
