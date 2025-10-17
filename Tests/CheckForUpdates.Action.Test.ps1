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

    It 'Test YamlClass ReplaceAll with regex - negative lookbehind and word boundaries' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlContent = @(
            "needs: [ inputs ]",
            "myOutput: `${{ needs.inputs.outputs.output }}",
            "myInput: `${{ inputs.output }}",
            "if: inputs.runTests == 'true'",
            "step: CreateInputs"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Replace "inputs.output" where "inputs" is NOT preceded by a dot (negative lookbehind)
        # and "output" is a complete word (word boundary)
        # This matches the actual pattern used in the hide feature: (?<!\.)inputs\.output\b
        $yaml.ReplaceAll("(?<!\.)inputs\.output\b", "REPLACED", $true)

        $yaml.content[0] | Should -Be "needs: [ inputs ]" # Should NOT be replaced (no .output)
        $yaml.content[1] | Should -Be "myOutput: `${{ needs.inputs.outputs.output }}" # Should NOT be replaced (preceded by dot in needs.inputs)
        $yaml.content[2] | Should -Be "myInput: `${{ REPLACED }}"
        $yaml.content[3] | Should -Be "if: inputs.runTests == 'true'" # Should NOT be replaced (.runTests, not .output)
        $yaml.content[4] | Should -Be "step: CreateInputs" # Should NOT be replaced (part of another word)
    }

    It 'Test YamlClass ReplaceAll with regex - pattern matching' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlContent = @(
            "version: 1.0.0",
            "version: 2.0.0",
            "version: 3.0.0",
            "other: value"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Replace version numbers using regex pattern
        $yaml.ReplaceAll("version: \d+\.\d+\.\d+", "version: 99.99.99", $true)

        $yaml.content[0] | Should -Be "version: 99.99.99"
        $yaml.content[1] | Should -Be "version: 99.99.99"
        $yaml.content[2] | Should -Be "version: 99.99.99"
        $yaml.content[3] | Should -Be "other: value" # Should NOT be replaced
    }

    It 'Test YamlClass ReplaceAll with regex - capture groups' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlContent = @(
            "runs-on: ubuntu-latest",
            "runs-on: windows-latest",
            "runs-on: macos-latest"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Use capture groups to swap OS names
        $yaml.ReplaceAll("runs-on: (ubuntu|windows|macos)-latest", "runs-on: custom-`$1-runner", $true)

        $yaml.content[0] | Should -Be "runs-on: custom-ubuntu-runner"
        $yaml.content[1] | Should -Be "runs-on: custom-windows-runner"
        $yaml.content[2] | Should -Be "runs-on: custom-macos-runner"
    }

    It 'Test YamlClass ReplaceAll with isRegex false uses literal replacement' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlContent = @(
            "pattern: \d+\.\d+",
            "value: 123.456"
        )

        $yaml = [Yaml]::new($yamlContent)

        # With isRegex=false, should do literal string replacement, not regex
        $yaml.ReplaceAll("\d+\.\d+", "REPLACED", $false)

        $yaml.content[0] | Should -Be "pattern: REPLACED"
        $yaml.content[1] | Should -Be "value: 123.456" # Should NOT be replaced (not a literal match)
    }

    It 'Test YamlClass ReplaceAll regex does not match across line boundaries' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        $yamlContent = @(
            "first: line",
            "second: line"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Try to match across lines - should not match anything
        $yaml.ReplaceAll("first.*second", "REPLACED", $true)

        $yaml.content[0] | Should -Be "first: line" # Should NOT be replaced
        $yaml.content[1] | Should -Be "second: line" # Should NOT be replaced
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

    It 'ApplyWorkflowInputDefaults hides boolean inputs when hide is true' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with boolean input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      visibleInput:",
            "        type: string",
            "        default: ''",
            "      hiddenInput:",
            "        type: boolean",
            "        default: false",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest",
            "    steps:",
            "      - name: Use input",
            "        run: echo `${{ github.event.inputs.hiddenInput }}"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "visibleInput"; "value" = "test" },
                        @{ "name" = "hiddenInput"; "value" = $true; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed from inputs
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('hiddenInput:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify the visible input still exists with updated default
        $inputs.Find('visibleInput:', [ref] $null, [ref] $null) | Should -Be $true
        $yaml.Get('on:/workflow_dispatch:/inputs:/visibleInput:/default:').content -join '' | Should -Be "default: 'test'"

        # Verify the reference was replaced with literal value
        $yaml.content -join "`n" | Should -Match "echo true"
        $yaml.content -join "`n" | Should -Not -Match "github\.event\.inputs\.hiddenInput"
    }

    It 'ApplyWorkflowInputDefaults hides string inputs and replaces references correctly' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with string input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      versionInput:",
            "        type: string",
            "        default: '+0.0'",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest",
            "    steps:",
            "      - name: Use version",
            "        run: echo `${{ inputs.versionInput }}",
            "      - name: Use version again",
            "        run: echo `${{ github.event.inputs.versionInput }}"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "versionInput"; "value" = "+0.1"; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('versionInput:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify both references were replaced with quoted string
        $content = $yaml.content -join "`n"
        $content | Should -Match "echo '\+0\.1'"
        $content | Should -Not -Match "inputs\.versionInput"
        $content | Should -Not -Match "github\.event\.inputs\.versionInput"
    }

    It 'ApplyWorkflowInputDefaults hides number inputs and replaces references correctly' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with number input
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      countInput:",
            "        type: number",
            "        default: 5",
            "jobs:",
            "  test:",
            "    runs-on: ubuntu-latest",
            "    steps:",
            "      - name: Use count",
            "        run: echo `${{ inputs.countInput }}"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "countInput"; "value" = 10; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('countInput:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify the reference was replaced with number (unquoted)
        $yaml.content -join "`n" | Should -Match "echo 10"
        $yaml.content -join "`n" | Should -Not -Match "inputs\.countInput"
    }

    It 'ApplyWorkflowInputDefaults replaces hidden input references in if conditions' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with input used in if condition (without ${{ }})
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      runTests:",
            "        type: boolean",
            "        default: false",
            "jobs:",
            "  test:",
            "    runs-on: windows-latest",
            "    if: github.event.inputs.runTests == 'true'",
            "    steps:",
            "      - name: Run",
            "        run: echo Running"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "runTests"; "value" = $true; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('runTests:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify the reference in if condition was replaced with string literal
        # Bare references in if conditions are always treated as strings in GitHub Actions
        # GitHub Actions comparisons are case-sensitive, so we use lowercase 'true'
        $yaml.content -join "`n" | Should -Match "if: 'true' == 'true'"
        $yaml.content -join "`n" | Should -Not -Match "github\.event\.inputs\.runTests"
    }

    It 'ApplyWorkflowInputDefaults does not replace job output references' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Create a test workflow YAML with needs.JobName.outputs.inputName pattern
        # This should NOT be replaced even if an input with the same name exists and is hidden
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      branch:",
            "        type: string",
            "        default: 'main'",
            "jobs:",
            "  Inputs:",
            "    runs-on: ubuntu-latest",
            "    outputs:",
            "      branch: `${{ steps.CreateInputs.outputs.branch }}",
            "    steps:",
            "      - name: Create inputs",
            "        id: CreateInputs",
            "        run: echo 'branch=main' >> `$GITHUB_OUTPUT",
            "  Deploy:",
            "    runs-on: ubuntu-latest",
            "    needs: [ Inputs ]",
            "    steps:",
            "      - name: Deploy",
            "        env:",
            "          branch: `${{ needs.Inputs.outputs.branch }}",
            "        run: echo Deploying to `$branch"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag for the branch input
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "branch"; "value" = "production"; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('branch:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify that needs.Inputs.outputs.branch is NOT replaced
        # This is a job output reference, not a workflow input reference
        $content = $yaml.content -join "`n"
        $content | Should -Match "needs\.Inputs\.outputs\.branch"

        # Verify that direct input references would be replaced if they existed
        # (but they don't exist in this workflow, so we just verify the job reference remains)
        $content | Should -Not -Match "github\.event\.inputs\.branch"
        $content | Should -Not -Match "`\$\{\{ inputs\.branch \}\}"
    }

    It 'ApplyWorkflowInputDefaults does not replace parts of job output references with input names like output' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Edge case: input named "output" should not replace "inputs.outputs.output" or "outputs.output"
        # Using lowercase "inputs" as job name to test the problematic case
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      output:",
            "        type: string",
            "        default: 'default'",
            "jobs:",
            "  inputs:",
            "    runs-on: ubuntu-latest",
            "    outputs:",
            "      output: `${{ steps.CreateInputs.outputs.output }}",
            "    steps:",
            "      - name: Create inputs",
            "        id: CreateInputs",
            "        run: echo 'output=test' >> `$GITHUB_OUTPUT",
            "  Deploy:",
            "    runs-on: ubuntu-latest",
            "    needs: [ inputs ]",
            "    steps:",
            "      - name: Deploy",
            "        env:",
            "          myOutput: `${{ needs.inputs.outputs.output }}",
            "        run: echo Using `$myOutput"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag for the "output" input
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "output"; "value" = "hidden"; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('output:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify that needs.inputs.outputs.output is NOT replaced
        $content = $yaml.content -join "`n"
        $content | Should -Match "needs\.inputs\.outputs\.output"
        $content | Should -Match "steps\.CreateInputs\.outputs\.output"

        # Verify that direct input references would be replaced if they existed
        $content | Should -Not -Match "github\.event\.inputs\.output"
        $content | Should -Not -Match "`\$\{\{ inputs\.output \}\}"
    }

    It 'ApplyWorkflowInputDefaults does not replace job output references when input is named outputs' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # Edge case: input named "outputs" should not replace "inputs.outputs" in job output contexts
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      outputs:",
            "        type: string",
            "        default: 'default'",
            "jobs:",
            "  Initialization:",
            "    runs-on: ubuntu-latest",
            "    outputs:",
            "      telemetryScopeJson: `${{ steps.init.outputs.telemetryScopeJson }}",
            "    steps:",
            "      - name: Initialize",
            "        id: init",
            "        run: echo 'telemetryScopeJson={}' >> `$GITHUB_OUTPUT",
            "  Deploy:",
            "    runs-on: ubuntu-latest",
            "    needs: [ Initialization ]",
            "    steps:",
            "      - name: Deploy",
            "        env:",
            "          telemetryScope: `${{ needs.Initialization.outputs.telemetryScopeJson }}",
            "        run: echo Using `$telemetryScope",
            "      - name: Use input",
            "        run: echo `${{ inputs.outputs }}"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag for the "outputs" input
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "outputs"; "value" = "hidden-value"; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputs.Find('outputs:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify that needs.Initialization.outputs.telemetryScopeJson is NOT replaced
        $content = $yaml.content -join "`n"
        $content | Should -Match "needs\.Initialization\.outputs\.telemetryScopeJson"
        $content | Should -Match "steps\.init\.outputs\.telemetryScopeJson"

        # Verify that the actual input reference WAS replaced
        $content | Should -Match "echo 'hidden-value'"
        $content | Should -Not -Match "github\.event\.inputs\.outputs"
        $content | Should -Not -Match "`\$\{\{ inputs\.outputs \}\}"
    }

    It 'ApplyWorkflowInputDefaults does not replace job outputs when job is named inputs and input is named outputs' {
        . (Join-Path $scriptRoot "yamlclass.ps1")

        # This is the real edge case: job named "inputs" (lowercase) with outputs, and an input also named "outputs"
        # needs.inputs.outputs.something should NOT be replaced (it's a job output reference)
        # but ${{ inputs.outputs }} should be replaced (it's a workflow input reference)
        $yamlContent = @(
            "name: 'Test Workflow'",
            "on:",
            "  workflow_dispatch:",
            "    inputs:",
            "      outputs:",
            "        type: string",
            "        default: 'default'",
            "jobs:",
            "  inputs:",
            "    runs-on: ubuntu-latest",
            "    outputs:",
            "      myValue: `${{ steps.init.outputs.myValue }}",
            "    steps:",
            "      - name: Initialize",
            "        id: init",
            "        run: echo 'myValue=test' >> `$GITHUB_OUTPUT",
            "  Deploy:",
            "    runs-on: ubuntu-latest",
            "    needs: [ inputs ]",
            "    steps:",
            "      - name: Use job output",
            "        env:",
            "          value: `${{ needs.inputs.outputs.myValue }}",
            "        run: echo Job output is `$value",
            "      - name: Use input",
            "        run: echo Input is `${{ inputs.outputs }}"
        )

        $yaml = [Yaml]::new($yamlContent)

        # Create settings with hide flag for the "outputs" input
        $repoSettings = @{
            "workflowInputDefaults" = @(
                @{
                    "workflow" = "Test Workflow"
                    "defaults" = @(
                        @{ "name" = "outputs"; "value" = "hidden-input-value"; "hide" = $true }
                    )
                }
            )
        }

        # Apply the defaults
        ApplyWorkflowInputDefaults -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

        # Verify the hidden input was removed
        $inputsSection = $yaml.Get('on:/workflow_dispatch:/inputs:/')
        $inputsSection.Find('outputs:', [ref] $null, [ref] $null) | Should -Be $false

        # Verify that needs.inputs.outputs.myValue is NOT replaced (job output reference)
        $content = $yaml.content -join "`n"
        $content | Should -Match "needs\.inputs\.outputs\.myValue"

        # Verify that steps.init.outputs.myValue is NOT replaced (step output reference)
        $content | Should -Match "steps\.init\.outputs\.myValue"

        # Verify that inputs.outputs WAS replaced with the hidden value
        $content | Should -Match "echo Input is 'hidden-input-value'"
        $content | Should -Not -Match "`\$\{\{ inputs\.outputs \}\}"
    }
}
