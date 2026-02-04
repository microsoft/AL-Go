# PSScriptAnalyzer
# Run tests

<#
  .SYNOPSIS
    Run Pester tests
  .PARAMETER Path
    The folder where the tests are located. Default is the folder where the script is located.
#>
param(
  [Parameter(Mandatory = $true)]
  [string] $Path
)

try {
  $errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

  Write-Host "Running tests in $Path"

  $result = Invoke-Pester @(Get-ChildItem -Path (Join-Path $Path "*.Test.ps1")) -passthru
  if ($result.FailedCount -gt 0) {
    Write-Host "::Error::$($result.FailedCount) tests are failing"
    $host.SetShouldExit(1)
  }
}
catch {
  Write-Host "::Error::Error when running tests. The Error was $($_.Exception.Message)"
  $host.SetShouldExit(1)
}
