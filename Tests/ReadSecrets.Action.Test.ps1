Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

BeforeAll {
    $actionName = "ReadSecrets"
    $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
    $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
}

Describe "ReadSecrets Action Tests" {
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

}
