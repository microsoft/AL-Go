Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project = '.'
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0082' -parentTelemetryScopeJson $parentTelemetryScopeJson

    . (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')

    $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\TestResults.xml"
    $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetTestResultSummaryMD -testResultsFile $testResultsFile

    $settings = $env:Settings | ConvertFrom-Json
    $bcptTestResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptTestResults.json"
    $bcptBaseLineFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptBaseLine.json"
    $bcptThresholdsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptThresholds.json"
    $bcptSummaryMD = GetBcptSummaryMD `
        -bcptTestResultsFile $bcptTestResultsFile `
        -baseLinePath $bcptBaseLineFile `
        -thresholdsPath $bcptThresholdsFile `
        -bcptThresholds ($settings.bcptThresholds | ConvertTo-HashTable)

    # If summary fits, we will display it in the GitHub summary
    if ($testResultsSummaryMD.Length -gt 65000) {
        # If Test results summary is too long, we will not display it in the GitHub summary, instead we will display a message to download the test results
        $testResultsSummaryMD = "<i>Test results summary size exceeds GitHub summary capacity. Download **TestResults** artifact to see details.</i>"
    }
    # If summary AND BCPT summary fits, we will display both in the GitHub summary
    if ($testResultsSummaryMD.Length + $bcptSummaryMD.Length -gt 65000) {
        # If Combined Test Results and BCPT summary exceeds GitHub summary capacity, we will not display the BCPT summary
        $bcptSummaryMD = "<i>Performance test results summary size exceeds GitHub summary capacity. Download **BcptTestResults** artifact to see details.</i>"
    }
    # If summary AND BCPT summary AND failures summary fits, we will display all in the GitHub summary
    if ($testResultsSummaryMD.Length + $testResultsfailuresMD.Length + $bcptSummaryMD.Length -gt 65000) {
        # If Combined Test Results, failures and BCPT summary exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
        $testResultsfailuresMD = $testResultsFailuresSummaryMD
    }

    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## Test results`n`n"
    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsSummaryMD.Replace("\n","`n"))`n`n"
    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsfailuresMD.Replace("\n","`n"))`n`n"
    if ($bcptSummaryMD) {
        Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## Performance test results`n`n"
        Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($bcptSummaryMD.Replace("\n","`n"))`n`n"
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }

    throw
}
