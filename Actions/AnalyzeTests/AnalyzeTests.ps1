Param(
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Tests to analyze", Mandatory = $false)]
    [ValidateSet('normal', 'bcpt', 'pageScripting')]
    [string] $testType = 'normal'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')
$mdHelperPath = Join-Path -Path $PSScriptRoot -ChildPath "..\MarkDownHelper.psm1"
if (Test-Path $mdHelperPath) {
    Import-Module $mdHelperPath
}

$testResultsSummaryMD = ''
$testResultsfailuresMD = ''
$testResultsFailuresSummaryMD = ''

switch ($testType) {
    'normal' {
        $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\TestResults.xml"
        $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetTestResultSummaryMD -testResultsFile $testResultsFile
        $testTitle = "Test results"
    }
    'bcpt' {
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
    'pageScripting' {
        $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\PageScriptingTestResults.xml"
        $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetPageScriptingTestResultSummaryMD -testResultsFile $testResultsFile
        $testTitle = "Page Scripting test results"
    }
    default {
        Write-Host "::error:: Unknown test type: $testType"
        return ''
    }
}

# If summary fits, we will display it in the GitHub summary
if ($testResultsSummaryMD.Length -gt 65000) {
    # If Test results summary is too long, we will not display it in the GitHub summary, instead we will display a message to download the test results
    $testResultsSummaryMD = "<i>Test results summary size exceeds GitHub summary capacity. Download **TestResults** artifact to see details.</i>"
}
if ($testResultsSummaryMD.Length + $testResultsfailuresMD.Length -gt 65000) {
    # If Combined Test Results and failures exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
    $testResultsfailuresMD = $testResultsFailuresSummaryMD
}

Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## $testTitle`n`n"
Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsSummaryMD.Replace("\n","`n"))`n`n"
Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsfailuresMD.Replace("\n","`n"))`n`n"