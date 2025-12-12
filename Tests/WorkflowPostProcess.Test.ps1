Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
Import-Module (Join-Path $PSScriptRoot '..\Actions\.Modules\WorkflowPostProcessHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "WorkflowPostProcess Action Tests" {
    BeforeAll {
        $actionName = "WorkflowPostProcess"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # Call action

    It 'GetWorkflowDuration handles different culture formats correctly' {
        $endTimeUTC = [DateTime]::Parse("2025-12-12T10:00:01.0000000Z")

        # Test UTC start time
        $workflowDuration = GetWorkflowDuration -StartTime "2025-12-12T10:00:00.0000000Z" -EndTime $endTimeUTC
        $workflowDuration | Should -Be 1

        # Test en-US culture format
        $workflowDuration = GetWorkflowDuration -StartTime "12/12/2025 10:00:00 AM" -EndTime $endTimeUTC
        $workflowDuration | Should -Be 1

        # Test de-DE culture format
        $workflowDuration = GetWorkflowDuration -StartTime "12.12.2025 10:00:00" -EndTime $endTimeUTC
        $workflowDuration | Should -Be 1

        # Test da-DK culture format
        $workflowDuration = GetWorkflowDuration -StartTime "12-12-2025 10:00:00" -EndTime $endTimeUTC
        $workflowDuration | Should -Be 1
    }

}
