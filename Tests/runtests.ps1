# PSScriptAnalyzer
# Run tests
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "AppHelper.Test.ps1" -Resolve )

# Test Actions
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "AddExistingApp.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "CheckForUpdates.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "CreateApp.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "CreateDevelopmentEnvironment.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "Deploy.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "IncrementVersionNumber.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "PipelineCleanup.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "ReadSecrets.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "ReadSettings.Action.Test.ps1" -Resolve )
Invoke-Pester (Join-Path -path $PSScriptRoot -ChildPath "RunPipeline.Action.Test.ps1" -Resolve )
