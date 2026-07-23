Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "E2EAnalyze Action Tests" {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $PSScriptRoot "..\.github\actions\E2EAnalyze\E2EAnalyze.ps1" -Resolve
        # Dot-source the script to load Get-E2EScenariosToRun without executing the main block.
        # -maxParallel satisfies the mandatory parameter; the main block is guarded to only run when the
        # script is invoked directly (InvocationName -ne '.').
        . $scriptPath -maxParallel 1

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'allScenarios', Justification = 'False positive.')]
        $allScenarios = @('alpha', 'beta', 'gamma')
    }

    It 'Get-E2EScenariosToRun is defined' {
        Get-Command Get-E2EScenariosToRun -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Default filter (*) returns all scenarios' {
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios)
        $result.Count | Should -Be 3
        $result | Should -Contain 'alpha'
        $result | Should -Contain 'beta'
        $result | Should -Contain 'gamma'
    }

    It 'Zero-match filter returns no scenarios' {
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'zzz*')
        $result.Count | Should -Be 0
    }

    It 'One-match exact filter returns a single scenario' {
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'alpha')
        $result.Count | Should -Be 1
        $result | Should -Contain 'alpha'
    }

    It 'One-match wildcard filter returns a single scenario' {
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'gam*')
        $result.Count | Should -Be 1
        $result | Should -Contain 'gamma'
    }

    It 'Multi-match comma separated filter returns only matching scenarios' {
        # Regression test: multiple filter entries must not cause every scenario to match
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'alpha,beta')
        $result.Count | Should -Be 2
        $result | Should -Contain 'alpha'
        $result | Should -Contain 'beta'
        $result | Should -Not -Contain 'gamma'
    }

    It 'Multi-match comma separated wildcard filter returns only matching scenarios' {
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'al*, be*')
        $result.Count | Should -Be 2
        $result | Should -Contain 'alpha'
        $result | Should -Contain 'beta'
        $result | Should -Not -Contain 'gamma'
    }

    It 'Disabled scenarios are filtered out' {
        $disabled = @([PSCustomObject]@{ scenario = 'beta'; reason = 'Flaky' })
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -disabledScenariosConfig $disabled)
        $result.Count | Should -Be 2
        $result | Should -Contain 'alpha'
        $result | Should -Contain 'gamma'
        $result | Should -Not -Contain 'beta'
    }

    It 'Filter and disabled scenarios combine' {
        $disabled = @([PSCustomObject]@{ scenario = 'alpha'; reason = 'Disabled' })
        $result = @(Get-E2EScenariosToRun -allScenarios $allScenarios -scenariosFilter 'alpha,beta' -disabledScenariosConfig $disabled)
        $result.Count | Should -Be 1
        $result | Should -Contain 'beta'
        $result | Should -Not -Contain 'alpha'
    }

    It 'Empty scenario list returns nothing' {
        $result = @(Get-E2EScenariosToRun -allScenarios @() -scenariosFilter '*')
        $result.Count | Should -Be 0
    }
}
