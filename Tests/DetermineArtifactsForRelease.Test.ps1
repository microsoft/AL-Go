[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
param()

Get-Module Github-Helper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)
Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'DetermineArtifactsForRelease Tests' {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1")

        $actionName = "DetermineArtifactsForRelease"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        function MockArtifact {
            param([string] $name, [int] $runId = 4711, [string] $sha = 'abc123')
            [PSCustomObject]@{
                name = $name
                expired = $false
                archive_download_url = "https://example.com/artifacts/$name"
                workflow_run = [PSCustomObject]@{ id = $runId; head_sha = $sha }
            }
        }
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "artifacts" = "The artifacts to publish on the release"
            "commitish" = "The target commitish for the release"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    Context 'Artifact selection behavior' {
        BeforeAll {
            $env:GITHUB_REPOSITORY = 'org/repo'
            $env:GITHUB_API_URL = 'https://api.github.com'
            $env:GITHUB_REF_NAME = 'main'
            $env:Settings = '{"repoName":"repo","type":"PTE","powerPlatformSolutionFolder":""}'
        }

        BeforeEach {
            $script:githubOutputFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -Path $script:githubOutputFile -ItemType File | Out-Null
            $env:GITHUB_OUTPUT = $script:githubOutputFile
            $runArtifacts = @()
            $artifactsByName = @{}
            Mock FindLatestSuccessfulCICDRun { 4711, 'abc123' }
            Mock GetArtifactsFromWorkflowRun { $runArtifacts }
            Mock Invoke-RestMethod { throw "Unexpected request: $Uri" }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'abc123' } }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/actions/artifacts?name=*' } -MockWith {
                $name = [Uri]::UnescapeDataString(($Uri -replace '^.*[?&]name=([^&]*).*$', '$1'))
                $found = @()
                if ($artifactsByName.ContainsKey($name)) { $found = @($artifactsByName[$name]) }
                [PSCustomObject]@{ total_count = $found.Count; artifacts = $found }
            }
        }

        AfterEach {
            if ($script:githubOutputFile -and (Test-Path $script:githubOutputFile)) {
                Remove-Item -Path $script:githubOutputFile -Force
            }
        }

        It 'Mixed projects (apps + test artifacts) produce a non-empty include list from the latest successful CI/CD run' {
            $runArtifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.0.0'),
                (MockArtifact 'proj1-main-TestApps-1.0.0.0'),
                (MockArtifact 'proj2-main-Apps-1.0.0.0')
            )

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'commitish=abc123'
            $output | Should -Match 'proj1-main-Apps-1\.0\.0\.0'
            $output | Should -Match 'proj1-main-TestApps-1\.0\.0\.0'
            $output | Should -Match 'proj2-main-Apps-1\.0\.0\.0'
            Should -Invoke FindLatestSuccessfulCICDRun -Times 1 -Exactly -ParameterFilter { $branch -eq 'main' -and $retention -eq 90 -and $repository -eq 'org/repo' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $workflowRun -eq '4711' -and $projects -eq 'proj1,proj2' -and $version -eq '*' }
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -like '*/actions/artifacts?per_page*' }
        }

        It 'Single project repository uses the repository name in artifact names' {
            $runArtifacts = @((MockArtifact 'repo-main-Apps-1.0.0.0'))

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["."]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'repo-main-Apps-1\.0\.0\.0'
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $projects -eq 'repo' }
        }

        It 'Test-only project is skipped with a warning (including build-mode test artifacts)' {
            $runArtifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.0.0'),
                (MockArtifact 'proj2-main-CleanTestApps-1.0.0.0')
            )
            Mock Write-Host { }
            Mock Write-Host { } -ParameterFilter { "$Object" -like '::Warning::*proj2*' }

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]'

            Should -Invoke Write-Host -ParameterFilter { "$Object" -like '::Warning::*proj2*' } -Times 1 -Exactly -Scope It
            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'proj1-main-Apps-1\.0\.0\.0'
            $output | Should -Not -Match 'proj2-main-CleanTestApps'
        }

        It 'Throws a clear error when no project has releasable artifacts' {
            $runArtifacts = @((MockArtifact 'proj1-main-TestApps-1.0.0.0'))

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No release artifacts found for any project*'
        }

        It 'Throws original error when a project has no artifacts of any kind' {
            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No artifacts found for this project*'
        }

        It 'Reports missing artifacts as before when no successful CI/CD run exists for latest' {
            Mock FindLatestSuccessfulCICDRun { 0, '' }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No artifacts found for this project*'
            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly
        }

        It 'Specific version finds the run by exact artifact name and reads only the artifacts of that run' {
            $artifactsByName['proj1-main-Apps-1.2.3.4'] = @(MockArtifact 'proj1-main-Apps-1.2.3.4' -runId 99 -sha 'def456')
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'def456' } }
            }
            $runArtifacts = @(
                (MockArtifact 'proj1-main-Apps-1.2.3.4' -runId 99 -sha 'def456'),
                (MockArtifact 'proj1-main-TestApps-1.2.3.4' -runId 99 -sha 'def456')
            )

            & $scriptPath -buildVersion '1.2.3.4' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'commitish=def456'
            $output | Should -Match 'proj1-main-Apps-1\.2\.3\.4'
            $output | Should -Match 'proj1-main-TestApps-1\.2\.3\.4'
            Should -Invoke FindLatestSuccessfulCICDRun -Times 0 -Exactly
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $workflowRun -eq '99' -and $version -eq '1.2.3.4' }
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -like '*/actions/artifacts?per_page*' }
        }

        It 'Specific version also finds PowerPlatformSolution artifacts and skips projects without release artifacts' {
            $artifactsByName['proj2-main-PowerPlatformSolution-1.2.3.4'] = @(MockArtifact 'proj2-main-PowerPlatformSolution-1.2.3.4' -runId 99)
            $runArtifacts = @(
                (MockArtifact 'proj1-main-TestApps-1.2.3.4' -runId 99),
                (MockArtifact 'proj2-main-PowerPlatformSolution-1.2.3.4' -runId 99)
            )

            & $scriptPath -buildVersion '1.2.3.4' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'proj2-main-PowerPlatformSolution-1\.2\.3\.4'
            $output | Should -Not -Match 'proj1-main-TestApps'
        }

        It 'Specific version reports missing artifacts as before when no artifact with that version exists' {
            { & $scriptPath -buildVersion '1.2.3.4' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No artifacts found for this project*'
            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly
        }
    }
}
