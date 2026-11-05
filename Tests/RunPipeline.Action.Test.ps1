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

        $tokens = $null
        $parseErrors = $null
        $runPipelineAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath,
            [ref] $tokens,
            [ref] $parseErrors
        )
        $parseErrors | Should -BeNullOrEmpty
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'eligibilityAssignments', Justification = 'Used by eligibility wiring test.')]
        $eligibilityAssignments = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -eq '$runTestsInSeparateAction'
                }, $true))
        $eligibilityAssignments.Count | Should -Be 1

        $eligibilityFunctionAst = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Get-SeparateTestActionIneligibilityReasons'
                }, $true))
        $eligibilityFunctionAst.Count | Should -Be 1
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'eligibilityFunction', Justification = 'Used by eligibility test cases.')]
        $eligibilityFunction = $eligibilityFunctionAst[0].Body.GetScriptBlock()

        $newCredentialFunctionAst = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'New-RunPipelineContainerCredential'
                }, $true))
        $newCredentialFunctionAst.Count | Should -Be 1
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'newCredentialFunction', Justification = 'Used by credential test cases.')]
        $newCredentialFunction = $newCredentialFunctionAst[0].Body.GetScriptBlock()

        $setCredentialFunctionAst = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Set-RunPipelineContainerCredential'
                }, $true))
        $setCredentialFunctionAst.Count | Should -Be 1
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'setCredentialFunction', Justification = 'Used by credential test cases.')]
        $setCredentialFunction = $setCredentialFunctionAst[0].Body.GetScriptBlock()

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'credentialCommandAsts', Justification = 'Used by credential ordering tests.')]
        $credentialCommandAsts = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in @(
                        'New-RunPipelineContainerCredential',
                        'Set-RunPipelineContainerCredential',
                        'Run-AlPipeline'
                    )
                }, $true))
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Creates and attaches the container credential before Run-AlPipeline' {
        $newCredentialCommands = @($credentialCommandAsts | Where-Object { $_.GetCommandName() -eq 'New-RunPipelineContainerCredential' })
        $setCredentialCommands = @($credentialCommandAsts | Where-Object { $_.GetCommandName() -eq 'Set-RunPipelineContainerCredential' })
        $runAlPipelineCommands = @($credentialCommandAsts | Where-Object { $_.GetCommandName() -eq 'Run-AlPipeline' })

        $newCredentialCommands.Count | Should -Be 1
        $setCredentialCommands.Count | Should -Be 1
        $runAlPipelineCommands.Count | Should -Be 1
        $newCredentialCommands[0].Extent.StartOffset | Should -BeLessThan $runAlPipelineCommands[0].Extent.StartOffset
        $setCredentialCommands[0].Extent.StartOffset | Should -BeLessThan $runAlPipelineCommands[0].Extent.StartOffset
        $setCredentialCommands[0].Extent.Text | Should -Match '-runAlPipelineParams \$runAlPipelineParams'
        $setCredentialCommands[0].Extent.Text | Should -Match '-credential \$containerCredential'
        $setCredentialCommands[0].Extent.Text | Should -Match '-exportForRunTests:\$runTestsInSeparateAction'
    }

    It 'Derives separate test eligibility from the deterministic reason list' {
        $eligibilityAssignments[0].Right.Extent.Text |
            Should -Be '$settings.useSeparateTestAction.enabled -and $separateTestActionIneligibilityReasons.Count -eq 0'
        $actionScript | Should -Match ([regex]::Escape('$separateTestActionIneligibilityReasons -join ''; '''))
    }

    It 'Computes eligibility and configures the container credential for <Name>' -TestCases @(
        @{
            Name           = 'an enabled single-country container build'
            Enabled        = $true
            Expected       = $true
            ExpectedReason = ''
        }
        @{
            Name           = 'a disabled separate action'
            Enabled        = $false
            Expected       = $false
            ExpectedReason = ''
        }
        @{
            Name           = 'disabled normal tests'
            Enabled        = $true
            DoNotRunTests  = $true
            Expected       = $false
            ExpectedReason = 'doNotRunTests is enabled'
        }
        @{
            Name             = 'disabled test builds'
            Enabled          = $true
            DoNotBuildTests  = $true
            Expected         = $false
            ExpectedReason   = 'doNotBuildTests is enabled'
        }
        @{
            Name             = 'a build without app publication'
            Enabled          = $true
            DoNotPublishApps = $true
            Expected         = $false
            ExpectedReason   = 'doNotPublishApps is enabled'
        }
        @{
            Name                = 'additional countries'
            Enabled             = $true
            AdditionalCountries = @('dk')
            Expected             = $false
            ExpectedReason       = 'additionalCountries is configured'
        }
        @{
            Name                       = 'a test data callback with no remaining RunPipeline test category'
            Enabled                    = $true
            HasImportTestData          = $true
            DoNotRunBcptTests          = $true
            DoNotRunPageScriptingTests = $true
            Expected                   = $false
            ExpectedReason             = 'ImportTestDataInBcContainer requires RunPipeline when BCPT and page scripting tests are disabled'
        }
        @{
            Name                       = 'a test data callback with BCPT tests enabled'
            Enabled                    = $true
            HasImportTestData          = $true
            DoNotRunBcptTests          = $false
            DoNotRunPageScriptingTests = $true
            Expected                   = $true
            ExpectedReason             = ''
        }
        @{
            Name                       = 'a test data callback with page scripting tests enabled'
            Enabled                    = $true
            HasImportTestData          = $true
            DoNotRunBcptTests          = $true
            DoNotRunPageScriptingTests = $false
            Expected                   = $true
            ExpectedReason             = ''
        }
        @{
            Name             = 'configured restore events'
            Enabled          = $true
            RestoreDatabases = @('beforeeachtestapp', 'BeforeEachBcptTestApp')
            Expected         = $true
            ExpectedReason   = ''
        }
        @{
            Name                       = 'multiple blockers'
            Enabled                    = $true
            DoNotRunTests              = $true
            DoNotBuildTests            = $true
            DoNotPublishApps           = $true
            AdditionalCountries        = @('dk')
            HasImportTestData          = $true
            DoNotRunBcptTests          = $true
            DoNotRunPageScriptingTests = $true
            RestoreDatabases           = @('BeforeEachTestApp')
            Expected                   = $false
            ExpectedReason             = 'doNotRunTests is enabled; doNotBuildTests is enabled; doNotPublishApps is enabled; additionalCountries is configured; ImportTestDataInBcContainer requires RunPipeline when BCPT and page scripting tests are disabled'
        }
    ) {
        param(
            $Enabled,
            $DoNotRunTests,
            $DoNotBuildTests,
            $DoNotPublishApps,
            $AdditionalCountries,
            $HasImportTestData,
            $DoNotRunBcptTests,
            $DoNotRunPageScriptingTests,
            $RestoreDatabases,
            $Expected,
            $ExpectedReason
        )

        $previousGitHubEnv = $env:GITHUB_ENV
        $env:GITHUB_ENV = Join-Path $TestDrive "$([guid]::NewGuid()).env"
        $settings = @{
            useSeparateTestAction = @{
                enabled  = $Enabled
                testType = ''
            }
            doNotRunTests              = [bool] $DoNotRunTests
            doNotBuildTests            = [bool] $DoNotBuildTests
            doNotPublishApps           = [bool] $DoNotPublishApps
            doNotRunBcptTests          = [bool] $DoNotRunBcptTests
            doNotRunPageScriptingTests = [bool] $DoNotRunPageScriptingTests
            restoreDatabases           = @($RestoreDatabases)
        }

        try {
            $runAlPipelineParams = @{}
            if ($HasImportTestData) {
                $runAlPipelineParams.ImportTestDataInBcContainer = {}
            }
            $ineligibilityReasons = @(& $eligibilityFunction `
                    -settings $settings `
                    -additionalCountries @($AdditionalCountries) `
                    -runAlPipelineParams $runAlPipelineParams)
            ($ineligibilityReasons -join '; ') | Should -Be $ExpectedReason
            $runTestsInSeparateAction = $settings.useSeparateTestAction.enabled -and $ineligibilityReasons.Count -eq 0
            $runTestsInSeparateAction | Should -Be $Expected

            $containerCredential = & $newCredentialFunction
            $maskOutput = @(& $setCredentialFunction `
                    -runAlPipelineParams $runAlPipelineParams `
                    -credential $containerCredential `
                    -exportForRunTests:$runTestsInSeparateAction 6>&1)

            $containerCredential | Should -BeOfType System.Management.Automation.PSCredential
            $containerCredential.UserName | Should -Be 'admin'
            $containerCredential.GetNetworkCredential().Password | Should -Match '^Pass![0-9a-f-]{36}$'
            [object]::ReferenceEquals($runAlPipelineParams.credential, $containerCredential) | Should -BeTrue

            if ($Expected) {
                $exportedCredential = @(
                    Get-Content -Path $env:GITHUB_ENV -Encoding UTF8 |
                        Where-Object { $_ -like 'containerCredential=*' }
                )
                $exportedCredential.Count | Should -Be 1
                $containerCredentialBase64 = $exportedCredential[0].Substring('containerCredential='.Length)
                $exportedCredentialJson = [System.Text.Encoding]::UTF8.GetString(
                    [System.Convert]::FromBase64String($containerCredentialBase64)
                ) | ConvertFrom-Json
                $exportedCredentialJson.username | Should -Be $containerCredential.UserName
                $exportedCredentialJson.password | Should -Be $containerCredential.GetNetworkCredential().Password
                $maskMessages = @($maskOutput | ForEach-Object { "$_" })
                $maskMessages | Should -Contain "::add-mask::$($containerCredential.GetNetworkCredential().Password)"
                $maskMessages | Should -Contain "::add-mask::$containerCredentialBase64"
            }
            else {
                Test-Path -Path $env:GITHUB_ENV | Should -BeFalse
                $maskOutput | Should -BeNullOrEmpty
            }
        }
        finally {
            $env:GITHUB_ENV = $previousGitHubEnv
        }
    }

    # Call action

}
