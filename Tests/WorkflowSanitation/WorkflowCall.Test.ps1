Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "AL-Go workflows supporting workflow_call should follow the reusable workflow contract" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\..\Actions\CheckForUpdates\yamlclass.ps1')

        <#
         .SYNOPSIS
          Gets the steps in a workflow, which use a specific AL-Go action.
         .DESCRIPTION
          Returns an object for every step using the action, with the line number of the uses: line and the lines of the step (from the - line to the next step).
         .PARAMETER lines
          The lines of the workflow file.
         .PARAMETER actionName
          The name of the AL-Go action (e.g. ReadSettings).
         .EXAMPLE
          GetActionSteps -lines (Get-Content -Path $workflowFile -Encoding UTF8) -actionName 'ReadSettings'
        #>
        function GetActionSteps {
            Param(
                [string[]] $lines,
                [string] $actionName
            )

            for ($idx = 0; $idx -lt $lines.Count; $idx++) {
                if ($lines[$idx] -match "^\s*(-\s+)?uses:\s+microsoft/AL-Go-Actions/$actionName@") {
                    # Find the start of the step (the line starting with -)
                    $start = $idx
                    while ($start -gt 0 -and $lines[$start] -notmatch '^\s*-\s') { $start-- }
                    $indent = $lines[$start].IndexOf('-')
                    # Find the end of the step (next line with the same or less indentation, which isn't empty)
                    $end = $start + 1
                    while ($end -lt $lines.Count -and ($lines[$end].Trim() -eq '' -or ($lines[$end].Length - $lines[$end].TrimStart().Length) -gt $indent)) { $end++ }
                    [PSCustomObject]@{
                        "line" = $idx + 1
                        "content" = @($lines[$start..($end - 1)] | ForEach-Object { $_.Trim() })
                    }
                }
            }
        }

        <#
         .SYNOPSIS
          Gets the inputs of a workflow trigger as a hashtable of input name and input properties.
         .PARAMETER yaml
          The workflow loaded as a Yaml object.
         .PARAMETER trigger
          The trigger (workflow_dispatch or workflow_call).
         .EXAMPLE
          GetTriggerInputs -yaml $yaml -trigger 'workflow_call'
        #>
        function GetTriggerInputs {
            Param(
                [Yaml] $yaml,
                [string] $trigger
            )

            $inputs = [ordered]@{}
            $inputsYaml = $yaml.Get("on:/$($trigger):/inputs:/")
            if ($inputsYaml) {
                foreach($inputLine in $inputsYaml.GetNextLevel('')) {
                    $inputName = $inputLine.TrimEnd(':')
                    $inputs."$inputName" = @{
                        "description" = $inputsYaml.GetProperty("$inputLine/description:")
                        "type" = $inputsYaml.GetProperty("$inputLine/type:")
                        "required" = $inputsYaml.GetProperty("$inputLine/required:")
                        "default" = $inputsYaml.GetProperty("$inputLine/default:")
                    }
                }
            }
            return $inputs
        }
    }

    $testCases = @(
        foreach($template in @('Per Tenant Extension', 'AppSource App')) {
            Get-ChildItem -Path (Join-Path $PSScriptRoot "..\..\Templates\$template\.github\workflows" -Resolve) -Filter '*.yaml' |
                Where-Object { -not $_.Name.StartsWith('_') } |
                Where-Object { (Get-Content -Path $_.FullName -Encoding UTF8) -match '^\s{2}workflow_call:' } |
                ForEach-Object { @{ "template" = $template; "workflow" = $_.Name; "path" = $_.FullName } }
        }
    )

    It 'There are workflows supporting workflow_call' -TestCases @(@{ "count" = $testCases.Count }) {
        param($count)
        $count | Should -BeGreaterThan 0
    }

    It '<template>/<workflow> has a required caller input' -TestCases $testCases {
        param($template, $workflow, $path)
        $callInputs = GetTriggerInputs -yaml ([Yaml]::Load($path)) -trigger 'workflow_call'
        $callInputs.Keys | Should -Contain 'caller'
        $callInputs.caller.type | Should -Be 'string'
        $callInputs.caller.required | Should -Be 'true'
    }

    It '<template>/<workflow> mirrors workflow_dispatch inputs in workflow_call' -TestCases $testCases {
        param($template, $workflow, $path)
        $yaml = [Yaml]::Load($path)
        $dispatchInputs = GetTriggerInputs -yaml $yaml -trigger 'workflow_dispatch'
        $callInputs = GetTriggerInputs -yaml $yaml -trigger 'workflow_call'
        (@($callInputs.Keys | Where-Object { $_ -ne 'caller' }) -join ', ') | Should -Be (@($dispatchInputs.Keys) -join ', ') -Because "workflow_call inputs (except caller) should be the same as workflow_dispatch inputs"
        foreach($inputName in $dispatchInputs.Keys) {
            $dispatchInput = $dispatchInputs."$inputName"
            $callInput = $callInputs."$inputName"
            # workflow_call inputs must have a type. Untyped and choice workflow_dispatch inputs are strings
            $expectedType = $dispatchInput.type
            if (-not $expectedType -or $expectedType -eq 'choice') { $expectedType = 'string' }
            $callInput.type | Should -Be $expectedType -Because "type of input $inputName"
            $callInput.description | Should -Be $dispatchInput.description -Because "description of input $inputName"
            $callInput.required | Should -Be $dispatchInput.required -Because "required of input $inputName"
            if ($callInput.required -eq 'true') {
                # The default value of a required workflow_call input is never used (and flagged by actionlint)
                $callInput.default | Should -BeNullOrEmpty -Because "required input $inputName should not have a default value"
            }
            else {
                $callInput.default | Should -Be $dispatchInput.default -Because "default of input $inputName"
            }
        }
    }

    It '<template>/<workflow> defines WorkflowEventName and WorkflowName' -TestCases $testCases {
        param($template, $workflow, $path)
        $yaml = [Yaml]::Load($path)
        $workflowName = $yaml.GetProperty('name:').Trim("'").Trim('"')
        $yaml.GetProperty('env:/WorkflowEventName:') | Should -Be "`${{ inputs.caller && 'workflow_call' || github.event_name }}"
        $yaml.GetProperty('env:/WorkflowName:') | Should -Be "`${{ inputs.caller && '$workflowName' || github.workflow }}"
        # The env context isn't available everywhere (e.g. concurrency or with: of reusable workflow jobs), where the workflow name is repeated
        foreach($match in ([regex]::Matches(($yaml.content -join "`n"), "inputs\.caller && '([^']*)' \|\| github\.workflow"))) {
            $match.Groups[1].Value | Should -Be $workflowName -Because "the name of the workflow is used when called"
        }
    }

    It '<template>/<workflow> does not use the event payload or the event name of the caller' -TestCases $testCases {
        param($template, $workflow, $path)
        $lines = Get-Content -Path $path -Encoding UTF8
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            $line = $lines[$idx]
            $line | Should -Not -Match 'github\.event\.inputs' -Because "line $($idx + 1) should use inputs instead of github.event.inputs"
            $line | Should -Not -Match '\$env:GITHUB_EVENT_NAME' -Because "line $($idx + 1) should use env:WorkflowEventName instead of env:GITHUB_EVENT_NAME"
            if ($line -notmatch '^\s*WorkflowEventName:') {
                $line | Should -Not -Match 'github\.event_name' -Because "line $($idx + 1) should use env.WorkflowEventName instead of github.event_name"
            }
            if ($line -notmatch 'inputs\.caller &&' -and $line -notmatch '^\s*description:') {
                $line | Should -Not -Match 'github\.workflow\b(?!_)' -Because "line $($idx + 1) should use env.WorkflowName instead of github.workflow"
            }
        }
    }

    It '<template>/<workflow> passes the reusable workflow overrides to AL-Go actions' -TestCases $testCases {
        param($template, $workflow, $path)
        $lines = Get-Content -Path $path -Encoding UTF8
        $expectedWith = @{
            "ReadSettings" = @('workflowName: ${{ env.WorkflowName }}')
            "ValidateWorkflowInput" = @('workflowName: ${{ env.WorkflowName }}', 'inputsJson: ${{ toJson(inputs) }}')
            "DumpWorkflowInfo" = @('workflowEventName: ${{ env.WorkflowEventName }}', 'inputsJson: ${{ toJson(inputs) }}')
            "DetermineProjectsToBuild" = @('workflowEventName: ${{ env.WorkflowEventName }}')
            "GetWorkflowMultiRunBranches" = @('workflowEventName: ${{ env.WorkflowEventName }}')
        }
        foreach($actionName in $expectedWith.Keys) {
            foreach($step in (GetActionSteps -lines $lines -actionName $actionName)) {
                foreach($expected in $expectedWith."$actionName") {
                    $step.content | Should -Contain $expected -Because "the $actionName step at line $($step.line) should pass $expected"
                }
            }
        }
    }

    It '<template>/<workflow> passes the workflow name to _BuildALGoProject' -TestCases $testCases {
        param($template, $workflow, $path)
        $lines = Get-Content -Path $path -Encoding UTF8
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            if ($lines[$idx] -match '^\s*uses:\s+\./\.github/workflows/_BuildALGoProject\.yaml') {
                # The job ends at the next line with an indentation of 2 or less (next job)
                $end = $idx + 1
                while ($end -lt $lines.Count -and ($lines[$end].Trim() -eq '' -or $lines[$end] -match '^\s{3,}')) { $end++ }
                $jobLines = @($lines[$idx..($end - 1)] | ForEach-Object { $_.Trim() })
                @($jobLines | Where-Object { $_ -match "^workflowName: \$\{\{ inputs\.caller && '[^']*' \|\| github\.workflow \}\}$" }).Count | Should -Be 1 -Because "the job calling _BuildALGoProject at line $($idx + 1) should pass workflowName"
            }
        }
    }

    It '<template>/<workflow> passes the workflow name to _BuildPowerPlatformSolution' -TestCases $testCases {
        param($template, $workflow, $path)
        $lines = Get-Content -Path $path -Encoding UTF8
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            if ($lines[$idx] -match '^\s*uses:\s+\./\.github/workflows/_BuildPowerPlatformSolution\.yaml') {
                # The job ends at the next line with an indentation of 2 or less (next job)
                $end = $idx + 1
                while ($end -lt $lines.Count -and ($lines[$end].Trim() -eq '' -or $lines[$end] -match '^\s{3,}')) { $end++ }
                $jobLines = @($lines[$idx..($end - 1)] | ForEach-Object { $_.Trim() })
                @($jobLines | Where-Object { $_ -match "^workflowName: \$\{\{ inputs\.caller && '[^']*' \|\| github\.workflow \}\}$" }).Count | Should -Be 1 -Because "the job calling _BuildPowerPlatformSolution at line $($idx + 1) should pass workflowName"
            }
        }
    }
}
