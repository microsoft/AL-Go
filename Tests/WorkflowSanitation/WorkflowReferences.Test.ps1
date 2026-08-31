Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-Go workflows should reference actions from approved repositories" {
    It 'All PTE workflows reference actions from approved repositories' {
        (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows reference actions from approved repositories' {
        (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestActionsReferences -YamlPath $_.FullName
        }
    }
}

Describe "All AL-Go workflows should reference approved reusable workflows" {
    It 'All PTE workflows reference approved reusable workflows' {
        (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }

    It 'All AppSource workflows reference approved reusable workflows' {
        (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath | ForEach-Object {
            TestWorkflowReferences -YamlPath $_.FullName
        }
    }
}
