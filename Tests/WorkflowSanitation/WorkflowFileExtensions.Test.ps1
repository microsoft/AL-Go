Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-GO workflows should have the .yaml extension" {
    BeforeAll {
        $AppSourceWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $PTEWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
    }

    It 'All PTE workflows should have the .yaml extension' {
        $PTEWorkflows | ForEach-Object {
            $_.Extension | Should -Be '.yaml'
        }
    }

    It 'All AppSource workflows should have the .yaml extension' {
        $AppSourceWorkflows | ForEach-Object {
            $_.Extension | Should -Be '.yaml'
        }
    }
}
