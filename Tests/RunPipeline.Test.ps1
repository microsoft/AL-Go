$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "RunPipeline separate test action eligibility" {
    BeforeAll {
        $runPipelineScript = Get-Content (Join-Path $PSScriptRoot "../Actions/RunPipeline/RunPipeline.ps1") -Raw
        $tokens = $null
        $parseErrors = $null
        $runPipelineAst = [System.Management.Automation.Language.Parser]::ParseInput($runPipelineScript, [ref] $tokens, [ref] $parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $eligibilityAssignments = @($runPipelineAst.FindAll({
                    Param($ast)
                    $ast -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $ast.Left.Extent.Text -eq '$runTestsInSeparateAction'
                }, $true))
        $eligibilityAssignments.Count | Should -Be 1
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'eligibilityExpression', Justification = 'Used by the Pester test cases.')]
        $eligibilityExpression = [scriptblock]::Create(
            "Param(`$settings, `$createsTestContainer, `$additionalCountries) $($eligibilityAssignments[0].Right.Extent.Text)"
        )

        function Get-TestSetting {
            Param(
                [bool] $useSeparateTestAction = $true,
                [bool] $doNotRunTests = $false
            )

            return @{
                useSeparateTestAction = $useSeparateTestAction
                doNotRunTests         = $doNotRunTests
            }
        }
    }

    It "Uses the separate action for an eligible single-country build" {
        (& $eligibilityExpression (Get-TestSetting) $true @()) | Should -BeTrue
    }

    It "Keeps normal tests in RunPipeline when additional countries are configured" {
        (& $eligibilityExpression (Get-TestSetting) $true @("dk", "de")) | Should -BeFalse
    }

    It "Skips the separate action when normal tests are disabled" {
        (& $eligibilityExpression (Get-TestSetting -doNotRunTests $true) $true @()) | Should -BeFalse
    }

    It "Skips the separate action when no local test container is created" {
        (& $eligibilityExpression (Get-TestSetting) $false @()) | Should -BeFalse
    }

    It "Skips the separate action when the preview setting is disabled" {
        (& $eligibilityExpression (Get-TestSetting -useSeparateTestAction $false) $true @()) | Should -BeFalse
    }

    It "Uses the runtime decision for the workflow signal and container lifetime" {
        $runPipelineScript | Should -Match 'runTestsInSeparateAction=\$runTestsInSeparateAction'
        $runPipelineScript | Should -Match '-keepContainer:\$runTestsInSeparateAction'
        $runPipelineScript | Should -Not -Match 'keepContainerForSeparateTestAction'
    }

    It "Gates both template RunTests steps on the runtime decision" {
        $expectedCondition = "if: steps.DetermineBuildProject.outputs.BuildIt == 'True' && env.runTestsInSeparateAction == 'True'"
        $workflowPaths = @(
            "../Templates/AppSource App/.github/workflows/_BuildALGoProject.yaml"
            "../Templates/Per Tenant Extension/.github/workflows/_BuildALGoProject.yaml"
        )

        foreach ($workflowPath in $workflowPaths) {
            $workflow = Get-Content (Join-Path $PSScriptRoot $workflowPath) -Raw
            ([regex]::Matches($workflow, [regex]::Escape($expectedCondition))).Count | Should -Be 1
            $workflow | Should -Not -Match "env\.useSeparateTestAction == 'True'"
        }
    }
}
