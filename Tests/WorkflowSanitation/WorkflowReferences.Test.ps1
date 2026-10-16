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
    It 'Validates local workflow references without a version suffix' {
        $path = Join-Path $TestDrive 'local-workflow.yaml'
        'uses: ./.github/workflows/_BuildALGoProject.yaml' | Set-Content -LiteralPath $path -Encoding UTF8
        { TestWorkflowReferences -YamlPath $path } | Should -Not -Throw

        'uses: ./unapproved/_BuildALGoProject.yaml' | Set-Content -LiteralPath $path -Encoding UTF8
        { TestWorkflowReferences -YamlPath $path } | Should -Throw

        'uses: ./.github/workflows/../../unapproved.yaml' | Set-Content -LiteralPath $path -Encoding UTF8
        { TestWorkflowReferences -YamlPath $path } | Should -Throw

        'uses: "./unapproved/workflow.yaml"' | Set-Content -LiteralPath $path -Encoding UTF8
        { TestWorkflowReferences -YamlPath $path } | Should -Throw
    }

    It 'Continues to validate versioned workflow references' {
        $path = Join-Path $TestDrive 'versioned-workflow.yaml'
        'uses: external/repo/.github/workflows/build.yaml@main' | Set-Content -LiteralPath $path -Encoding UTF8
        { TestWorkflowReferences -YamlPath $path } | Should -Throw
    }

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
