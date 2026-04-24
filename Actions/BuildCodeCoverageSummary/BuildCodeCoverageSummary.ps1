Param(
    [Parameter(HelpMessage = "Project to analyze coverage for", Mandatory = $false)]
    [string] $project = '.'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "CoverageReportGenerator.ps1" -Resolve)

$coverageSummaryMD = ''
$coverageDetailsMD = ''

# Find Cobertura coverage file in .buildartifacts folder
$coverageFile = Join-Path $ENV:GITHUB_WORKSPACE "$project/.buildartifacts/CodeCoverage/cobertura.xml"

if (-not (Test-Path -Path $coverageFile -PathType Leaf)) {
    Write-Host "No coverage file found at: $coverageFile"
    Write-Host "Skipping coverage summary generation."
    return
}

Write-Host "Processing coverage file: $coverageFile"

# Generate coverage summary markdown
$coverageResult = Get-CoverageSummaryMD -CoverageFile $coverageFile
$coverageSummaryMD = $coverageResult.SummaryMD
$coverageDetailsMD = $coverageResult.DetailsMD

# Helper function to calculate byte size
function GetStringByteSize($string) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($string)
    return $bytes.Length
}

$titleSize = GetStringByteSize("## Code Coverage`n`n")
$summarySize = GetStringByteSize("$($coverageSummaryMD.Replace("\n","`n"))`n`n")
$detailsSize = GetStringByteSize("$($coverageDetailsMD.Replace("\n","`n"))`n`n")

# GitHub job summaries are limited to just under 1MB
if ($coverageSummaryMD) {
    if ($titleSize + $summarySize -gt (1MB - 4)) {
        $coverageSummaryMD = "<i>Coverage summary size exceeds GitHub summary capacity. Download **CodeCoverage** artifact to see details.</i>"
        $summarySize = GetStringByteSize($coverageSummaryMD)
    }
    if ($titleSize + $summarySize + $detailsSize -gt (1MB - 4)) {
        # Truncate details if too long
        $coverageDetailsMD = "<i>Coverage details truncated due to size limits.</i>"
    }

    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "## Code Coverage`n`n"
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "$($coverageSummaryMD.Replace("\n","`n"))`n`n"
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "$($coverageDetailsMD.Replace("\n","`n"))`n`n"
}
