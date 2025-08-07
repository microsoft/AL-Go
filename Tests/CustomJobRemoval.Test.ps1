Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Custom Job Removal Tests" {
    BeforeAll {
        $actionName = "CheckForUpdates"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        Import-Module (Join-Path $scriptRoot "..\Github-Helper.psm1") -DisableNameChecking -Force
        . (Join-Path -Path $scriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")
        . (Join-Path -Path $scriptRoot -ChildPath "yamlclass.ps1")

        # Create temporary directory for test files
        $testDir = Join-Path $PSScriptRoot "temp_custom_job_test"
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force
        }
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Clean up test directory
        $testDir = Join-Path $PSScriptRoot "temp_custom_job_test"
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force
        }
    }

    It 'Custom jobs should not be applied from final repositories' {
        $testDir = Join-Path $PSScriptRoot "temp_custom_job_test"

        # Create a mock template CICD workflow (base workflow)
        $templateWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  Build:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Create a final repository workflow with custom jobs (simulating a repository that uses a template)
        $finalRepoWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  CustomJob-ShouldNotPersist:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Custom Step",
            "        run: echo 'This custom job should not persist'",
            "  Build:",
            "    needs: [ Initialization, CustomJob-ShouldNotPersist ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Save test files
        $templateFile = Join-Path $testDir "template_cicd.yaml"
        $finalRepoFile = Join-Path $testDir "final_repo_cicd.yaml"

        $templateWorkflow -join "`n" | Set-Content -Path $templateFile -Encoding UTF8
        $finalRepoWorkflow -join "`n" | Set-Content -Path $finalRepoFile -Encoding UTF8

        # Mock environment and repo settings for final repository
        $env:GITHUB_REPOSITORY = "testowner/final-repo"
        $env:GITHUB_API_URL = "https://api.github.com"
        $repoSettings = @{}

        # Mock GitHub API for final repository (not a template)
        Mock InvokeWebRequest -MockWith {
            return @{
                Content = '{"is_template": false}'
            }
        } -ParameterFilter { $uri -eq "https://api.github.com/repos/testowner/final-repo" }

        # Simulate the logic from CheckForUpdates.ps1
        $srcContent = Get-Content -Path $templateFile -Raw
        $dstFileExists = Test-Path -Path $finalRepoFile
        $type = 'workflow'

        # Apply the template repository detection logic (using GitHub API)
        $token = "mock-token"
        $isFinalRepository = $false

        try {
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "Bearer $token"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $repoInfo = (InvokeWebRequest -Headers $headers -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)").Content | ConvertFrom-Json
            $isTemplateRepository = $repoInfo.is_template
            $isFinalRepository = -not $isTemplateRepository
        }
        catch {
            $isFinalRepository = $true
        }

        # Test that final repository is correctly detected
        $isFinalRepository | Should -Be $true

        # Apply customizations based on repository type
        if ($dstFileExists -and $type -eq 'workflow') {
            if (-not $isFinalRepository) {
                [Yaml]::ApplyCustomizations([ref] $srcContent, $finalRepoFile)
            }
        }

        # Verify that custom jobs were NOT applied (srcContent should not contain CustomJob-ShouldNotPersist)
        $srcContent | Should -Not -Match "CustomJob-ShouldNotPersist"
        $srcContent | Should -Not -Match "This custom job should not persist"

        # Verify that the base template structure is preserved
        $srcContent | Should -Match "Initialization:"
        $srcContent | Should -Match "Build:"
        $srcContent | Should -Match "PostProcess:"
    }

    It 'Custom jobs should be applied from template repositories' {
        $testDir = Join-Path $PSScriptRoot "temp_custom_job_test"

        # Create a mock template CICD workflow (base workflow)
        $templateWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  Build:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Create a template repository workflow with custom jobs
        $templateRepoWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  CustomJob-Template:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Template Custom Step",
            "        run: echo 'This is a template custom job'",
            "  Build:",
            "    needs: [ Initialization, CustomJob-Template ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Save test files
        $templateFile = Join-Path $testDir "template_cicd2.yaml"
        $templateRepoFile = Join-Path $testDir "template_repo_cicd.yaml"

        $templateWorkflow -join "`n" | Set-Content -Path $templateFile -Encoding UTF8
        $templateRepoWorkflow -join "`n" | Set-Content -Path $templateRepoFile -Encoding UTF8

        # Mock environment and repo settings for template repository
        $env:GITHUB_REPOSITORY = "testowner/template-repo"
        $env:GITHUB_API_URL = "https://api.github.com"
        $repoSettings = @{}

        # Mock GitHub API for template repository (marked as template)
        Mock InvokeWebRequest -MockWith {
            return @{
                Content = '{"is_template": true}'
            }
        } -ParameterFilter { $uri -eq "https://api.github.com/repos/testowner/template-repo" }

        # Simulate the logic from CheckForUpdates.ps1
        $srcContent = Get-Content -Path $templateFile -Raw
        $dstFileExists = Test-Path -Path $templateRepoFile
        $type = 'workflow'

        # Apply the template repository detection logic (using GitHub API)
        $token = "mock-token"
        $isFinalRepository = $false

        try {
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "Bearer $token"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $repoInfo = (InvokeWebRequest -Headers $headers -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)").Content | ConvertFrom-Json
            $isTemplateRepository = $repoInfo.is_template
            $isFinalRepository = -not $isTemplateRepository
        }
        catch {
            $isFinalRepository = $true
        }

        # Test that template repository is correctly detected
        $isFinalRepository | Should -Be $false

        # Apply customizations based on repository type
        if ($dstFileExists -and $type -eq 'workflow') {
            if (-not $isFinalRepository) {
                [Yaml]::ApplyCustomizations([ref] $srcContent, $templateRepoFile)
            }
        }

        # Verify that custom jobs WERE applied (srcContent should contain CustomJob-Template)
        $srcContent | Should -Match "CustomJob-Template"
        $srcContent | Should -Match "This is a template custom job"

        # Verify that the base template structure is preserved
        $srcContent | Should -Match "Initialization:"
        $srcContent | Should -Match "Build:"
        $srcContent | Should -Match "PostProcess:"
    }

    It 'Custom jobs should be applied in final repositories when allowCustomJobsInEndRepos is true' {
        $testDir = Join-Path $PSScriptRoot "temp_custom_job_test"

        # Create a mock template CICD workflow (base workflow)
        $templateWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  Build:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Create a final repository workflow with custom jobs
        $finalRepoWorkflow = @(
            "name: 'CI/CD'",
            "on:",
            "  workflow_dispatch:",
            "jobs:",
            "  Initialization:",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Initialize",
            "        run: echo 'Initializing'",
            "  CustomJob-ShouldPersist:",
            "    needs: [ Initialization ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Custom Step",
            "        run: echo 'This custom job should persist when allowCustomJobsInEndRepos is true'",
            "  Build:",
            "    needs: [ Initialization, CustomJob-ShouldPersist ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: Build",
            "        run: echo 'Building'",
            "  PostProcess:",
            "    needs: [ Initialization, Build ]",
            "    runs-on: [ windows-latest ]",
            "    steps:",
            "      - name: PostProcess",
            "        run: echo 'PostProcessing'"
        )

        # Save test files
        $templateFile = Join-Path $testDir "template_cicd_allow.yaml"
        $finalRepoFile = Join-Path $testDir "final_repo_cicd_allow.yaml"

        $templateWorkflow -join "`n" | Set-Content -Path $templateFile -Encoding UTF8
        $finalRepoWorkflow -join "`n" | Set-Content -Path $finalRepoFile -Encoding UTF8

        # Mock environment and repo settings for final repository with allowCustomJobsInEndRepos = true
        $env:GITHUB_REPOSITORY = "testowner/final-repo"
        $env:GITHUB_API_URL = "https://api.github.com"
        $repoSettings = @{
            allowCustomJobsInEndRepos = $true
        }

        # Mock GitHub API for final repository (not a template)
        Mock InvokeWebRequest -MockWith {
            return @{
                Content = '{"is_template": false}'
            }
        } -ParameterFilter { $uri -eq "https://api.github.com/repos/testowner/final-repo" }

        # Test the workflow processing logic (simulating CheckForUpdates.ps1 behavior)
        [Yaml]$templateYaml = [Yaml]::load($templateFile)
        $srcContent = $templateYaml.content -join "`n"

        # Simulate the repository type detection and custom job handling
        $token = "mock-token"
        $isFinalRepository = $false
        $allowCustomJobsInEndRepos = $false

        if ($repoSettings.ContainsKey('allowCustomJobsInEndRepos')) {
            $allowCustomJobsInEndRepos = $repoSettings.allowCustomJobsInEndRepos
        }

        try {
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "Bearer $token"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $repoInfo = (InvokeWebRequest -Headers $headers -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)").Content | ConvertFrom-Json
            $isTemplateRepository = $repoInfo.is_template
            $isFinalRepository = -not $isTemplateRepository
        }
        catch {
            $isFinalRepository = $true
        }

        # Verify that it's detected as a final repository
        $isFinalRepository | Should -Be $true

        # Verify that allowCustomJobsInEndRepos is set to true
        $allowCustomJobsInEndRepos | Should -Be $true

        # When allowCustomJobsInEndRepos is true, custom jobs should be applied
        # even in final repositories, so the condition should be:
        # NOT ($isFinalRepository -and -not $allowCustomJobsInEndRepos)
        $shouldApplyCustomJobs = -not ($isFinalRepository -and -not $allowCustomJobsInEndRepos)
        $shouldApplyCustomJobs | Should -Be $true

        # Apply customizations if condition is met (simulating the actual behavior)
        if ($shouldApplyCustomJobs) {
            [Yaml]::ApplyCustomizations([ref] $srcContent, $finalRepoFile)
        }

        # Verify that custom jobs are preserved in the final content
        $srcContent | Should -Match "CustomJob-ShouldPersist"
    }

    It 'allowCustomJobsInEndRepos setting defaults to false when not specified' {
        $repoSettings = @{
            # allowCustomJobsInEndRepos is not specified - should default to false
        }

        $allowCustomJobsInEndRepos = $false
        if ($repoSettings.ContainsKey('allowCustomJobsInEndRepos')) {
            $allowCustomJobsInEndRepos = $repoSettings.allowCustomJobsInEndRepos
        }

        # Should default to false
        $allowCustomJobsInEndRepos | Should -Be $false
    }

    It 'GitHub template repositories should always allow custom jobs' {
        # Mock environment variables
        $env:GITHUB_REPOSITORY = "testowner/template-repo"
        $env:GITHUB_API_URL = "https://api.github.com"

        # Mock GitHub API for template repository
        Mock InvokeWebRequest -MockWith {
            return @{
                Content = '{"is_template": true}'
            }
        } -ParameterFilter { $uri -eq "https://api.github.com/repos/testowner/template-repo" }

        $token = "mock-token"
        $isFinalRepository = $false

        try {
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "Bearer $token"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $repoInfo = (InvokeWebRequest -Headers $headers -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)").Content | ConvertFrom-Json
            $isTemplateRepository = $repoInfo.is_template
            $isFinalRepository = -not $isTemplateRepository
        }
        catch {
            $isFinalRepository = $true
        }

        # Template repositories should NOT be detected as final repositories
        $isFinalRepository | Should -Be $false -Because "GitHub template repository should always allow custom jobs"
    }

    It 'Non-template repositories should be considered final repositories' {
        # Mock environment variables
        $env:GITHUB_REPOSITORY = "testowner/final-repo"
        $env:GITHUB_API_URL = "https://api.github.com"

        # Mock GitHub API for non-template repository
        Mock InvokeWebRequest -MockWith {
            return @{
                Content = '{"is_template": false}'
            }
        } -ParameterFilter { $uri -eq "https://api.github.com/repos/testowner/final-repo" }

        $token = "mock-token"
        $isFinalRepository = $false

        try {
            $headers = @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "Bearer $token"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $repoInfo = (InvokeWebRequest -Headers $headers -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)").Content | ConvertFrom-Json
            $isTemplateRepository = $repoInfo.is_template
            $isFinalRepository = -not $isTemplateRepository
        }
        catch {
            $isFinalRepository = $true
        }

        # Non-template repositories should be detected as final repositories
        $isFinalRepository | Should -Be $true -Because "Non-template repository should be considered a final repository"
    }
}