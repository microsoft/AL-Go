Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

$global:actionName = "Deploy"
$global:scriptRoot = Join-Path $PSScriptRoot "..\Actions\$global:actionName" -Resolve
$global:actionScript = GetActionScript -scriptRoot $global:scriptRoot -scriptName "$global:actionName.ps1"

Describe "$global:actionName Action Tests" {
    It 'Compile Action' {
        Invoke-Expression $global:actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $global:scriptRoot -actionName $global:actionName -actionScript $global:actionScript -permissions $permissions -outputs $outputs
    }

    # Call action

}
