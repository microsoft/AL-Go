Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-GO workflows should reference actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)" {
    BeforeAll {
        $AppSourceWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $PTEWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
    }

    It 'All PTE workflows are referencing actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)' {
        $PTEWorkflows | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows are referencing actions that come from the microsoft/AL-Go-Actions or actions/ (by GitHub)' {
        $AppSourceWorkflows | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }
}

Describe "All AL-GO workflows should reference reusable workflows from the same repository" {
    BeforeAll {
        $AppSourceWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $PTEWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
    }

    It 'All PTE workflows are referencing reusable workflows from the same repository ' {
        $PTEWorkflows | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows are referencing reusable workflows from the same repository ' {
        $AppSourceWorkflows | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }
}
