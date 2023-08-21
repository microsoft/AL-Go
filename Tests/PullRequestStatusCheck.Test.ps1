Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "PullRequestStatusCheck Action Tests" {
    BeforeAll {
        $actionName = "PullRequestStatusCheck"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
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

    # Call action

    It 'should fail if there is a job that fails' {
        Mock -CommandName gh -MockWith {  '{ "total_count":  3, "jobs":  [ { "conclusion":  "failure" }, { "conclusion":  "skipped" }, { "conclusion":  "success" } ] }' }

       { 
        & $scriptPath `
                -Repository "microsoft/AL-Go" `
                -RunId "123456"
        } | Should -Throw
    }

    It 'should complete if there are no failing jobs' {
        Mock -CommandName gh -MockWith {  '{ "total_count":  3, "jobs":  [ { "conclusion":  "skipped" }, { "conclusion":  "skipped" }, { "conclusion":  "success" } ] }' }

       { 
        & $scriptPath `
                -Repository "microsoft/AL-Go" `
                -RunId "123456"
        }

        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Workflow succeeded" }
    }

}
