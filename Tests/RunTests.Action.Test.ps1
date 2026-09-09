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

        . $helperPath
        Import-Module (Join-Path $scriptRoot 'RunTests.psm1' -Resolve) -DisableNameChecking -Force

    }

    BeforeEach {
        $script:previousContainerCredential = $ENV:containerCredential
        $script:previousContainerName = $ENV:containerName
        $script:previousRunTestsToken = $ENV:_token
        $script:previousTokenObservationPath = $ENV:_runTestsTokenObservationPath
        $script:previousGitHubWorkspace = $ENV:GITHUB_WORKSPACE
        $script:previousSettings = $ENV:Settings
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
        if ($null -eq $script:previousRunTestsToken) {
            Remove-Item Env:\_token -ErrorAction SilentlyContinue
        }
        else {
            $ENV:_token = $script:previousRunTestsToken
        }
        if ($null -eq $script:previousTokenObservationPath) {
            Remove-Item Env:\_runTestsTokenObservationPath -ErrorAction SilentlyContinue
        }
        else {
            $ENV:_runTestsTokenObservationPath = $script:previousTokenObservationPath
        }
        if ($null -eq $script:previousGitHubWorkspace) {
            Remove-Item Env:\GITHUB_WORKSPACE -ErrorAction SilentlyContinue
        }
        else {
            $ENV:GITHUB_WORKSPACE = $script:previousGitHubWorkspace
        }
        if ($null -eq $script:previousSettings) {
            Remove-Item Env:\Settings -ErrorAction SilentlyContinue
        }
        else {
            $ENV:Settings = $script:previousSettings
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

    It 'Loads only the runner override and delegates event log capture to the module' {
        $overrideCommands = @($actionAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Get-ScriptOverrides'
                }, $true))
        $overrideCommands.Count | Should -Be 1
        $overrideParameter = @($overrideCommands[0].CommandElements |
                Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $_.ParameterName -eq 'OverrideScriptNames'
                })[0]
        $overrideParameterIndex = [Array]::IndexOf($overrideCommands[0].CommandElements, $overrideParameter)
        $overrideArgument = $overrideCommands[0].CommandElements[$overrideParameterIndex + 1]
        @($overrideArgument.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true).Value) | Should -Be @('RunTestsInBcContainer')

        $actionEventLogCalls = @($actionAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Export-AlGoContainerEventLog'
                }, $true))
        $actionEventLogCalls.Count | Should -Be 0

        $moduleTokens = $null
        $moduleParseErrors = $null
        $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scriptRoot 'RunTests.psm1'),
            [ref] $moduleTokens,
            [ref] $moduleParseErrors
        )
        $moduleParseErrors | Should -BeNullOrEmpty
        @($moduleAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Export-AlGoContainerEventLog'
                }, $true)).Count | Should -Be 1
    }

    It 'Refreshes the override token from a direct script parameter' {
        $providedToken = "provided-$([Guid]::NewGuid())"
        $ENV:_token = 'stale-token'
        $ENV:GITHUB_WORKSPACE = $TestDrive
        $ENV:Settings = '{}'
        $ENV:containerName = 'test-container'
        $ENV:_runTestsTokenObservationPath = Join-Path $TestDrive 'observed-token.txt'
        $ENV:containerCredential = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes('{"username":"test-user","password":"test-password"}')
        )

        Mock DownloadAndImportBcContainerHelper {}
        Mock AnalyzeRepo { return @{ testFolders = @() } }
        Mock Get-ScriptOverrides {
            return @{
                RunTestsInBcContainer = {
                    param([hashtable] $parameters)
                    $null = $parameters
                    Set-Content -Path $ENV:_runTestsTokenObservationPath -Value $ENV:_token -Encoding UTF8
                    return $true
                }
            }
        }
        Mock Invoke-AlGoTestRun {
            param($runTestsOverride)
            return (& $runTestsOverride -parameters @{})
        }

        & $scriptPath -token $providedToken

        (Get-Content -Path $ENV:_runTestsTokenObservationPath -Raw).Trim() | Should -Be $providedToken
        $ENV:_token | Should -Be $providedToken
    }

    It 'Passes nested settings to AnalyzeRepo as recursive hashtables' {
        $ENV:GITHUB_WORKSPACE = $TestDrive
        $ENV:Settings = @{
            workspaceCompilation = @{
                enabled = $true
                options = @(@{ name = 'nested-entry' })
            }
        } | ConvertTo-Json -Depth 4
        $ENV:containerName = 'test-container'
        $ENV:containerCredential = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes('{"username":"test-user","password":"test-password"}')
        )

        Mock DownloadAndImportBcContainerHelper {}
        Mock AnalyzeRepo {
            param($settings)
            $settings | Should -BeOfType System.Collections.Hashtable
            $settings.workspaceCompilation | Should -BeOfType System.Collections.Hashtable
            $settings.workspaceCompilation.options[0] | Should -BeOfType System.Collections.Hashtable
            $settings.workspaceCompilation.options[0].name | Should -Be 'nested-entry'
            return @{ testFolders = @() }
        }
        Mock Get-ScriptOverrides { return @{} }
        Mock Invoke-AlGoTestRun {}

        & $scriptPath

        Should -Invoke AnalyzeRepo -Times 1 -Exactly
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
