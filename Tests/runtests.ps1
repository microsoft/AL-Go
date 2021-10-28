# PSScriptAnalyzer
# Run tests
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "AppHelper.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "CreateReleaseNotes.Tests" -Resolve )
