$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

<#
.SYNOPSIS
    Runs the code coverage aggregate worker in a child PowerShell 7 process.
.DESCRIPTION
    Loads the aggregate module and processes report descriptors received through
    standard input using paths supplied by the parent process.
#>

try {
    Import-Module $env:ALGO_COVERAGE_WORKER_MODULE -Force -DisableNameChecking
    Invoke-CodeCoverageAggregateProcess `
        -configPath $env:ALGO_COVERAGE_WORKER_CONFIG `
        -resultPath $env:ALGO_COVERAGE_WORKER_RESULT
}
catch {
    Write-Error "Code coverage aggregate worker failed. $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
