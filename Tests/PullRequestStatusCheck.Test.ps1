Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "PullRequestStatusCheck Action Tests" {
    BeforeAll {
        $actionName = "PullRequestStatusCheck"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        # Import Github-Helper so Invoke-CommandWithRetry is available and its Start-Sleep can be mocked.
        Import-Module (Join-Path $scriptRoot '..\Github-Helper.psm1' -Resolve) -DisableNameChecking -Force
        $ENV:GITHUB_REPOSITORY = "organization/repository"
        $ENV:GITHUB_RUN_ID = "123456"
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'should fail if there is a job that fails' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "failure" }]}' }
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: job3'
    }

    It 'should detect failing jobs across multiple pages (gh --slurp returns an array)' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '[{"total_count":4,"jobs":[{ "name": "job1", "conclusion": "success" },{ "name": "job2", "conclusion": "success" }]},{"total_count":4,"jobs":[{ "name": "job3", "conclusion": "success" },{ "name": "job4", "conclusion": "failure" }]}]' }
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: job4'
    }

    It 'should complete if there are no failing jobs' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "success" }]}' }
        Mock Write-Host {}
        & $scriptPath
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "PR Build succeeded" }
    }

    It 'should retry when the jobs API call fails and then give up' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 1 }
        Mock -CommandName Start-Sleep -ModuleName Github-Helper -MockWith {}
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage '*Failed to get jobs for run*'
        Assert-MockCalled gh -Exactly 5 -Scope It
    }
}
