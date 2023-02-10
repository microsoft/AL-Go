

function Test-ALGOActionsAreComingFromMicrosoft {
    param(
        [Parameter(Mandatory)]
        [string]$YamlPath
    )

    $yaml = Get-Content -Path $YamlPath -Raw
    $pattern = '\w*/AL-Go-Actions/'
    $actions = [regex]::matches($yaml, $pattern)

    $actions | ForEach-Object {
        $action = $_.Value
        $action | Should -BeLike "microsoft/AL-Go-Actions/"
    }
}

function Test-AllWorkflowsInPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $workflows = Get-ChildItem -Path $Path -Filter "*.yaml" -Recurse
    $workflows | ForEach-Object {
        Test-ALGOActionsAreComingFromMicrosoft -YamlPath $_.FullName
    }
}

Describe "All AL-GO Actions should be coming from the microsoft/AL-Go-Actions repository" {

    It 'All PTE workflows are referencing the microsoft/AL-Go-Actions' {
        $workflowsFolder = (Join-Path $PSScriptRoot "..\Templates\Per Tenant Extension\.github\workflows\" -Resolve)
        Test-AllWorkflowsInPath -Path $workflowsFolder
    }

    It 'All AppSource workflows are referencing the microsoft/AL-Go-Actions' {
        $workflowsFolder = (Join-Path $PSScriptRoot "..\Templates\AppSource App\.github\workflows\" -Resolve)
        Test-AllWorkflowsInPath -Path $workflowsFolder
    }
}
