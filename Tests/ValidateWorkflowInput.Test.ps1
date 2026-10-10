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

    It 'Test Validate-ReleaseType' {
        Import-Module (Join-Path -Path $scriptRoot -ChildPath "$($actionName).psm1" -Resolve) -Force -DisableNameChecking
        $inputName = 'releaseType'

        { Validate-ReleaseType -inputName $inputName -inputValue 'Release' } | Should -Not -Throw
        { Validate-ReleaseType -inputName $inputName -inputValue 'Prerelease' } | Should -Not -Throw
        { Validate-ReleaseType -inputName $inputName -inputValue 'Draft' } | Should -Not -Throw
        { Validate-ReleaseType -inputName $inputName -inputValue 'release' } | Should -Throw
        { Validate-ReleaseType -inputName $inputName -inputValue 'Beta' } | Should -Throw
        { Validate-ReleaseType -inputName $inputName -inputValue '' } | Should -Throw
    }

    # Call action
    Context 'Call action with workflowName and inputsJson (reusable workflow)' {
        BeforeEach {
            $env:Settings = (@{ versioningStrategy = 0 } | ConvertTo-Json -Compress)
        }

        AfterEach {
            Remove-Item env:Settings -ErrorAction SilentlyContinue
        }

        It 'Validates inputs from inputsJson for the specified workflow' {
            $inputsJson = @{ name = 'v1.0'; tag = '1.0.0'; releaseType = 'Prerelease'; updateVersionNumber = '+0.1'; createReleaseBranch = $false } | ConvertTo-Json -Compress
            { . $scriptPath -workflowName ' Create release' -inputsJson $inputsJson } | Should -Not -Throw
        }

        It 'Does not validate an empty updateVersionNumber in Create release' {
            $inputsJson = @{ releaseType = 'Release'; updateVersionNumber = '' } | ConvertTo-Json -Compress
            { . $scriptPath -workflowName ' Create release' -inputsJson $inputsJson } | Should -Not -Throw
        }

        It 'Throws on invalid releaseType in Create release' {
            $inputsJson = @{ releaseType = 'Beta'; updateVersionNumber = '' } | ConvertTo-Json -Compress
            { . $scriptPath -workflowName ' Create release' -inputsJson $inputsJson } | Should -Throw "*releaseType is 'Beta'*"
        }

        It 'Throws on invalid versionNumber in Increment Version Number' {
            $inputsJson = @{ versionNumber = '1.2.3'; directCommit = $true } | ConvertTo-Json -Compress
            { . $scriptPath -workflowName ' Increment Version Number' -inputsJson $inputsJson } | Should -Throw "*versionNumber is '1.2.3'*"
        }

        It 'Throws when no validation script exists for the workflow' {
            $inputsJson = @{ releaseType = 'Release' } | ConvertTo-Json -Compress
            { . $scriptPath -workflowName 'My Orchestrator' -inputsJson $inputsJson } | Should -Throw "No validate workflow script found for myorchestrator."
        }
    }
}
