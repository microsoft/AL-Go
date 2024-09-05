Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-Go workflows should have the .yaml extension" {
    It 'All PTE workflows should have the .yaml extension' {
        (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            $_.Extension | Should -Be '.yaml'
        }
    }

    It 'All AppSource workflows should have the .yaml extension' {
        (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            $_.Extension | Should -Be '.yaml'
        }
    }
}
