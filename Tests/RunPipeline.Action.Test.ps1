Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "RunPipeline Action Tests" {
    BeforeAll {
        $actionName = "RunPipeline"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Test warning for symbols packages' {
        Import-Module (Join-Path $scriptRoot '.\RunPipeline.psm1' -Resolve) -Force
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
        Import-Module (Join-Path $PSScriptRoot '../Actions/TelemetryHelper.psm1')

        # Mock the OutputWarning and Trace-Warning functions
        Mock -CommandName OutputWarning -MockWith { param($Message) Write-Host "OutputWarning: $Message" } -ModuleName RunPipeline
        Mock -CommandName Trace-Warning -MockWith { param($Message) Write-Host "Trace-Information: $Message" } -ModuleName RunPipeline

        # Invoke the function with TestApp1 (a symbols package) and TestApp2 (a full app package)
        $tempFolder = [System.IO.Path]::GetTempPath()
        Test-InstallApps -AllInstallApps @(".\TestApps\EssentialBusinessHeadlinesFull.app", ".\TestApps\EssentialBusinessHeadlinesSymbols.app") -ProjectPath $PSScriptRoot -RunnerTempFolder $tempFolder

        # Assert that the warning was output
        Should -Invoke -CommandName 'OutputWarning' -Times 1 -ModuleName RunPipeline
        Should -Invoke -CommandName 'OutputWarning' -Times 1 -ModuleName RunPipeline -ParameterFilter { $Message -like "*App EssentialBusinessHeadlinesSymbols.app is a symbols package and should not be published. The workflow may fail if you try to publish it." }

        # Assert that Trace-Warning was called once with the count
        Should -Invoke -CommandName 'Trace-Warning' -Times 1 -ModuleName RunPipeline -ParameterFilter { $Message -like "*1 symbols-only package(s) detected in install apps." }
        # Assert that Trace-Warning was not called
        Should -Invoke -CommandName 'Trace-Warning' -Times 0 -ModuleName RunPipeline -ParameterFilter { $Message -like "App file path for * could not be resolved." }
    }

    # Call action

}
