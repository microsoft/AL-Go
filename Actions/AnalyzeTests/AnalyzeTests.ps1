Param(
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Tests to analyze", Mandatory = $false)]
    [string] $testsToAnalyze = 'default'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')

if ($testsToAnalyze -eq 'default') {
    $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\TestResults.xml"
    #$analyzerFunction = ${function:GetTestResultSummaryMD}
    $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetTestResultSummaryMD -testResultsFile $testResultsFile
    $testTitle = "Test results"
} 
elseif ($testsToAnalyze -eq 'bcpt') {
    $settings = $env:Settings | ConvertFrom-Json
    $bcptTestResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptTestResults.json"
    $bcptBaseLineFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptBaseLine.json"
    $bcptThresholdsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\bcptThresholds.json"
    $testResultsSummaryMD = GetBcptSummaryMD `
        -bcptTestResultsFile $bcptTestResultsFile `
        -baseLinePath $bcptBaseLineFile `
        -thresholdsPath $bcptThresholdsFile `
        -bcptThresholds ($settings.bcptThresholds | ConvertTo-HashTable)
    $testTitle = "Performance test results"
}
elseif ($testsToAnalyze -eq 'pageScripting') {
    #. (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')
    #page script analyzer..
    $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\PageScriptingTestResults.xml"
    #$analyzerFunction = ${function:GetPageScriptingTestResultSummaryMD}
    $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetPageScriptingTestResultSummaryMD -testResultsFile $testResultsFile
    $testTitle = "Page Scripting test results"
}
else {
    Write-Host "::error:: Unknown test type: $testsToAnalyze"
}

#$testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\$testResultsFile"
#$testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetTestResultSummaryMD -testResultsFile $testResultsFile
#$testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = $analyzerFunction.Invoke($testResultsFile)

# If summary fits, we will display it in the GitHub summary
if ($testResultsSummaryMD.Length -gt 65000) {
    # If Test results summary is too long, we will not display it in the GitHub summary, instead we will display a message to download the test results
    $testResultsSummaryMD = "<i>Test results summary size exceeds GitHub summary capacity. Download **TestResults** artifact to see details.</i>"
}
# # If summary AND BCPT summary fits, we will display both in the GitHub summary
# if ($testResultsSummaryMD.Length + $bcptSummaryMD.Length -gt 65000) {
#     # If Combined Test Results and BCPT summary exceeds GitHub summary capacity, we will not display the BCPT summary
#     $bcptSummaryMD = "<i>Performance test results summary size exceeds GitHub summary capacity. Download **BcptTestResults** artifact to see details.</i>"
# }
# If summary AND BCPT summary AND failures summary fits, we will display all in the GitHub summary
# if ($testResultsSummaryMD.Length + $testResultsfailuresMD.Length + $bcptSummaryMD.Length -gt 65000) {
#     # If Combined Test Results, failures and BCPT summary exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
#     $testResultsfailuresMD = $testResultsFailuresSummaryMD
# }
if ($testResultsSummaryMD.Length + $testResultsfailuresMD.Length -gt 65000) {
    # If Combined Test Results and failures exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
    $testResultsfailuresMD = $testResultsFailuresSummaryMD
}

Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## $testTitle`n`n"
Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsSummaryMD.Replace("\n","`n"))`n`n"
Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsfailuresMD.Replace("\n","`n"))`n`n"
# if ($bcptSummaryMD) {
#     Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## Performance test results`n`n"
#     Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($bcptSummaryMD.Replace("\n","`n"))`n`n"
# }
