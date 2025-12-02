Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "GetWorkflowMultiRunBranches Action" {
    BeforeAll {
        $actionName = "GetWorkflowMultiRunBranches"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_ENV = [System.IO.Path]::GetTempFileName()
    }

    AfterEach {
        Remove-Item $env:GITHUB_OUTPUT
        Remove-Item $env:GITHUB_ENV
    }

    Context "Action tests" {
        It 'Compile Action' {
            Invoke-Expression $actionScript
        }

        It 'Test action.yaml matches script' {
            $outputs = [ordered]@{
                "Result" = "JSON-formatted object with branches property, an array of branch names"
            }
            YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
        }
    }

    Context 'workflow_dispatch event' {
        It 'Action sets the current branch as result when no branch patterns are specified' {
            $env:GITHUB_EVENT_NAME = "workflow_dispatch"
            $env:Settings = ""
            $env:GITHUB_REF_NAME = "main"

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1")

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"main`"]}"
        }

        It 'Action sets the input branch as result when a branch pattern is specified' {
            $env:GITHUB_EVENT_NAME = "workflow_dispatch"
            $env:Settings = ""
            $env:GITHUB_REF_NAME = "main"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/test-branch", "origin/main", "origin/some-other-branch", "origin") }

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1") -includeBranches "test-branch"

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"test-branch`"]}"
        }

        It 'Action sets the input branch as result when a branch pattern with wild card is specified' {
            $env:GITHUB_EVENT_NAME = "workflow_dispatch"
            $env:Settings = ""
            $env:GITHUB_REF_NAME = "main"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/test-branch", "origin/main", "origin/some-other-branch", "origin") }

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1") -includeBranches "*branch*"

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"test-branch`",`"some-other-branch`"]}"
        }

        It 'Action filters out HEAD symbolic reference when using wildcard' {
            $env:GITHUB_EVENT_NAME = "workflow_dispatch"
            $env:Settings = ""
            $env:GITHUB_REF_NAME = "main"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/HEAD", "origin/main", "origin/develop", "origin/feature-1") }

            # Call the action script with wildcard to get all branches
            . (Join-Path $scriptRoot "$actionName.ps1") -includeBranches "*"

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            # Verify that HEAD is not included in the result
            $outputValue | Should -Not -Match "HEAD"
            $outputValue | Should -Be "{`"branches`":[`"main`",`"develop`",`"feature-1`"]}"
        }
    }

    Context 'schedule event' {
        It 'Action sets the current branch as result when no branch patterns are specified' {
            $env:GITHUB_EVENT_NAME = "schedule"
            $env:Settings = "{ 'workflowSchedule': { 'includeBranches': [] } }"
            $env:GITHUB_REF_NAME = "default-branch"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/test-branch", "origin/main", "origin/default-branch", "origin") }

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1")

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"default-branch`"]}"
        }

        It 'Action sets the input branch as result when a branch pattern is specified' {
            $env:GITHUB_EVENT_NAME = "schedule"
            $env:Settings = "{ 'workflowSchedule': { 'includeBranches': ['test-branch'] } }"
            $env:GITHUB_REF_NAME = "main"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/test-branch", "origin/main", "origin/some-other-branch", "origin") }

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1") -includeBranches "some-random-branch" # This should be ignored

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"test-branch`"]}"
        }

        It 'Action sets the input branch as result when a branch pattern with wild card is specified' {
            $env:GITHUB_EVENT_NAME = "schedule"
            $env:Settings = "{ 'workflowSchedule': { 'includeBranches': ['*branch*'] } }"
            $env:GITHUB_REF_NAME = "main"

            Mock -CommandName invoke-git -ParameterFilter { $command -eq 'for-each-ref'}  -MockWith  { return @("origin/test-branch", "origin/main", "origin/some-other-branch", "origin") }

            # Call the action script
            . (Join-Path $scriptRoot "$actionName.ps1")

            $outputName, $outputValue = (Get-Content $env:GITHUB_OUTPUT) -split '='
            $outputName | Should -Be "Result"
            $outputValue | Should -Be "{`"branches`":[`"test-branch`",`"some-other-branch`"]}"
        }
    }
}
