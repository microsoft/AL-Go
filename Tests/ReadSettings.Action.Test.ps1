Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "ReadSettings Action Tests" {
    BeforeAll {
        $actionName = "ReadSettings"
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
            "SettingsJson" = "Settings in compressed Json format"
            "GitHubRunnerJson" = "GitHubRunner in compressed Json format"
            "GitHubRunnerShell" = "Shell for GitHubRunner jobs"
            "EnvironmentsJson" = "Environments in compressed Json format"
            "EnvironmentCount" = "Number of environments in array"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # Call action

}
