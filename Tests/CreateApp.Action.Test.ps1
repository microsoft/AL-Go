Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

BeforeAll {
    $actionName = "CreateApp"
    $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
    $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
}

Describe "CreateApp Action Tests" {
    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # Call action

}
