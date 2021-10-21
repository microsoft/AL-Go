# PSScriptAnalyzer
# Run tests
Invoke-Pester @(Get-ChildItem -Path (Join-Path $PSScriptRoot "*.Test.ps1"))
