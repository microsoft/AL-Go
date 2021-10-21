Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

$actionName = "ReadSettings"
$scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
$actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"

Describe "$actionName Action Tests" {
    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = @{
            "Settings" = "Settings in compressed Json format"
        }
        $outputs = @{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # Call action

}
