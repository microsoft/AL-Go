Param(
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Tests to analyze", Mandatory = $true)]
    [ValidateSet('normal', 'bcpt', 'pageScripting')]
    [string] $testType
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')

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
        $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\.buildartifacts\PageScriptingTestResults.xml"
        $testResultsSummaryMD, $testResultsfailuresMD, $testResultsFailuresSummaryMD = GetPageScriptingTestResultSummaryMD -testResultsFile $testResultsFile -project $project
        $testTitle = "Page Scripting test results"
    }
    default {
        Write-Host "::error:: Unknown test type: $testType"
        return ''
    }
}

function GetStringByteSize($string) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($string)
    return $bytes.Length
}

Write-Host "----"
Write-Host "## $testTitle"
Write-Host "----"
Write-Host "$($testResultsSummaryMD)"
Write-Host "----"
Write-Host "$($testResultsfailuresMD)"
Write-Host "----"


$titleSize = GetStringByteSize("## $testTitle`n`n")
#$summarySize = GetStringByteSize("$($testResultsSummaryMD.Replace("\n","`n"))`n`n")
#$failureSummarySize = GetStringByteSize("$($testResultsfailuresMD.Replace("\n","`n"))`n`n")
$summarySize = GetStringByteSize("oakepokff")
$failureSummarySize = GetStringByteSize("ifjoisjf")

# GitHub job summaries are limited to just under 1MB and we call Add-Content 3 times which each adds a new line, hence 1MB - 4.
# If no tests are found, don't add a job summary at all.
if ($testResultsSummaryMD) {
    # If summary fits, we will display it in the GitHub summary
    if ($titleSize + $summarySize -gt (1MB - 4)) {
        # If Test results summary is too long, we will not display it in the GitHub summary, instead we will display a message to download the test results
        $testResultsSummaryMD = "<i>Test results summary size exceeds GitHub summary capacity. Download **TestResults** artifact to see details.</i>"
        $summarySize = GetStringByteSize($testResultsSummaryMD)
    }
    if ($titleSize + $summarySize + $failureSummarySize -gt (1MB - 4)) {
        # If Combined Test Results and failures exceeds GitHub summary capacity, we will not display the failures details, only the failures summary
        $testResultsfailuresMD = $testResultsFailuresSummaryMD
    }

    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "## $testTitle`n`n"
    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsSummaryMD.Replace("\n","`n"))`n`n"
    Add-Content -Encoding UTF8 -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultsfailuresMD.Replace("\n","`n"))`n`n"
}
