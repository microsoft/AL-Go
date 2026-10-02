Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "DumpWorkflowInfo Action Tests" {
    BeforeAll {
        $actionName = "DumpWorkflowInfo"
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

    Context 'Dump inputs' {
        BeforeEach {
            Mock Write-Host { }
            $eventPathFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).json"
            @{ inputs = @{ fromEvent = 'eventValue' } } | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 -Path $eventPathFile
            $env:GITHUB_EVENT_PATH = $eventPathFile
        }

        AfterEach {
            Remove-Item -Path $eventPathFile -Force -ErrorAction SilentlyContinue
            Remove-Item env:GITHUB_EVENT_PATH -ErrorAction SilentlyContinue
        }

        It 'Dumps inputs from the event payload for workflow_dispatch' {
            . $scriptPath -workflowEventName 'workflow_dispatch'
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "- fromEvent = 'eventValue'" }
        }

        It 'Dumps inputs from inputsJson for workflow_call' {
            $inputsJson = @{ caller = 'Orchestrator'; directCommit = $true } | ConvertTo-Json -Compress
            . $scriptPath -workflowEventName 'workflow_call' -inputsJson $inputsJson
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "Event name: workflow_call" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "- caller = 'Orchestrator'" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "- directCommit = 'True'" }
            Should -Invoke Write-Host -Exactly 0 -ParameterFilter { $Object -eq "- fromEvent = 'eventValue'" }
        }

        It 'Does not dump inputs for other events' {
            . $scriptPath -workflowEventName 'push'
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "Event name: push" }
            Should -Invoke Write-Host -Exactly 0 -ParameterFilter { $Object -eq "Inputs:" }
        }
    }
}
