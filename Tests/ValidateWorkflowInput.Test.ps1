Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "ValidateWorkflowInput Action Tests" {
    BeforeAll {
        $actionName = "ValidateWorkflowInput"
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

    It 'Test Validate-UpdateVersionNumber' {
        Import-Module (Join-Path -Path $scriptRoot -ChildPath "$($actionName).psm1" -Resolve) -Force -DisableNameChecking
        $inputName = 'UpdateVersionNumber'

        $settings = @{
            versioningStrategy = 0
        }
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+1'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.1'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.0.1'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.0.0.1'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2.3'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2.3.4'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue 'a.b'} | Should -Throw

        $settings = @{
            versioningStrategy = 3
        }
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+1'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.1'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.0.1'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '+0.0.0.1'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2.3'} | Should -Not -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue '1.2.3.4'} | Should -Throw
        { Validate-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue 'a.b.c'} | Should -Throw
    }
    # Call action

}
