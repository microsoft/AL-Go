Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0082' -parentTelemetryScopeJson $parentTelemetryScopeJson

    . (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')

    $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\TestResults.xml"
    $testResultsSummaryMD, $testResultsfailuresMD, $failuresSummaryMD = GetTestResultSummaryMD -path $testResultsFile

    $bcptTestResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\BCPTTestResults.json"
    $bcptBaseLineFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\BCPTBaseLine.json"
    $bcptSummaryMD = GetBcptSummaryMD -path $bcptTestResultsFile -baseLinePath $bcptBaseLineFile

    # If summary fits, we will display it in the GitHub summary
    if ($summaryMD.Length -gt 65000) {
        # If Test results summary is too long, we will not display it in the GitHub summary, instead we will display a message to download the test results
        $summaryMD = "<i>Test results summary is too long to be displayed in the GitHub summary. Download test results to see details.</i>"
    }
    # If summary AND BCPT summary fits, we will display both in the GitHub summary
    if ($summaryMD.Length+$bcptSummaryMD.Length -gt 65000) {
        # If Combined Test Results and BCPT summary exceeds GitHub summary capacity, we will not display the BCPT summary
        $bcptSummaryMD = "<i>Performance test results summary is too long to be displayed in the GitHub summary. Download BCPT Test results to see details.</i>"
    }
    # If summary AND BCPT summary AND failures summary fits, we will display all in the GitHub summary
    if ($summaryMD.Length+$failuresMD.Length+$bcptSummaryMD.Length -gt 65000) {
        # If Combined Test Results, failures and BCPT summary exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
        $failuresMD = $failuresSummaryMD
    }

    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "## Test results`n`n"
    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($summaryMD.Replace("\n","`n"))`n`n"
    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($failuresMD.Replace("\n","`n"))`n`n"
    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "## Performance test results`n`n"
    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($bcptSummaryMD.Replace("\n","`n"))`n`n"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "AnalyzeTests action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
