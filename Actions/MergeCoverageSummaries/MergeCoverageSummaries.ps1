Param(
    [Parameter(HelpMessage = "Path containing downloaded coverage artifacts", Mandatory = $true)]
    [string] $coveragePath,
    [Parameter(HelpMessage = "Path to source code checkout", Mandatory = $false)]
    [string] $sourcePath = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\BuildCodeCoverageSummary\CoverageReportGenerator.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "CoberturaMerger.psm1" -Resolve) -Force -DisableNameChecking

if (-not (Test-Path $coveragePath)) {
    Write-Host "No coverage artifacts found at: $coveragePath"
    Write-Host "Skipping coverage merge."
    return
}

# Find all cobertura.xml files in subdirectories (each artifact is in its own subfolder)
$coberturaFiles = @(Get-ChildItem -Path $coveragePath -Filter "cobertura.xml" -Recurse -File)

if ($coberturaFiles.Count -eq 0) {
    Write-Host "No cobertura.xml files found under: $coveragePath"
    return
}

Write-Host "Found $($coberturaFiles.Count) coverage file(s) to merge:"
$coberturaFiles | ForEach-Object {
    $artifactName = (Split-Path (Split-Path $_.FullName -Parent) -Leaf)
    Write-Host "  [$artifactName] $($_.FullName)"
}

# Always write to _merged/ directory so the workflow upload step finds the file
$mergedOutputDir = Join-Path $coveragePath "_merged"
$mergedFile = Join-Path $mergedOutputDir "cobertura.xml"

if ($coberturaFiles.Count -eq 1) {
    Write-Host "Only one coverage file found, copying to merged output (no merge needed)"
    if (-not (Test-Path $mergedOutputDir)) {
        New-Item -ItemType Directory -Path $mergedOutputDir -Force | Out-Null
    }
    Copy-Item -Path $coberturaFiles[0].FullName -Destination $mergedFile -Force
} else {
    Merge-CoberturaFiles `
        -CoberturaFiles ($coberturaFiles.FullName) `
        -OutputPath $mergedFile | Out-Null
}

# Merge stats.json files for metadata (app source paths, excluded objects)
$statsFiles = @(Get-ChildItem -Path $coveragePath -Filter "cobertura.stats.json" -Recurse -File)
$mergedStats = $null
if ($statsFiles.Count -gt 0) {
    $mergedStats = Merge-CoverageStats -StatsFiles ($statsFiles.FullName)

    # Save merged stats alongside merged cobertura
    $mergedStatsFile = [System.IO.Path]::ChangeExtension($mergedFile, '.stats.json')
    $mergedStats | ConvertTo-Json -Depth 10 | Set-Content -Path $mergedStatsFile -Encoding UTF8
    Write-Host "Saved merged stats to: $mergedStatsFile"
}

# Generate consolidated coverage summary
Write-Host "`nGenerating consolidated coverage summary..."
$coverageResult = Get-CoverageSummaryMD -CoverageFile $mergedFile

if ($coverageResult.SummaryMD) {
    # Helper function to calculate byte size
    function GetStringByteSize($string) {
        return [System.Text.Encoding]::UTF8.GetBytes($string).Length
    }

    $header = "## :bar_chart: Code Coverage - Consolidated`n`n"
    $inputInfo = ":information_source: Merged from **$($coberturaFiles.Count)** build job(s)`n`n"

    # Warn if build had failures (some jobs may not have produced coverage data)
    $incompleteWarning = ""
    if ($env:_BUILD_RESULT -eq 'failure') {
        $incompleteWarning = "> :warning: **Incomplete coverage data** - some build jobs failed and did not produce coverage results. Actual coverage may be higher than reported.`n`n"
        OutputWarning -message "Coverage data is incomplete - some build jobs failed and did not produce coverage results."
    }
    $headerSize = GetStringByteSize($header)
    $inputInfoSize = GetStringByteSize($inputInfo)
    $warningSize = GetStringByteSize($incompleteWarning)
    $summarySize = GetStringByteSize($coverageResult.SummaryMD)
    $detailsSize = GetStringByteSize($coverageResult.DetailsMD)

    # GitHub job summaries are limited to just under 1MB
    $coverageSummaryMD = $coverageResult.SummaryMD
    $coverageDetailsMD = $coverageResult.DetailsMD

    if ($headerSize + $inputInfoSize + $warningSize + $summarySize -gt (1MB - 4)) {
        $coverageSummaryMD = "<i>Coverage summary size exceeds GitHub summary capacity.</i>"
        $summarySize = GetStringByteSize($coverageSummaryMD)
    }
    if ($headerSize + $inputInfoSize + $warningSize + $summarySize + $detailsSize -gt (1MB - 4)) {
        $coverageDetailsMD = "<i>Coverage details truncated due to size limits.</i>"
    }

    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value $header
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value $inputInfo
    if ($incompleteWarning) {
        Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value $incompleteWarning
    }
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "$($coverageSummaryMD.Replace("\n","`n"))`n`n"
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "$($coverageDetailsMD.Replace("\n","`n"))`n`n"

    Write-Host "Coverage summary written to GITHUB_STEP_SUMMARY"
}
