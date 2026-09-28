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
        $eligibilityAssignments = @($runPipelineAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -eq '$runTestsInSeparateAction'
                }, $true))
        $eligibilityAssignments.Count | Should -Be 1
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'eligibilityExpression', Justification = 'Used by eligibility test cases.')]
        $eligibilityExpression = [scriptblock]::Create(
            "param(`$settings, `$additionalCountries) $($eligibilityAssignments[0].Right.Extent.Text)"
        )
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Computes separate test action eligibility for <Name>' -TestCases @(
        @{
            Name                = 'an enabled single-country container build'
            Enabled             = $true
            DoNotRunTests       = $false
            DoNotPublishApps    = $false
            AdditionalCountries = @()
            Expected            = $true
        }
        @{
            Name                = 'a disabled separate action'
            Enabled             = $false
            DoNotRunTests       = $false
            DoNotPublishApps    = $false
            AdditionalCountries = @()
            Expected            = $false
        }
        @{
            Name                = 'disabled normal tests'
            Enabled             = $true
            DoNotRunTests       = $true
            DoNotPublishApps    = $false
            AdditionalCountries = @()
            Expected            = $false
        }
        @{
            Name                = 'a build without app publication'
            Enabled             = $true
            DoNotRunTests       = $false
            DoNotPublishApps    = $true
            AdditionalCountries = @()
            Expected            = $false
        }
        @{
            Name                = 'additional countries'
            Enabled             = $true
            DoNotRunTests       = $false
            DoNotPublishApps    = $false
            AdditionalCountries = @('dk')
            Expected            = $false
        }
    ) {
        param($Enabled, $DoNotRunTests, $DoNotPublishApps, $AdditionalCountries, $Expected)

        $settings = @{
            useSeparateTestAction = @{
                enabled  = $Enabled
                testType = ''
            }
            doNotRunTests       = $DoNotRunTests
            doNotPublishApps    = $DoNotPublishApps
        }

        (& $eligibilityExpression $settings $AdditionalCountries) | Should -Be $Expected
    }

    # Call action

}
