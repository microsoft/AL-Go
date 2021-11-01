# PSScriptAnalyzer
# Run tests
try {
  $errorActionPreference = "stop"
  Set-StrictMode -version 2.0
  $result = Invoke-Pester @(Get-ChildItem -Path (Join-Path $PSScriptRoot "*.Test.ps1")) -passthru
  if ($result.FailedCount -gt 0) {
    Write-Host "::Error::$($TestResults.FailedCount) tests are failing"
    $host.SetShouldExit(1)
  }
}
catch {
  Write-Host "::Error::Error when running tests. The Error was $($_.Exception.Message)"
  $host.SetShouldExit(1)
}

