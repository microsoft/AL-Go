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
}

Describe "ResolveFilePaths" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")

        $rootFolder = $PSScriptRoot

        $sourceFolder = Join-Path $rootFolder "sourcePath"
        if (-not (Test-Path $sourceFolder)) {
            New-Item -Path $sourceFolder -ItemType Directory | Out-Null
        }
        # Create a source folder structure
        New-Item -Path (Join-Path $sourceFolder "folder/File1.txt") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $sourceFolder "folder/File2.log") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $sourceFolder "folder/File3.txt") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $sourceFolder "folder/File4.md") -ItemType File -Force | Out-Null

        $originalSourceFolder = Join-Path $rootFolder "originalSourceFolder"
        if (-not (Test-Path $originalSourceFolder)) {
            New-Item -Path $originalSourceFolder -ItemType Directory | Out-Null
        }
        New-Item -Path (Join-Path $originalSourceFolder "folder/File1.txt") -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $originalSourceFolder "folder/File2.log") -ItemType File -Force | Out-Null
    }

    AfterAll {
        # Clean up
        if (Test-Path $sourceFolder) {
            Remove-Item -Path $sourceFolder -Recurse -Force
        }

        if (Test-Path $originalSourceFolder) {
            Remove-Item -Path $originalSourceFolder -Recurse -Force
        }
    }

    It 'ResolveFilePaths with specific files extensions' {
        $destinationPath = "destinationPath"
        $destinationFolder = Join-Path $rootFolder $destinationPath
        $files = @(
            @{ "sourcePath" = "folder"; "filter" = "*.txt"; "destinationPath" = 'newFolder'; "destinationName" = "" }
            @{ "sourcePath" = "folder"; "filter" = "*.md"; "destinationPath" = 'newFolder'; "destinationName" = "" }
        )

        $fullFilePaths = ResolveFilePaths -sourceFolder $sourceFolder -files $files -destinationFolder $destinationFolder

        $fullFilePaths | Should -Not -BeNullOrEmpty
        $fullFilePaths.Count | Should -Be 3
        $fullFilePaths[0].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File1.txt")
        $fullFilePaths[0].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File1.txt")
        $fullFilePaths[0].type | Should -Be $null
        $fullFilePaths[1].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File3.txt")
        $fullFilePaths[1].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File3.txt")
        $fullFilePaths[1].type | Should -Be $null
        $fullFilePaths[2].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File4.md")
        $fullFilePaths[2].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File4.md")
        $fullFilePaths[2].type | Should -Be $null
    }

    It 'ResolveFilePaths with specific destination names' {
        $destinationPath = "destinationPath"
        $destinationFolder = Join-Path $rootFolder $destinationPath
        $files = @(
            @{ "sourcePath" = "folder"; "filter" = "File1.txt"; "destinationPath" = 'newFolder'; "destinationName" = "CustomFile1.txt" }
            @{ "sourcePath" = "folder"; "filter" = "File2.log"; "destinationPath" = 'newFolder'; "destinationName" = "CustomFile2.log" }
        )

        $fullFilePaths = ResolveFilePaths -sourceFolder $sourceFolder -files $files -destinationFolder $destinationFolder

        $fullFilePaths | Should -Not -BeNullOrEmpty
        $fullFilePaths.Count | Should -Be 2
        $fullFilePaths[0].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File1.txt")
        $fullFilePaths[0].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/CustomFile1.txt")
        $fullFilePaths[0].type | Should -Be $null
        $fullFilePaths[1].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File2.log")
        $fullFilePaths[1].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/CustomFile2.log")
        $fullFilePaths[1].type | Should -Be $null
    }

    It 'ResolveFilePaths with type' {
        $destinationPath = "destinationPath"
        $destinationFolder = Join-Path $PSScriptRoot $destinationPath
        $files = @(
            @{ "sourcePath" = "folder"; "filter" = "*.txt"; "destinationPath" = "folder"; "destinationName" = ""; type = "text" }
            @{ "sourcePath" = "folder"; "filter" = "*.md"; "destinationPath" = "folder"; "destinationName" = ""; type = "markdown" }
        )
        $fullFilePaths = ResolveFilePaths -sourceFolder $sourceFolder -files $files -destinationFolder $destinationFolder

        # Verify destinationFullPath is not filled
        $fullFilePaths | Should -Not -BeNullOrEmpty
        $fullFilePaths.Count | Should -Be 3
        $fullFilePaths[0].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File1.txt")
        $fullFilePaths[0].destinationFullPath | Should -Be (Join-Path $destinationFolder "folder/File1.txt")
        $fullFilePaths[0].type | Should -Be "text"
        $fullFilePaths[1].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File3.txt")
        $fullFilePaths[1].destinationFullPath | Should -Be (Join-Path $destinationFolder "folder/File3.txt")
        $fullFilePaths[1].type | Should -Be "text"
        $fullFilePaths[2].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File4.md")
        $fullFilePaths[2].destinationFullPath | Should -Be (Join-Path $destinationFolder "folder/File4.md")
        $fullFilePaths[2].type | Should -Be "markdown"
    }

    It 'ResolveFilePaths with original source folder' {
        $destinationPath = "destinationPath"
        $destinationFolder = Join-Path $PSScriptRoot $destinationPath
        $files = @(
            @{ "sourcePath" = "folder"; "filter" = "*.txt"; "destinationPath" = "newFolder"; "destinationName" = ""; type = "text" }
            @{ "sourcePath" = "folder"; "filter" = "*.md"; "destinationPath" = "newFolder"; "destinationName" = ""; type = "markdown" }
        )

        $fullFilePaths = ResolveFilePaths -sourceFolder $sourceFolder -files $files -destinationFolder $destinationFolder -originalSourceFolder $originalSourceFolder

        $fullFilePaths | Should -Not -BeNullOrEmpty
        $fullFilePaths.Count | Should -Be 3
        $fullFilePaths[0].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File1.txt")
        $fullFilePaths[0].originalSourceFullPath | Should -Be (Join-Path $originalSourceFolder "folder/File1.txt")
        $fullFilePaths[0].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File1.txt")
        $fullFilePaths[0].type | Should -Be "text"

        $fullFilePaths[1].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File3.txt") # File3.txt doesn't exist in original source folder, so it should still point to the source folder
        $fullFilePaths[1].originalSourceFullPath | Should -Be $null
        $fullFilePaths[1].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File3.txt")
        $fullFilePaths[1].type | Should -Be "text"

        $fullFilePaths[2].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File4.md") # File4.md doesn't exist in original source folder, so it should still point to the source folder
        $fullFilePaths[2].originalSourceFullPath | Should -Be $null
        $fullFilePaths[2].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File4.md")
        $fullFilePaths[2].type | Should -Be "markdown"
    }

    It 'ResolveFilePaths returns unique file paths' {
        $destinationPath = "destinationPath"
        $destinationFolder = Join-Path $PSScriptRoot $destinationPath
        $files = @(
            @{ "sourcePath" = "folder"; "filter" = "*.txt"; "destinationPath" = "newFolder"; "destinationName" = ""; type = "text"; }
            @{ "sourcePath" = "folder"; "filter" = "*"; "destinationPath" = "newFolder"; "destinationName" = ""; type = "unknown"; }
        )

        $fullFilePaths = ResolveFilePaths -sourceFolder $sourceFolder -files $files -destinationFolder $destinationFolder

        $fullFilePaths | Should -Not -BeNullOrEmpty
        $fullFilePaths.Count | Should -Be 4
        $fullFilePaths[0].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File1.txt")
        $fullFilePaths[0].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File1.txt")
        $fullFilePaths[1].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File2.log")
        $fullFilePaths[1].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File2.log")
        $fullFilePaths[2].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File3.txt")
        $fullFilePaths[2].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File3.txt")
        $fullFilePaths[3].sourceFullPath | Should -Be (Join-Path $sourceFolder "folder/File4.md")
        $fullFilePaths[3].destinationFullPath | Should -Be (Join-Path $destinationFolder "newFolder/File4.md")
    }

}

Describe "ReplaceOwnerRepoAndBranch" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")
    }

    It "Replaces owner, repo, and branch in workflow content" {
        $srcContent = [ref]@"
jobs:
  build:
    uses: microsoft/AL-Go-Actions@main
"@
        $templateOwner = "contoso"
        $templateBranch = "dev"
        ReplaceOwnerRepoAndBranch -srcContent $srcContent -templateOwner $templateOwner -templateBranch $templateBranch
        $srcContent.Value | Should -Be @"
jobs:
  build:
    uses: contoso/AL-Go/Actions@dev
"@
    }
}

Describe "IsDirectALGo" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")
    }
    It "Returns true for direct AL-Go repo URL" {
        IsDirectALGo -templateUrl "https://github.com/contoso/AL-Go@main" | Should -Be True
    }
    It "Returns false for non-direct AL-Go repo URL" {
        IsDirectALGo -templateUrl "https://github.com/contoso/OtherRepo@main" | Should -Be False
    }
}

Describe "GetFilesToUpdate" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")

        # Create template folder with test files
        $templateFolder = Join-Path $PSScriptRoot "template"
        New-Item -ItemType Directory -Path $templateFolder -Force | Out-Null

        New-Item -ItemType Directory -Path (Join-Path $templateFolder "subfolder") -Force | Out-Null

        $testPSFile = Join-Path $templateFolder "test.ps1"
        Set-Content -Path $testPSFile -Value "# test ps file"

        $testTxtFile = Join-Path $templateFolder "test.txt"
        Set-Content -Path $testTxtFile -Value "test txt file"

        $testTxtFile2 = Join-Path $templateFolder "test2.txt"
        Set-Content -Path $testTxtFile2 -Value "test txt file 2"

        $testSubfolderFile = Join-Path $templateFolder "subfolder/testsub.txt"
        Set-Content -Path $testSubfolderFile -Value "test subfolder txt file"

        $testSubfolderFile2 = Join-Path $templateFolder "subfolder/testsub2.txt"
        Set-Content -Path $testSubfolderFile2 -Value "test subfolder txt file 2"

        # Display the created files structure for template folder
        # .
        # ├── test.ps1
        # ├── test.txt
        # └── test2.txt
        # └── subfolder
        #     └── testsub.txt
    }

    AfterAll {
        if (Test-Path $templateFolder) {
            Remove-Item -Path $templateFolder -Recurse -Force
        }
    }

    It "Returns the correct files to update with filters" {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.ps1" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testPSFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test.ps1')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.txt" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder
        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 2
        $filesToUpdate[0].sourceFullPath | Should -Be $testTxtFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test.txt')
        $filesToUpdate[1].sourceFullPath | Should -Be $testTxtFile2
        $filesToUpdate[1].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test2.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty
    }

    It 'Returns the correct files when there are files to ignore' {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.*" })
                filesToIgnore = @(@{ filter = "test.txt" })
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 2
        $filesToUpdate[0].sourceFullPath | Should -Be $testPSFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test.ps1')
        $filesToUpdate[1].sourceFullPath | Should -Be $testTxtFile2
        $filesToUpdate[1].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test2.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.txt" })
                filesToIgnore = @(@{ filter = "*" })
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        # No files to update
        $filesToUpdate | Should -BeNullOrEmpty
        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty
    }

    It 'Returns the correct files within subfolders' {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ sourcePath = 'subfolder'; filter = "*.txt" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 2
        $filesToUpdate[0].sourceFullPath | Should -Be $testSubfolderFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'subfolder/testsub.txt')
        $filesToUpdate[1].sourceFullPath | Should -Be $testSubfolderFile2
        $filesToUpdate[1].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'subfolder/testsub2.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ sourcePath = 'subfolder'; filter = "*.txt" })
                filesToIgnore = @(@{ sourcePath = 'subfolder'; filter = "testsub2.txt" })
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testSubfolderFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'subfolder/testsub.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty
    }

    It 'Returns the correct files with destinationPath' {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.txt"; destinationPath = "customFolder" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 2
        $filesToUpdate[0].sourceFullPath | Should -Be $testTxtFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'customFolder/test.txt')
        $filesToUpdate[1].sourceFullPath | Should -Be $testTxtFile2
        $filesToUpdate[1].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'customFolder/test2.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.txt"; destinationPath = "customFolder" })
                filesToIgnore = @(@{ filter = "test2.txt" })
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testTxtFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'customFolder/test.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty
    }

    It 'Returns the correct files with destinationName' {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "test.ps1"; destinationName = "renamed.txt" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testPSFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'renamed.txt')

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "test.ps1"; destinationPath = 'dstPath'; destinationName = "renamed.txt" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testPSFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'dstPath/renamed.txt')
    }

    It 'Return the correct files with types' {
        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.ps1"; type = "script" })
                filesToIgnore = @()
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testPSFile
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test.ps1')
        $filesToUpdate[0].type | Should -Be "script"

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty

        $settings = @{
            updateALGoFiles = @{
                filesToUpdate = @(@{ filter = "*.txt"; type = "text" })
                filesToIgnore = @(@{ filter = "test.txt" })
                filesToRemove = @()
            }
        }

        $filesToUpdate, $filesToRemove = GetFilesToUpdate -settings $settings -baseFolder 'baseFolder' -templateFolder $templateFolder

        $filesToUpdate | Should -Not -BeNullOrEmpty
        $filesToUpdate.Count | Should -Be 1
        $filesToUpdate[0].sourceFullPath | Should -Be $testTxtFile2
        $filesToUpdate[0].destinationFullPath | Should -Be (Join-Path 'baseFolder' 'test2.txt')
        $filesToUpdate[0].type | Should -Be "text"

        # No files to remove
        $filesToRemove | Should -BeNullOrEmpty
    }
}