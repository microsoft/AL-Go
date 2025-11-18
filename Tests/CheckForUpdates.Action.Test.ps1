Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
Import-Module (Join-Path $PSScriptRoot "../Actions/TelemetryHelper.psm1")
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/ReadSettings.psm1') -Force
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

    Context 'ApplyWorkflowDefaultInputs' {

        It 'applies default values to workflow inputs' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "directCommit"; "value" = $true },
                    @{ "name" = "useGhTokenWorkflow"; "value" = $true },
                    @{ "name" = "updateVersionNumber"; "value" = "+0.1" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify the defaults were applied
            $yaml.Get('on:/workflow_dispatch:/inputs:/directCommit:/default:').content -join '' | Should -Be 'default: true'
            $yaml.Get('on:/workflow_dispatch:/inputs:/useGhTokenWorkflow:/default:').content -join '' | Should -Be 'default: true'
            $yaml.Get('on:/workflow_dispatch:/inputs:/updateVersionNumber:/default:').content -join '' | Should -Be "default: '+0.1'"
        }

        It 'handles empty workflowDefaultInputs array' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        type: boolean",
                "        default: false",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with empty workflowDefaultInputs array
            $repoSettings = @{
                "workflowDefaultInputs" = @()
            }

            # Apply the defaults - should not throw and should not modify workflow
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
            $yaml.Get('on:/workflow_dispatch:/inputs:/myInput:/default:').content -join '' | Should -Be 'default: false'
        }

        It 'handles workflows without workflow_dispatch' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "directCommit"; "value" = $true }
                )
            }

            # Apply the defaults - should not throw
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
        }

        It 'handles workflow_dispatch without inputs section' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with workflow_dispatch but no inputs
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with workflow input defaults
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "someInput"; "value" = $true }
                )
            }

            # Apply the defaults - should not throw
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
        }

        It 'applies multiple defaults to same workflow' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with multiple inputs
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      input1:",
                "        type: boolean",
                "        default: false",
                "      input2:",
                "        type: number",
                "        default: 0",
                "      input3:",
                "        type: string",
                "        default: ''",
                "      input4:",
                "        type: choice",
                "        options:",
                "          - optionA",
                "          - optionB",
                "        default: optionA",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with multiple defaults
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "input1"; "value" = $true },
                    @{ "name" = "input2"; "value" = 5 },
                    @{ "name" = "input3"; "value" = "test-value" },
                    @{ "name" = "input4"; "value" = "optionB" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify all defaults were applied
            $yaml.Get('on:/workflow_dispatch:/inputs:/input1:/default:').content -join '' | Should -Be 'default: true'
            $yaml.Get('on:/workflow_dispatch:/inputs:/input2:/default:').content -join '' | Should -Be 'default: 5'
            $yaml.Get('on:/workflow_dispatch:/inputs:/input3:/default:').content -join '' | Should -Be "default: 'test-value'"
            $yaml.Get('on:/workflow_dispatch:/inputs:/input4:/default:').content -join '' | Should -Be "default: 'optionB'"
        }

        It 'inserts default line when missing' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with input without default line (only description)
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        description: 'My input without default'",
                "        type: string",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with default value
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = "new-default" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify default line was inserted
            $defaultLine = $yaml.Get('on:/workflow_dispatch:/inputs:/myInput:/default:')
            $defaultLine | Should -Not -BeNullOrEmpty
            $defaultLine.content -join '' | Should -Be "default: 'new-default'"
        }

        It 'is case-insensitive for input names' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with specific casing
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      MyInput:",
                "        type: boolean",
                "        default: false",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with different casing
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify default WAS applied despite case difference (case-insensitive matching)
            $yaml.Get('on:/workflow_dispatch:/inputs:/MyInput:/default:').content -join '' | Should -Be 'default: true'
        }

        It 'ignores defaults for non-existent inputs' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      existingInput:",
                "        type: boolean",
                "        default: false",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with both existing and non-existent input names
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "existingInput"; "value" = $true },
                    @{ "name" = "nonExistentInput"; "value" = "ignored" },
                    @{ "name" = "anotherMissingInput"; "value" = 42 }
                )
            }

            # Apply the defaults - should not throw
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw

            # Verify only the existing input was modified
            $yaml.Get('on:/workflow_dispatch:/inputs:/existingInput:/default:').content -join '' | Should -Be 'default: true'
        }

        It 'handles special YAML characters in string values' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      input1:",
                "        type: string",
                "        default: ''",
                "      input2:",
                "        type: string",
                "        default: ''",
                "      input3:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with special YAML characters
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "input1"; "value" = "value: with colon" },
                    @{ "name" = "input2"; "value" = "value # with comment" },
                    @{ "name" = "input3"; "value" = "value with 'quotes' inside" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify values are properly quoted and escaped
            $yaml.Get('on:/workflow_dispatch:/inputs:/input1:/default:').content -join '' | Should -Be "default: 'value: with colon'"
            $yaml.Get('on:/workflow_dispatch:/inputs:/input2:/default:').content -join '' | Should -Be "default: 'value # with comment'"
            $yaml.Get('on:/workflow_dispatch:/inputs:/input3:/default:').content -join '' | Should -Be "default: 'value with ''quotes'' inside'"
        }

        It 'handles environment input type' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with environment type
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      environmentName:",
                "        description: Environment to deploy to",
                "        type: environment",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with environment value (should be treated as string)
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "environmentName"; "value" = "production" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify environment value is set as string
            $yaml.Get('on:/workflow_dispatch:/inputs:/environmentName:/default:').content -join '' | Should -Be "default: 'production'"
        }

        It 'validates invalid choice value not in options' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with choice input
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      deploymentType:",
                "        type: choice",
                "        options:",
                "          - Development",
                "          - Staging",
                "          - Production",
                "        default: Development",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with invalid choice value
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "deploymentType"; "value" = "Testing" }
                )
            }

            # Apply the defaults - should throw validation error
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*not a valid choice*"
        }

        It 'handles inputs without existing default' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = "test-value" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify the default was added
            $defaultLine = $yaml.Get('on:/workflow_dispatch:/inputs:/myInput:/default:')
            $defaultLine | Should -Not -BeNullOrEmpty
            $defaultLine.content -join '' | Should -Be "default: 'test-value'"
        }

        It 'handles different value types' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "boolInput"; "value" = $true },
                    @{ "name" = "stringInput"; "value" = "test" },
                    @{ "name" = "numberInput"; "value" = 42 }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify the defaults were applied with correct types
            $yaml.Get('on:/workflow_dispatch:/inputs:/boolInput:/default:').content -join '' | Should -Be 'default: true'
            $yaml.Get('on:/workflow_dispatch:/inputs:/stringInput:/default:').content -join '' | Should -Be "default: 'test'"
            $yaml.Get('on:/workflow_dispatch:/inputs:/numberInput:/default:').content -join '' | Should -Be 'default: 42'
        }

        It 'validates boolean type mismatch' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "boolInput"; "value" = "not a boolean" }
                )
            }

            # Apply the defaults - should throw validation error
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected boolean value*"
        }

        It 'validates number type mismatch' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "numberInput"; "value" = "not a number" }
                )
            }

            # Apply the defaults - should throw validation error
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected number value*"
        }

        It 'validates string type mismatch' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "stringInput"; "value" = $true }
                )
            }

            # Apply the defaults - should throw validation error
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*Expected string value*"
        }

        It 'validates choice type' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "choiceInput"; "value" = "option2" }
                )
            }

            # Apply the defaults - should succeed
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
            $yaml.Get('on:/workflow_dispatch:/inputs:/choiceInput:/default:').content -join '' | Should -Be "default: 'option2'"
        }

        It 'validates choice value is in available options' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "choiceInput"; "value" = "invalidOption" }
                )
            }

            # Apply the defaults - should throw validation error
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } |
            Should -Throw "*not a valid choice*"
        }

        It 'validates choice value with case-sensitive matching' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "releaseTypeInput"; "value" = "Prerelease" }
                )
            }

            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
            $yaml.Get('on:/workflow_dispatch:/inputs:/releaseTypeInput:/default:').content -join '' | Should -Be "default: 'Prerelease'"

            # Test 2: Wrong case should fail with case-sensitive error message
            $yaml2 = [Yaml]::new($yamlContent)
            $repoSettings2 = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "releaseTypeInput"; "value" = "prerelease" }
                )
            }

            { ApplyWorkflowDefaultInputs -yaml $yaml2 -repoSettings $repoSettings2 -workflowName "Test Workflow" } |
            Should -Throw "*case-sensitive match required*"

            # Test 3: Uppercase version should also fail
            $yaml3 = [Yaml]::new($yamlContent)
            $repoSettings3 = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "releaseTypeInput"; "value" = "PRERELEASE" }
                )
            }

            { ApplyWorkflowDefaultInputs -yaml $yaml3 -repoSettings $repoSettings3 -workflowName "Test Workflow" } |
            Should -Throw "*case-sensitive match required*"
        }

        It 'handles inputs without type specification' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "noTypeInput"; "value" = "string value" }
                )
            }

            # Apply the defaults - should succeed
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow" } | Should -Not -Throw
            $yaml.Get('on:/workflow_dispatch:/inputs:/noTypeInput:/default:').content -join '' | Should -Be "default: 'string value'"
        }

        It 'escapes single quotes in string values' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "nameInput"; "value" = "O'Brien" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify single quote is escaped per YAML spec (doubled)
            $yaml.Get('on:/workflow_dispatch:/inputs:/nameInput:/default:').content -join '' | Should -Be "default: 'O''Brien'"
        }

        It 'applies last value when multiple entries have same input name' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      input1:",
                "        type: string",
                "        default: ''",
                "      input2:",
                "        type: boolean",
                "        default: false",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with duplicate entries for input1 - simulating merged conditional settings
            # This can happen when multiple conditionalSettings blocks both match and both define the same input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "input1"; "value" = "first-value" },
                    @{ "name" = "input2"; "value" = $false },
                    @{ "name" = "input1"; "value" = "second-value" },  # Duplicate input1
                    @{ "name" = "input1"; "value" = "final-value" }    # Another duplicate input1
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow"

            # Verify "last wins" - the final value for input1 should be applied
            $yaml.Get('on:/workflow_dispatch:/inputs:/input1:/default:').content -join '' | Should -Be "default: 'final-value'"
            $yaml.Get('on:/workflow_dispatch:/inputs:/input2:/default:').content -join '' | Should -Be 'default: false'
        }

    } # End of Context 'ApplyWorkflowDefaultInputs'

    Context 'ApplyWorkflowDefaultInputs - Hide Feature' {

        It 'hides boolean inputs when hide is true' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "visibleInput"; "value" = "test" },
                    @{ "name" = "hiddenInput"; "value" = $true; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide Boolean"

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

        It 'hides string inputs and replaces references correctly' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "versionInput"; "value" = "+0.1"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide String"

            # Verify the hidden input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('versionInput:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify both references were replaced with quoted string
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo '\+0\.1'"
            $content | Should -Not -Match "inputs\.versionInput"
            $content | Should -Not -Match "github\.event\.inputs\.versionInput"
        }

        It 'hides number inputs and replaces references correctly' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "countInput"; "value" = 10; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide Number"

            # Verify the hidden input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('countInput:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference was replaced with number (unquoted)
            $yaml.content -join "`n" | Should -Match "echo 10"
            $yaml.content -join "`n" | Should -Not -Match "inputs\.countInput"
        }

        It 'replaces hidden input references in if conditions' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "runTests"; "value" = $true; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide If Condition"

            # Verify the hidden input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('runTests:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference in if condition was replaced with string literal
            # Bare references in if conditions are always treated as strings in GitHub Actions
            # GitHub Actions comparisons are case-sensitive, so we use lowercase 'true'
            $yaml.content -join "`n" | Should -Match "if: 'true' == 'true'"
            $yaml.content -join "`n" | Should -Not -Match "github\.event\.inputs\.runTests"
        }

        It 'does not replace job output references' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "branch"; "value" = "production"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Job Output"

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

        It 'does not replace parts of job output references with input names like output' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "output"; "value" = "hidden"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Input Named Output"

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

        It 'does not replace job output references when input is named outputs' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "outputs"; "value" = "hidden-value"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Input Named Outputs"

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

        It 'does not replace job outputs when job is named inputs and input is named outputs' {
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
                "workflowDefaultInputs" = @(
                    @{ "name" = "outputs"; "value" = "hidden-input-value"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Job Named Inputs"

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

        It 'silently skips hiding non-existent input' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with only one input
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      existingInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.existingInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings trying to hide an input that doesn't exist
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "existingInput"; "value" = "test-value" },
                    @{ "name" = "nonExistentInput"; "value" = "hidden-value"; "hide" = $true }
                )
            }

            # Mock OutputWarning to verify no warning is issued
            Mock OutputWarning { }

            # Apply the defaults - should not throw
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide Non-Existent" } | Should -Not -Throw

            # Verify no warning was issued
            Assert-MockCalled OutputWarning -Times 0

            # Verify the existing input was updated but not hidden
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('existingInput:', [ref] $null, [ref] $null) | Should -Be $true
            $yaml.Get('on:/workflow_dispatch:/inputs:/existingInput:/default:').content -join '' | Should -Be "default: 'test-value'"

            # Verify the workflow content was not affected by the non-existent input
            $content = $yaml.content -join "`n"
            $content | Should -Match "`\$\{\{ inputs\.existingInput \}\}"
        }

        It 'hides multiple inputs in the same workflow' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with multiple inputs to hide
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      visibleInput:",
                "        type: string",
                "        default: ''",
                "      hiddenInput1:",
                "        type: boolean",
                "        default: false",
                "      hiddenInput2:",
                "        type: string",
                "        default: ''",
                "      hiddenInput3:",
                "        type: number",
                "        default: 0",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Use inputs",
                "        run: echo `${{ inputs.hiddenInput1 }} `${{ inputs.hiddenInput2 }} `${{ inputs.hiddenInput3 }}",
                "      - name: Use visible",
                "        run: echo `${{ inputs.visibleInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with multiple hidden inputs
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "visibleInput"; "value" = "visible" },
                    @{ "name" = "hiddenInput1"; "value" = $true; "hide" = $true },
                    @{ "name" = "hiddenInput2"; "value" = "hidden-string"; "hide" = $true },
                    @{ "name" = "hiddenInput3"; "value" = 42; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Multiple Hidden"

            # Verify all hidden inputs were removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('hiddenInput1:', [ref] $null, [ref] $null) | Should -Be $false
            $inputs.Find('hiddenInput2:', [ref] $null, [ref] $null) | Should -Be $false
            $inputs.Find('hiddenInput3:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify visible input still exists
            $inputs.Find('visibleInput:', [ref] $null, [ref] $null) | Should -Be $true

            # Verify all references were replaced
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo true 'hidden-string' 42"
            $content | Should -Match "echo `\$\{\{ inputs\.visibleInput \}\}"
            $content | Should -Not -Match "inputs\.hiddenInput1"
            $content | Should -Not -Match "inputs\.hiddenInput2"
            $content | Should -Not -Match "inputs\.hiddenInput3"
        }

        It 'replaces hidden input references in different expression contexts' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with inputs used in various contexts
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      hiddenBool:",
                "        type: boolean",
                "        default: false",
                "      hiddenString:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    if: inputs.hiddenBool == true",
                "    env:",
                "      MY_VAR: `${{ inputs.hiddenString }}",
                "    steps:",
                "      - name: Checkout",
                "        uses: actions/checkout@v4",
                "        with:",
                "          ref: `${{ inputs.hiddenString }}",
                "      - name: Step with if",
                "        if: inputs.hiddenBool",
                "        run: echo Running",
                "      - name: Step with env",
                "        env:",
                "          BRANCH: `${{ inputs.hiddenString }}",
                "        run: echo `$BRANCH"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with hide flags
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "hiddenBool"; "value" = $true; "hide" = $true },
                    @{ "name" = "hiddenString"; "value" = "main"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Expression Contexts"

            # Verify all references were replaced correctly in different contexts
            $content = $yaml.content -join "`n"
            $content | Should -Match "if: true == true"  # Job-level if
            $content | Should -Match "MY_VAR: 'main'"    # Job-level env
            $content | Should -Match "ref: 'main'"       # Action with parameter
            $content | Should -Match "if: true"          # Step-level if
            $content | Should -Match "BRANCH: 'main'"    # Step-level env
            $content | Should -Not -Match "inputs\.hiddenBool"
            $content | Should -Not -Match "inputs\.hiddenString"
        }

        It 'does not replace partial input name matches' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with inputs that have overlapping names
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      test:",
                "        type: string",
                "        default: ''",
                "      testInput:",
                "        type: string",
                "        default: ''",
                "      mytest:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  run:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Use inputs",
                "        run: echo `${{ inputs.test }} `${{ inputs.testInput }} `${{ inputs.mytest }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide only the "test" input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "test"; "value" = "hidden-test"; "hide" = $true },
                    @{ "name" = "testInput"; "value" = "visible-testInput" },
                    @{ "name" = "mytest"; "value" = "visible-mytest" }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Partial Match"

            # Verify only "test" was hidden, not "testInput" or "mytest"
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('test:', [ref] $null, [ref] $null) | Should -Be $false
            $inputs.Find('testInput:', [ref] $null, [ref] $null) | Should -Be $true
            $inputs.Find('mytest:', [ref] $null, [ref] $null) | Should -Be $true

            # Verify only inputs.test was replaced
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo 'hidden-test' `\$\{\{ inputs\.testInput \}\} `\$\{\{ inputs\.mytest \}\}"
        }

        It 'hides choice type inputs correctly' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with choice input
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      releaseType:",
                "        type: choice",
                "        options:",
                "          - Release",
                "          - Prerelease",
                "          - Draft",
                "        default: Release",
                "jobs:",
                "  release:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Create release",
                "        run: echo Creating `${{ inputs.releaseType }} release"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide the choice input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "releaseType"; "value" = "Prerelease"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide Choice"

            # Verify the choice input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('releaseType:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference was replaced with the choice value
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo Creating 'Prerelease' release"
            $content | Should -Not -Match "inputs\.releaseType"
        }

        It 'hides environment type inputs correctly' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with environment input
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      environment:",
                "        type: environment",
                "        default: ''",
                "jobs:",
                "  deploy:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Deploy",
                "        run: echo Deploying to `${{ inputs.environment }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide the environment input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "environment"; "value" = "production"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Hide Environment"

            # Verify the environment input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('environment:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference was replaced
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo Deploying to 'production'"
            $content | Should -Not -Match "inputs\.environment"
        }

        It 'handles input references without whitespace' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with various spacing patterns
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: No spaces",
                "        run: echo `${{inputs.myInput}}",
                "      - name: Normal spaces",
                "        run: echo `${{ inputs.myInput }}",
                "      - name: Asymmetric left",
                "        run: echo `${{ inputs.myInput}}",
                "      - name: Asymmetric right",
                "        run: echo `${{inputs.myInput }}",
                "      - name: Multiple on same line",
                "        run: echo `${{inputs.myInput}} and `${{ inputs.myInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide the input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = "test-value"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Spacing"

            # Verify all variations were replaced with the same normalized output
            $content = $yaml.content -join "`n"

            # All spacing variations should be replaced with just the value (in quotes for strings)
            # Verify the four single-value lines all got replaced the same way
            ($content -split "`n" | Where-Object { $_ -match "^\s+run: echo 'test-value'`$" }).Count | Should -Be 4 -Because "Four lines with single value should all be normalized"

            # Verify the multiple-on-same-line case
            $content -match "(?m)^\s+run: echo 'test-value' and 'test-value'`$" | Should -Be $true -Because "Multiple on same line should both be replaced"

            # Verify no input references remain
            $content | Should -Not -Match "inputs\.myInput"
        }

        It 'replaces hidden input references in complex expressions' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with complex expressions
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      enableTests:",
                "        type: boolean",
                "        default: false",
                "      branch:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    if: inputs.enableTests == true && inputs.branch != ''",
                "    steps:",
                "      - name: Conditional",
                "        if: inputs.enableTests && needs.job.outputs.value",
                "        run: echo Testing",
                "      - name: Fallback",
                "        run: echo `${{ inputs.branch || 'main' }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide both inputs
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "enableTests"; "value" = $true; "hide" = $true },
                    @{ "name" = "branch"; "value" = "develop"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Complex Expressions"

            # Verify complex expressions were handled correctly
            $content = $yaml.content -join "`n"
            $content | Should -Match "if: true == true && 'develop' != ''"
            $content | Should -Match "if: true && needs\.job\.outputs\.value"
            $content | Should -Match "echo `\$\{\{ 'develop' \|\| 'main' \}\}"
            $content | Should -Not -Match "inputs\.enableTests"
            $content | Should -Not -Match "inputs\.branch"
        }

        It 'handles case-insensitive input references' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with mixed case references
            # Note: GitHub Actions itself is case-sensitive for input references in workflows
            # This test verifies our hide feature respects the actual case used
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Lower case",
                "        run: echo `${{ inputs.myInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide the input (case should not matter for input name matching)
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "MYINPUT"; "value" = "test-value"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Case Sensitivity"

            # Verify the input was hidden (case-insensitive matching for input names)
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('myInput:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference was replaced
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo 'test-value'"
        }

        It 'handles empty string values when hiding' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      emptyInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.emptyInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide with empty string value
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "emptyInput"; "value" = ""; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Empty Value"

            # Verify the input was removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('emptyInput:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the reference was replaced with empty quoted string
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo ''"
            $content | Should -Not -Match "inputs\.emptyInput"
        }

        It 'handles special characters in hidden values' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      input1:",
                "        type: string",
                "        default: ''",
                "      input2:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.input1 }} and `${{ inputs.input2 }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide with values containing special characters
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "input1"; "value" = "value with 'quotes'"; "hide" = $true },
                    @{ "name" = "input2"; "value" = "+0.1"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Special Chars"

            # Verify values are properly escaped
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo 'value with ''quotes''' and '\+0\.1'"
            $content | Should -Not -Match "inputs\.input1"
            $content | Should -Not -Match "inputs\.input2"
        }

        It 'handles hidden input with no references in workflow' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML where input is defined but never referenced
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      unusedInput:",
                "        type: string",
                "        default: ''",
                "      usedInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.usedInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide the unused input
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "unusedInput"; "value" = "hidden-unused"; "hide" = $true },
                    @{ "name" = "usedInput"; "value" = "visible" }
                )
            }

            # Apply the defaults - should not throw
            { ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Unused Input" } | Should -Not -Throw

            # Verify the unused input was still removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('unusedInput:', [ref] $null, [ref] $null) | Should -Be $false
            $inputs.Find('usedInput:', [ref] $null, [ref] $null) | Should -Be $true
        }

        It 'handles workflow with all inputs hidden' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML with only inputs that will be hidden
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      input1:",
                "        type: string",
                "        default: ''",
                "      input2:",
                "        type: boolean",
                "        default: false",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.input1 }} `${{ inputs.input2 }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Hide all inputs
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "input1"; "value" = "hidden1"; "hide" = $true },
                    @{ "name" = "input2"; "value" = $true; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - All Hidden"

            # Verify all inputs were removed
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('input1:', [ref] $null, [ref] $null) | Should -Be $false
            $inputs.Find('input2:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify references were replaced
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo 'hidden1' true"
        }

        It 'applies last value when duplicate entries have different hide flags' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.myInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with duplicate entries where first has hide=false, last has hide=true
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = "first-value"; "hide" = $false },
                    @{ "name" = "myInput"; "value" = "final-value"; "hide" = $true }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Duplicate Hide"

            # Verify last entry wins - input should be hidden
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('myInput:', [ref] $null, [ref] $null) | Should -Be $false

            # Verify the final hidden value was used
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo 'final-value'"
            $content | Should -Not -Match "inputs\.myInput"
        }

        It 'applies last value when duplicate entries have hide reversed' {
            . (Join-Path $scriptRoot "yamlclass.ps1")

            # Create a test workflow YAML
            $yamlContent = @(
                "name: 'Test Workflow'",
                "on:",
                "  workflow_dispatch:",
                "    inputs:",
                "      myInput:",
                "        type: string",
                "        default: ''",
                "jobs:",
                "  test:",
                "    runs-on: ubuntu-latest",
                "    steps:",
                "      - name: Test",
                "        run: echo `${{ inputs.myInput }}"
            )

            $yaml = [Yaml]::new($yamlContent)

            # Create settings with duplicate entries where first has hide=true, last has hide=false
            $repoSettings = @{
                "workflowDefaultInputs" = @(
                    @{ "name" = "myInput"; "value" = "first-value"; "hide" = $true },
                    @{ "name" = "myInput"; "value" = "final-value"; "hide" = $false }
                )
            }

            # Apply the defaults
            ApplyWorkflowDefaultInputs -yaml $yaml -repoSettings $repoSettings -workflowName "Test Workflow - Duplicate Hide Reversed"

            # Verify last entry wins - input should NOT be hidden
            $inputs = $yaml.Get('on:/workflow_dispatch:/inputs:/')
            $inputs.Find('myInput:', [ref] $null, [ref] $null) | Should -Be $true

            # Verify the final value was applied to the default
            $yaml.Get('on:/workflow_dispatch:/inputs:/myInput:/default:').content -join '' | Should -Be "default: 'final-value'"

            # Verify the reference was NOT replaced (input is visible)
            $content = $yaml.content -join "`n"
            $content | Should -Match "echo `\$\{\{ inputs\.myInput \}\}"
            $content | Should -Not -Match "echo 'final-value'"
        }

    } # End of Context 'ApplyWorkflowDefaultInputs - Hide Feature'
}
