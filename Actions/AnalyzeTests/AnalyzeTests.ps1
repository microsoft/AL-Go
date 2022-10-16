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
    if (Test-Path $testResultsFile) {
        $testResults = [xml](Get-Content "$project\TestResults.xml")
        $testResultSummary = GetTestResultSummary -testResults $testResults -includeFailures 50

        Add-Content -Path $env:GITHUB_OUTPUT -Value "TestResultMD=$testResultSummary"
        Write-Host "TestResultMD=$testResultSummary"
    
        Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultSummary.Replace("\n","`n"))`n"
    }
    else {
        Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "*Test results not found*`n`n"
    }

    $bcptTestResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\BCPTTestResults.json"
    if (Test-Path $bcptTestResultsFile) {
        # TODO Display BCPT Test Results
    }
    else {
        #Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "*BCPT test results not found*`n`n"
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "AnalyzeTests action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
