Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

$script:actionName = "CreateDevelopmentEnvironment"
$script:scriptRoot = Join-Path $PSScriptRoot "..\Actions\$script:actionName" -Resolve
$script:actionScript = GetActionScript -scriptRoot $script:scriptRoot -scriptName "$script:actionName.ps1"

Describe "$script:actionName Action Tests" {
    It 'Compile Action' {
        Invoke-Expression $script:actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $script:scriptRoot -actionName $script:actionName -actionScript $script:actionScript -permissions $permissions -outputs $outputs
    }

    # Call action

}
