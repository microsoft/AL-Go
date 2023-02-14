Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')


Describe "All AL-GO Actions should be coming from the microsoft/AL-Go-Actions repository" {

    It 'All PTE workflows are referencing the microsoft/AL-Go-Actions' {
        $workflowsFolder = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve)
        TestAllWorkflowsInPath -Path $workflowsFolder
    }

    It 'All AppSource workflows are referencing the microsoft/AL-Go-Actions' {
        $workflowsFolder = (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve)
        TestAllWorkflowsInPath -Path $workflowsFolder
    }
}
