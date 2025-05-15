Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

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
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Test YamlClass' {
        . (Join-Path $scriptRoot "yamlclass.ps1")
        $yaml = [Yaml]::load((Join-Path $PSScriptRoot 'YamlSnippet.txt'))

        # Yaml file should have 77 entries
        $yaml.content.Count | Should -be 73

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
        ($yaml.Get('jobs:/Initialization:/steps:/- name: Checkout').content -join '') | Should -be "- name: Checkout  uses: actions/checkout@v4  with:    lfs: true"

        # Get Shell line in read Settings step
        ($yaml.Get('jobs:/Initialization:/steps:/- name: Read settings/with:/shell:').content -join '')  | Should -be "shell: powershell"

        # Get Jobs section (without the jobs: line)
        $jobsYaml = $yaml.Get('jobs:/')

        # Locate CheckForUpdates
        $jobsYaml.Find('CheckForUpdates:', [ref] $start, [ref] $count) | Should -be $true
        $start | Should -be 23
        $count | Should -be 19

        # Replace all occurances of 'shell: powershell' with 'shell: pwsh'
        $yaml.ReplaceAll('shell: powershell','shell: pwsh')
        $yaml.content[46].Trim() | Should -be 'shell: pwsh'

        # Replace Permissions
        $yaml.Replace('Permissions:/',@('contents: write','actions: read'))
        $yaml.content[44].Trim() | Should -be 'shell: pwsh'
        $yaml.content.Count | Should -be 71

        # Get Jobs section (without the jobs: line)
        $jobsYaml = $yaml.Get('jobs:/')
        ($jobsYaml.Get('Initialization:/steps:/- name: Read settings/with:/shell:').content -join '') | Should -be "shell: pwsh"
    }

    It 'Test YamlClass Remove' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlSnippet = @(
            "permissions:",
            "  contents: read",
            "  actions: read",
            "  pull-requests: write",
            "  checks: write"
        )

        $permissionsYaml = [Yaml]::new($yamlSnippet)

        $permissionsContent = $permissionsYaml.Get('permissions:/')
        $permissionsContent.content.Count | Should -be 4
        $permissionsContent.Remove(1, 0) # Remove nothing
        $permissionsContent.content.Count | Should -be 4
        $permissionsContent.content[0].Trim() | Should -be 'contents: read'
        $permissionsContent.content[1].Trim() | Should -be 'actions: read'
        $permissionsContent.content[2].Trim() | Should -be 'pull-requests: write'
        $permissionsContent.content[3].Trim() | Should -be 'checks: write'

        $permissionsContent = $permissionsYaml.Get('permissions:/')
        $permissionsContent.content.Count | Should -be 4
        $permissionsContent.Remove(0, 3) # Remove first 3 lines
        $permissionsContent.content.Count | Should -be 1
        $permissionsContent.content[0].Trim() | Should -be 'checks: write'

        $permissionsContent = $permissionsYaml.Get('permissions:/')
        $permissionsContent.content.Count | Should -be 4
        $permissionsContent.Remove(2, 1) # Remove only the 3rd line
        $permissionsContent.content.Count | Should -be 3
        $permissionsContent.content[0].Trim() | Should -be 'contents: read'
        $permissionsContent.content[1].Trim() | Should -be 'actions: read'
        $permissionsContent.content[2].Trim() | Should -be 'checks: write'

        $permissionsContent = $permissionsYaml.Get('permissions:/')
        $permissionsContent.content.Count | Should -be 4
        $permissionsContent.Remove(2, 4) # Remove more than the number of lines
        $permissionsContent.content.Count | Should -be 2 # Only the first two lines should remain
        $permissionsContent.content[0].Trim() | Should -be 'contents: read'
        $permissionsContent.content[1].Trim() | Should -be 'actions: read'
    }

    It 'Test that Update AL-Go System Files uses fixes runs-on' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $updateYamlFile = Join-Path $scriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\UpdateGitHubGoSystemFiles.yaml"
        $updateYaml = [Yaml]::Load($updateYamlFile)
        $updateYaml.content | Where-Object { $_ -like '*runs-on:*' } | ForEach-Object {
            $_.Trim() | Should -Be 'runs-on: windows-latest' -Because "Expected 'runs-on: windows-latest', in order to hardcode runner to windows-latest, but got $_"
        }
    }

    # Call action
}

Describe "CheckForUpdates Action: CheckForUpdates.HelperFunctions.ps1" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        Import-Module (Join-Path $scriptRoot "..\Github-Helper.psm1") -DisableNameChecking -Force
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $tmpSrcFile = Join-Path $PSScriptRoot "tempSrcFile.json"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $tmpDstFile = Join-Path $PSScriptRoot "tempDestFile.json"
    }

    AfterEach {
        # Clean up temporary files
        if (Test-Path $tmpSrcFile) {
            Remove-Item -Path $tmpSrcFile -Force
        }
        if (Test-Path $tmpDstFile) {
            Remove-Item -Path $tmpDstFile -Force
        }
    }

    It 'GetModifiedSettingsContent returns correct content when destination files isn''t empty' {
        # Create settings files with the content
        @{ "`$schema" = "someSchema"; "srcSetting" = "value1" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpSrcFile -Force
        @{ "setting1" = "value2" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpDstFile -Force

        $modifiedContentJson = GetModifiedSettingsContent -srcSettingsFile $tmpSrcFile -dstSettingsFile $tmpDstFile

        $modifiedContent = $modifiedContentJson | ConvertFrom-Json
        $modifiedContent | Should -Not -BeNullOrEmpty
        $modifiedContent.setting1 | Should -Be "value2"
        $modifiedContent."`$schema" | Should -Be "someSchema"
    }

    It 'GetModifiedSettingsContent returns correct content when destination files doesn''t exist' {
        # Create only the source file
        @{ "`$schema" = "someSchema"; "srcSetting" = "value1" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpSrcFile -Force

        $modifiedContentJson = GetModifiedSettingsContent -srcSettingsFile $tmpSrcFile -dstSettingsFile $tmpDstFile

        $modifiedContent = $modifiedContentJson | ConvertFrom-Json
        $modifiedContent | Should -Not -BeNullOrEmpty
        $modifiedContent.srcSetting | Should -Be "value1"
        $modifiedContent."`$schema" | Should -Be "someSchema"
    }
}
