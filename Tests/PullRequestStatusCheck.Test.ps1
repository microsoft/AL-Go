Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "PullRequestStatusCheck Action Tests" {
    BeforeAll {
        $actionName = "PullRequestStatusCheck"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        $ENV:GITHUB_REPOSITORY = "organization/repository"
        $ENV:GITHUB_RUN_ID = "123456"
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    It 'should fail if there is a job that fails' {
        Mock -CommandName gh -MockWith {'{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "failure" }]}'}
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: job3'
    }

    It 'should complete if there are no failing jobs' {
        Mock -CommandName gh -MockWith {'{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "success" }]}'}
        Mock Write-Host {}
        & $scriptPath
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "PR Build succeeded" }
    }
}