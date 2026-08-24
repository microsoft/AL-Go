Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "RunTests Action Tests" {
    BeforeAll {
        $actionName = "RunTests"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'rawActionScript', Justification = 'Used by event-log wiring tests.')]
        $rawActionScript = Get-Content -Path $scriptPath -Raw

        $tokens = $null
        $parseErrors = $null
        $actionAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens, [ref] $parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        foreach ($functionName in @('Get-TestRunnerCredential', 'Get-TestRunnerContainerName')) {
            $functionAst = $actionAst.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
                }, $true)
            . ([ScriptBlock]::Create($functionAst.Extent.Text))
        }

        $helperPath = Join-Path $scriptRoot '..\AL-Go-Helper.ps1' -Resolve
        $helperAst = [System.Management.Automation.Language.Parser]::ParseFile($helperPath, [ref] $tokens, [ref] $parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $convertToHashTableAst = $helperAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertTo-HashTable'
            }, $true)
        . ([ScriptBlock]::Create($convertToHashTableAst.Extent.Text))

    }

    BeforeEach {
        $script:previousContainerCredential = $ENV:containerCredential
        $script:previousContainerName = $ENV:containerName
    }

    AfterEach {
        if ($null -eq $script:previousContainerCredential) {
            Remove-Item Env:\containerCredential -ErrorAction SilentlyContinue
        }
        else {
            $ENV:containerCredential = $script:previousContainerCredential
        }
        if ($null -eq $script:previousContainerName) {
            Remove-Item Env:\containerName -ErrorAction SilentlyContinue
        }
        else {
            $ENV:containerName = $script:previousContainerName
        }
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Uses the integrated event log lifecycle without loading an event log override' {
        $rawActionScript | Should -Match 'OverrideScriptNames @\("RunTestsInBcContainer"\)'
        $rawActionScript | Should -Match '(?m)^Invoke-AlGoTestRun '
        $rawActionScript | Should -Not -Match 'GetBcContainerEventLog'
    }

    Context 'RunPipeline wiring' {
        It 'Rejects a missing or blank kept container credential' -TestCases @(
            @{ Value = $null }
            @{ Value = '' }
            @{ Value = ' ' }
        ) {
            param($Value)
            $ENV:containerCredential = $Value

            { Get-TestRunnerCredential } |
                Should -Throw '*RunPipeline-to-RunTests wiring error*container credential*not provided*'
        }

        It 'Rejects malformed kept container credentials without exposing their value' -TestCases @(
            @{ Value = 'credential-secret-value' }
            @{ Value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{invalid')) }
            @{ Value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"username":"admin","password":""}')) }
        ) {
            param($Value)
            $ENV:containerCredential = $Value

            try {
                Get-TestRunnerCredential
                throw 'Expected credential validation to fail.'
            }
            catch {
                $_.Exception.Message | Should -BeLike '*RunPipeline-to-RunTests wiring error*container credential*expected format*'
                $_.Exception.Message | Should -Not -Match [regex]::Escape($Value)
            }
        }

        It 'Creates the credential supplied by RunPipeline' {
            $ENV:containerCredential = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes('{"username":"pipeline-user","password":"pipeline-password"}')
            )

            $credential = Get-TestRunnerCredential

            $credential.UserName | Should -Be 'pipeline-user'
            $credential.GetNetworkCredential().Password | Should -Be 'pipeline-password'
        }

        It 'Rejects a missing or blank kept container name' -TestCases @(
            @{ Value = $null }
            @{ Value = '' }
            @{ Value = ' ' }
        ) {
            param($Value)
            $ENV:containerName = $Value

            { Get-TestRunnerContainerName } |
                Should -Throw '*RunPipeline-to-RunTests wiring error*container name*not provided*'
        }

        It 'Uses the kept container name supplied by RunPipeline' {
            $ENV:containerName = 'pipeline-container'

            Get-TestRunnerContainerName | Should -Be 'pipeline-container'
        }
    }

    # Call action

}
