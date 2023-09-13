Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "CheckForUpdates Action Tests" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
            "workflows" = "write"
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    It 'Test YamlClass' {
        . (Join-Path $scriptRoot "yamlclass.ps1")
        $yaml = [Yaml]::load((Join-Path $PSScriptRoot 'YamlSnippet.txt'))

        # Yaml file should have 77 entries
        $yaml.content.Count | Should -be 77

        $start = 0; $count = 0
        # Locate lines for permissions section (including permissions: line)
        $yaml.Find('permissions:', [ref] $start, [ref] $count) | Should -be $true
        $start | Should -be 17
        $count | Should -be 5

        # Locate lines for permissions section (excluding permissions: line)
        $yaml.Find('permissions:/', [ref] $start, [ref] $count) | Should -be $true
        $start | Should -be 18
        $count | Should -be 4

        # Get Yaml class for permissions section (excluding permissions: line)
        $yaml.Get('permissions:/').content | ForEach-Object { $_ | Should -not -belike ' *' }

        # Locate section called permissionos (should return false)
        $yaml.Find('permissionos:', [ref] $start, [ref] $count)  | Should -Not -be $true

        # Check checkout step
        ($yaml.Get('jobs:/Initialization:/steps:/- name: Checkout').content -join '') | Should -be "- name: Checkout  uses: actions/checkout@v3  with:    lfs: true"

        # Get Shell line in read Settings step
        ($yaml.Get('jobs:/Initialization:/steps:/- name: Read settings/with:/shell:').content -join '')  | Should -be "shell: powershell"

        # Get Jobs section (without the jobs: line)
        $jobsYaml = $yaml.Get('jobs:/')

        # Locate CheckForUpdates
        $jobsYaml.Find('CheckForUpdates:', [ref] $start, [ref] $count) | Should -be $true
        $start | Should -be 25
        $count | Should -be 21

        # Replace all occurances of 'shell: powershell' with 'shell: pwsh'
        $yaml.ReplaceAll('shell: powershell','shell: pwsh')
        $yaml.content[46].Trim() | Should -be 'shell: pwsh'

        # Replace Permissions
        $yaml.Replace('Permissions:/',@('contents: write','actions: read'))
        $yaml.content[44].Trim() | Should -be 'shell: pwsh'
        $yaml.content.Count | Should -be 75

        # Get Jobs section (without the jobs: line)
        $jobsYaml = $yaml.Get('jobs:/')
        ($jobsYaml.Get('Initialization:/steps:/- name: Read settings/with:/shell:').content -join '') | Should -be "shell: pwsh"
    }

    # Call action
}
