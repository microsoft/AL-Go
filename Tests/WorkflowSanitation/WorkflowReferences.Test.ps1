Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-Go workflows should reference actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)" {
    It 'All PTE workflows are referencing actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)' {
        (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows are referencing actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)' {
        (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }
}

Describe "All AL-Go workflows should reference reusable workflows from the same repository" {
    It 'All PTE workflows are referencing reusable workflows from the same repository ' {
        (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows are referencing reusable workflows from the same repository ' {
        (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }
}
