Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
Import-Module (Join-Path $PSScriptRoot "..\Actions\TelemetryHelper.psm1")
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

    It 'Test that Update AL-Go System Files uses fixes runs-on' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $updateYamlFile = Join-Path $scriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\UpdateGitHubGoSystemFiles.yaml"
        $updateYaml = [Yaml]::Load($updateYamlFile)
        $updateYaml.content | Where-Object { $_ -like '*runs-on:*' } | ForEach-Object {
            $_.Trim() | Should -Be 'runs-on: windows-latest' -Because "Expected 'runs-on: windows-latest', in order to hardcode runner to windows-latest, but got $_"
        }
    }
}

Describe('YamlClass Tests') {
    BeforeAll {
        $actionName = "CheckForUpdates"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptRoot', Justification = 'False positive.')]
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve

        Mock Trace-Information {}
    }

    It 'Test YamlClass' {
        . (Join-Path $scriptRoot "yamlclass.ps1")
        $yaml = [Yaml]::load((Join-Path $PSScriptRoot 'YamlSnippet.txt'))

        # Yaml file should have 77 entries
        $yaml.content.Count | Should -be 74

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
        $start | Should -be 24
        $count | Should -be 19

        # Replace all occurances of 'shell: powershell' with 'shell: pwsh'
        $yaml.ReplaceAll('shell: powershell','shell: pwsh')
        $yaml.content[46].Trim() | Should -be 'shell: pwsh'

        # Replace Permissions
        $yaml.Replace('Permissions:/',@('contents: write','actions: read'))
        $yaml.content[44].Trim() | Should -be 'shell: pwsh'
        $yaml.content.Count | Should -be 72

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

    It 'Test YamlClass GetCustomJobsFromYaml' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $customizedYaml = [Yaml]::load((Join-Path $PSScriptRoot 'CustomizedYamlSnippet-All.txt'))
        $nonCustomizedYaml = [Yaml]::load((Join-Path $PSScriptRoot 'YamlSnippet.txt'))

        # Get Custom jobs from yaml
        $customJobs = $customizedYaml.GetCustomJobsFromYaml('CustomJob*')
        $customJobs | Should -Not -BeNullOrEmpty
        $customJobs.Count | Should -be 2

        $customJobs[0].Name | Should -Be 'CustomJob-MyFinalJob'
        $customJobs[0].Origin | Should -Be 'FinalRepository'

        $customJobs[1].Name | Should -Be 'CustomJob-MyCustomTemplateJob'
        $customJobs[1].Origin | Should -Be 'TemplateRepository'

        $emptyCustomJobs = $nonCustomizedYaml.GetCustomJobsFromYaml('CustomJob*')
        $emptyCustomJobs | Should -BeNullOrEmpty
    }

    It 'Test YamlClass AddCustomJobsToYaml' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $customTemplateYaml = [Yaml]::load((Join-Path $PSScriptRoot 'CustomizedYamlSnippet-TemplateRepository.txt'))
        $finalRepositoryYaml = [Yaml]::load((Join-Path $PSScriptRoot 'CustomizedYamlSnippet-FinalRepository.txt'))
        $nonCustomizedYaml = [Yaml]::load((Join-Path $PSScriptRoot 'YamlSnippet.txt'))

        $customTemplateJobs = $customTemplateYaml.GetCustomJobsFromYaml('CustomJob*')
        $customTemplateJobs | Should -Not -BeNullOrEmpty
        $customTemplateJobs.Count | Should -be 1
        $customTemplateJobs[0].Name | Should -Be 'CustomJob-MyCustomTemplateJob'
        $customTemplateJobs[0].Origin | Should -Be 'FinalRepository' # Custom template job has FinalRepository as origin when in the template itself

        # Add the custom job to the non-customized yaml
        $nonCustomizedYaml.AddCustomJobsToYaml($customTemplateJobs, [CustomizationOrigin]::TemplateRepository)

        $nonCustomizedYaml.content -join "`r`n" | Should -Be ($finalRepositoryYaml.content -join "`r`n")

        # Adding the jobs again doesn't have an effect
        $nonCustomizedYaml.AddCustomJobsToYaml($customTemplateJobs, [CustomizationOrigin]::TemplateRepository)

        $nonCustomizedYaml.content -join "`r`n" | Should -Be ($finalRepositoryYaml.content -join "`r`n")
    }

    It('Test YamlClass ApplyTemplateCustomizations') {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $srcContent = Get-Content (Join-Path $PSScriptRoot 'YamlSnippet.txt')
        $resultContent = Get-Content (Join-Path $PSScriptRoot 'CustomizedYamlSnippet-FinalRepository.txt')

        [Yaml]::ApplyTemplateCustomizations([ref] $srcContent, (Join-Path $PSScriptRoot 'CustomizedYamlSnippet-TemplateRepository.txt'))

        $srcContent | Should -Be ($resultContent -join "`n")
    }

    It('Test YamlClass ApplyFinalCustomizations') {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $srcContent = Get-Content (Join-Path $PSScriptRoot 'YamlSnippet.txt')
        $resultContent = Get-Content (Join-Path $PSScriptRoot 'CustomizedYamlSnippet-TemplateRepository.txt')

        [Yaml]::ApplyFinalCustomizations([ref] $srcContent, (Join-Path $PSScriptRoot 'CustomizedYamlSnippet-TemplateRepository.txt')) # Threat the template repo as a final repo

        $srcContent | Should -Be ($resultContent -join "`n")
    }
}

Describe "CheckForUpdates Action: CheckForUpdates.HelperFunctions.ps1" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        Import-Module (Join-Path $scriptRoot "..\Github-Helper.psm1") -DisableNameChecking -Force
        Import-Module (Join-Path $scriptRoot "..\.Modules\ReadSettings.psm1") -DisableNameChecking -Force
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

    It 'GetModifiedSettingsContent returns correct content when destination file is not empty' {
        # Create settings files with the content
        @{ "`$schema" = "someSchema"; "srcSetting" = "value1" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpSrcFile -Force
        @{ "setting1" = "value2" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpDstFile -Force

        $modifiedContentJson = GetModifiedSettingsContent -srcSettingsFile $tmpSrcFile -dstSettingsFile $tmpDstFile

        $modifiedContent = $modifiedContentJson | ConvertFrom-Json
        $modifiedContent | Should -Not -BeNullOrEmpty
        $modifiedContent.PSObject.Properties.Name.Count | Should -Be 2 # setting1 and $schema
        $modifiedContent."setting1" | Should -Be "value2"
        $modifiedContent."`$schema" | Should -Be "someSchema"
    }

    It 'GetModifiedSettingsContent returns correct content when destination file is empty' {
        # Create only the source file
        @{ "`$schema" = "someSchema"; "srcSetting" = "value1" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpSrcFile -Force
        '' | Out-File -FilePath $tmpDstFile -Force
        $modifiedContentJson = GetModifiedSettingsContent -srcSettingsFile $tmpSrcFile -dstSettingsFile $tmpDstFile

        $modifiedContent = $modifiedContentJson | ConvertFrom-Json
        $modifiedContent | Should -Not -BeNullOrEmpty
        @($modifiedContent.PSObject.Properties.Name).Count | Should -Be 2 # srcSetting and $schema
        $modifiedContent."`$schema" | Should -Be "someSchema"
        $modifiedContent."srcSetting" | Should -Be "value1"
    }

    It 'GetModifiedSettingsContent returns correct content when destination file does not exist' {
        # Create only the source file
        @{ "`$schema" = "someSchema"; "srcSetting" = "value1" } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpSrcFile -Force

        Test-Path $tmpDstFile | Should -Be $false
        $modifiedContentJson = GetModifiedSettingsContent -srcSettingsFile $tmpSrcFile -dstSettingsFile $tmpDstFile

        $modifiedContent = $modifiedContentJson | ConvertFrom-Json
        $modifiedContent | Should -Not -BeNullOrEmpty
        $modifiedContent.PSObject.Properties.Name.Count | Should -Be 2 # srcSetting and $schema
        $modifiedContent."srcSetting" | Should -Be "value1"
        $modifiedContent."`$schema" | Should -Be "someSchema"
    }

    It 'ApplyWorkflowInputDefaults applies default values to workflow inputs' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with workflow_dispatch inputs
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      directCommit:",
            "        description: Direct Commit?",
            "        type: boolean",
            "        default: false",
            "      useGhTokenWorkflow:",
            "        description: Use GhTokenWorkflow?",
            "        type: boolean",
            "        default: false",
            "      updateVersionNumber:",
            "        description: Version number",
            "        required: false",
            "        default: ''",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest",
            "    steps:",
            "      - run: echo test"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with workflow input defaults
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "directCommit"; "value" = $true },
                        @{ "name" = "useGhTokenWorkflow"; "value" = $true },
                        @{ "name" = "updateVersionNumber"; "value" = "+0.1" }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the defaults were applied
        $yaml.Get('on:/workflow_dispatch:/inputs:/directCommit:/default:').content -join '' | Should -Be 'default: true'
        $yaml.Get('on:/workflow_dispatch:/inputs:/useGhTokenWorkflow:/default:').content -join '' | Should -Be 'default: true'
        $yaml.Get('on:/workflow_dispatch:/inputs:/updateVersionNumber:/default:').content -join '' | Should -Be "default: '+0.1'"
    }

    It 'ApplyWorkflowInputDefaults handles workflows without workflow_dispatch' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML without workflow_dispatch
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  push:",
            "    branches: [ main ]",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest",
            "    steps:",
            "      - run: echo test"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with workflow input defaults
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "directCommit"; "value" = $true }
                    )
                }
            )
        }

        # Apply the defaults - should not throw
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
    }

    It 'ApplyWorkflowInputDefaults handles non-matching workflow names' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      directCommit:",
            "        description: Direct Commit?",
            "        type: boolean",
            "        default: false",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with workflow input defaults for a different workflow
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Other Workflow"
                    "defaults" = @(
                        @{ "name" = "directCommit"; "value" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the defaults were NOT applied (original value preserved)
        $yaml.Get('on:/workflow_dispatch:/inputs:/directCommit:/default:').content -join '' | Should -Be 'default: false'
    }

    It 'ApplyWorkflowInputDefaults handles inputs without existing default' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with input without default
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      myInput:",
            "        description: My Input",
            "        required: false",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with workflow input defaults
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "myInput"; "value" = "test-value" }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the default was added
        $defaultLine = $yaml.Get('on:/workflow_dispatch:/inputs:/myInput:/default:')
        $defaultLine | Should -Not -BeNullOrEmpty
        $defaultLine.content -join '' | Should -Be "default: 'test-value'"
    }

    It 'ApplyWorkflowInputDefaults handles different value types' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      boolInput:",
            "        type: boolean",
            "        default: false",
            "      stringInput:",
            "        type: string",
            "        default: ''",
            "      numberInput:",
            "        type: number",
            "        default: 0",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with different value types
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "boolInput"; "value" = $true },
                        @{ "name" = "stringInput"; "value" = "test" },
                        @{ "name" = "numberInput"; "value" = 42 }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the defaults were applied with correct types
        $yaml.Get('on:/workflow_dispatch:/inputs:/boolInput:/default:').content -join '' | Should -Be 'default: true'
        $yaml.Get('on:/workflow_dispatch:/inputs:/stringInput:/default:').content -join '' | Should -Be "default: 'test'"
        $yaml.Get('on:/workflow_dispatch:/inputs:/numberInput:/default:').content -join '' | Should -Be 'default: 42'
    }

    It 'ApplyWorkflowInputDefaults validates boolean type mismatch' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with boolean input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      boolInput:",
            "        type: boolean",
            "        default: false",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with wrong type (string instead of boolean)
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "boolInput"; "value" = "not a boolean" }
                    )
                }
            )
        }

        # Apply the defaults - should throw validation error
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected boolean value*"
    }

    It 'ApplyWorkflowInputDefaults validates number type mismatch' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with number input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      numberInput:",
            "        type: number",
            "        default: 0",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with wrong type (string instead of number)
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "numberInput"; "value" = "not a number" }
                    )
                }
            )
        }

        # Apply the defaults - should throw validation error
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected number value*"
    }

    It 'ApplyWorkflowInputDefaults validates string type mismatch' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with string input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      stringInput:",
            "        type: string",
            "        default: ''",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with wrong type (boolean instead of string)
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "stringInput"; "value" = $true }
                    )
                }
            )
        }

        # Apply the defaults - should throw validation error
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected string value*"
    }

    It 'ApplyWorkflowInputDefaults validates choice type' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with choice input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      choiceInput:",
            "        type: choice",
            "        options:",
            "          - option1",
            "          - option2",
            "        default: option1",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with correct type (string for choice)
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "choiceInput"; "value" = "option2" }
                    )
                }
            )
        }

        # Apply the defaults - should succeed
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
        $yaml.Get('on:/workflow_dispatch:/inputs:/choiceInput:/default:').content -join '' | Should -Be "default: 'option2'"
    }

    It 'ApplyWorkflowInputDefaults validates choice value is in available options' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with choice input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      choiceInput:",
            "        type: choice",
            "        options:",
            "          - option1",
            "          - option2",
            "          - option3",
            "        default: option1",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with invalid choice value
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "choiceInput"; "value" = "invalidOption" }
                    )
                }
            )
        }

        # Apply the defaults - should throw validation error
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*not a valid choice*"
    }

    It 'ApplyWorkflowInputDefaults validates choice value with case-sensitive matching' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with choice input using mixed case options
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      releaseTypeInput:",
            "        type: choice",
            "        options:",
            "          - Release",
            "          - Prerelease",
            "          - Draft",
            "        default: Release",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Test 1: Exact case match should succeed
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "releaseTypeInput"; "value" = "Prerelease" }
                    )
                }
            )
        }

        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
        $yaml.Get('on:/workflow_dispatch:/inputs:/releaseTypeInput:/default:').content -join '' | Should -Be "default: 'Prerelease'"

        # Test 2: Wrong case should fail with case-sensitive error message
        $yaml2 = [Yaml]::new($yamlContent)
        $repoSettings2 = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "releaseTypeInput"; "value" = "prerelease" }
                    )
                }
            )
        }

        { ApplyWorkflowInputDefaults -yaml $yaml2 -repoSettings $repoSettings2 -workflowName "Test Workflow" } |
            Should -Throw "*case-sensitive match required*"

        # Test 3: Uppercase version should also fail
        $yaml3 = [Yaml]::new($yamlContent)
        $repoSettings3 = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "releaseTypeInput"; "value" = "PRERELEASE" }
                    )
                }
            )
        }

        { ApplyWorkflowInputDefaults -yaml $yaml3 -repoSettings $repoSettings3 -workflowName "Test Workflow" } |
            Should -Throw "*case-sensitive match required*"
    }

    It 'ApplyWorkflowInputDefaults handles inputs without type specification' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML without type (defaults to string)
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      noTypeInput:",
            "        description: Input without type",
            "        default: ''",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with string value (should work without warning)
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "noTypeInput"; "value" = "string value" }
                    )
                }
            )
        }

        # Apply the defaults - should succeed
        { ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
        $yaml.Get('on:/workflow_dispatch:/inputs:/noTypeInput:/default:').content -join '' | Should -Be "default: 'string value'"
    }

    It 'ApplyWorkflowInputDefaults escapes single quotes in string values' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with string input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      nameInput:",
            "        type: string",
            "        default: ''",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with string value containing single quote
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "nameInput"; "value" = "O'Brien" }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify single quote is escaped per YAML spec (doubled)
        $yaml.Get('on:/workflow_dispatch:/inputs:/nameInput:/default:').content -join '' | Should -Be "default: 'O''Brien'"
    }
}

