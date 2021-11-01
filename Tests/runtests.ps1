# PSScriptAnalyzer
# Run tests
Invoke-Pester @(Get-ChildItem -Path (Join-Path $PSScriptRoot "*.Test.ps1"))
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "CreateReleaseNotes.Tests" -Resolve )
