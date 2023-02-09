Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "DetermineBuildOrder Action Tests" {
    BeforeAll {
        $actionName = "DetermineBuildOrder"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        Write-Host $env:GITHUB_OUTPUT
    }

    It 'should generate correct projects for depth 3' {
        & $scriptPath `
                -projectsJson '["P0","P1","P2","P3","P4"]' `
                -BuildOrderJson '{"1":["P1"],"2":["P2","P3"],"3":["P0","P4"]}' `
                -BuildOrderDepth '3' `
                -WorkflowDepth '3'
        
        $generatedEnvVariables = Get-Content $env:GITHUB_OUTPUT
        $generatedEnvVariables | Should -Contain 'projects3Json=["P0","P4"]'
        $generatedEnvVariables | Should -Contain 'projects3Count=2'
        $generatedEnvVariables | Should -Contain 'projects2Json=["P2","P3"]'
        $generatedEnvVariables | Should -Contain 'projects2Count=2'
        $generatedEnvVariables | Should -Contain 'projects1Json=["P1"]'
        $generatedEnvVariables | Should -Contain 'projects1Count=1'
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

}
