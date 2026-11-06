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
            param([string] $name, [string] $sha = 'abc123', [string] $createdAt = '2026-01-01T00:00:00Z')
            [PSCustomObject]@{
                name = $name
                expired = $false
                created_at = $createdAt
                archive_download_url = "https://example.com/artifacts/$name"
                workflow_run = [PSCustomObject]@{ head_sha = $sha }
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
            $script:originalGitHubWorkspace = $env:GITHUB_WORKSPACE
            $script:workspaceFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -Path $script:workspaceFolder -ItemType Directory | Out-Null
            $env:GITHUB_WORKSPACE = $script:workspaceFolder
            'proj1', 'proj2' | ForEach-Object { New-Item -Path (Join-Path $script:workspaceFolder $_) -ItemType Directory | Out-Null }

            function NewProjectSettings {
                param([string] $project, [hashtable] $projectSettings)
                $alGoFolder = Join-Path $script:workspaceFolder (Join-Path $project '.AL-Go')
                New-Item -Path $alGoFolder -ItemType Directory -Force | Out-Null
                $projectSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $alGoFolder 'settings.json') -Encoding UTF8
            }
        }

        AfterAll {
            $env:GITHUB_WORKSPACE = $script:originalGitHubWorkspace
            if ($script:workspaceFolder -and (Test-Path $script:workspaceFolder)) {
                Remove-Item -Path $script:workspaceFolder -Recurse -Force
            }
        }

        BeforeEach {
            $script:githubOutputFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -Path $script:githubOutputFile -ItemType File | Out-Null
            $env:GITHUB_OUTPUT = $script:githubOutputFile
        }

        AfterEach {
            if ($script:githubOutputFile -and (Test-Path $script:githubOutputFile)) {
                Remove-Item -Path $script:githubOutputFile -Force
            }
        }

        It 'Mixed projects (apps + test artifacts) produce a non-empty include list' {
            $artifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.0.0'),
                (MockArtifact 'proj1-main-TestApps-1.0.0.0'),
                (MockArtifact 'proj2-main-Apps-1.0.0.0')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'abc123' } }
            }

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'commitish=abc123'
            $output | Should -Match 'proj1-main-Apps-1\.0\.0\.0'
            $output | Should -Match 'proj1-main-TestApps-1\.0\.0\.0'
            $output | Should -Match 'proj2-main-Apps-1\.0\.0\.0'
        }

        It 'Test-only project is skipped with a warning (including build-mode test artifacts)' {
            $artifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.0.0'),
                (MockArtifact 'proj2-main-CleanTestApps-1.0.0.0')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'abc123' } }
            }
            Mock Write-Host { } -ParameterFilter { "$Object" -like '::Warning::*proj2*' }

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]'

            Assert-MockCalled Write-Host -ParameterFilter { "$Object" -like '::Warning::*proj2*' } -Scope It
            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'proj1-main-Apps-1\.0\.0\.0'
            $output | Should -Not -Match 'proj2-main-CleanTestApps'
        }

        It 'Throws a clear error when no project has releasable artifacts' {
            $artifacts = @(
                (MockArtifact 'proj1-main-TestApps-1.0.0.0')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No release artifacts found for any project*'
        }

        It 'Test project (projectsToTest) is skipped even though it has no artifacts' {
            NewProjectSettings -project 'testproj' -projectSettings @{ projectsToTest = @('proj1') }
            $artifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.0.0'),
                (MockArtifact 'proj1-main-TestApps-1.0.0.0')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'abc123' } }
            }

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","testproj"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'commitish=abc123'
            $output | Should -Match 'proj1-main-Apps-1\.0\.0\.0'
            $output | Should -Match 'proj1-main-TestApps-1\.0\.0\.0'
            $output | Should -Not -Match 'testproj'
        }

        It 'Throws a clear error when only test projects are present' {
            NewProjectSettings -project 'testproj' -projectSettings @{ projectsToTest = @('proj1') }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["testproj"]' } |
                Should -Throw -ExpectedMessage '*No release artifacts found for any project*'
        }

        It 'Throws original error when a project has no artifacts of any kind' {
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No artifacts found for this project*'
        }

        It 'Latest selects the most recently created artifacts, regardless of API order' {
            # Artifacts in the order returned by the API (descending artifact id, which isn't chronological)
            $artifacts = @(
                (MockArtifact 'W1-main-BuildOutput-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:14:17Z'),
                (MockArtifact 'W1-main-Apps-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:14:15Z'),
                (MockArtifact 'US-main-Apps-1.0.2.0' -sha 'sha2' -createdAt '2026-11-04T14:47:23Z'),
                (MockArtifact 'DK-main-Apps-1.0.4.0' -sha 'sha4' -createdAt '2026-11-04T14:52:08Z'),
                (MockArtifact 'DK-main-Apps-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:12:21Z'),
                (MockArtifact 'DK-main-BuildOutput-1.0.4.0' -sha 'sha4' -createdAt '2026-11-04T14:52:10Z'),
                (MockArtifact 'US-main-Apps-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:11:21Z'),
                (MockArtifact 'DK-main-TestApps-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:12:22Z'),
                (MockArtifact 'DK-main-TestApps-1.0.4.0' -sha 'sha4' -createdAt '2026-11-04T14:52:09Z')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/branches/*' } -MockWith {
                [PSCustomObject]@{ commit = [PSCustomObject]@{ sha = 'sha5' } }
            }

            & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["DK","US","W1"]'

            $output = Get-Content $env:GITHUB_OUTPUT -Raw
            $output | Should -Match 'commitish=sha5'
            $output | Should -Match 'DK-main-Apps-1\.0\.5\.0'
            $output | Should -Match 'DK-main-TestApps-1\.0\.5\.0'
            $output | Should -Match 'US-main-Apps-1\.0\.5\.0'
            $output | Should -Match 'W1-main-Apps-1\.0\.5\.0'
            $output | Should -Not -Match '1\.0\.4\.0'
            $output | Should -Not -Match '1\.0\.2\.0'
        }

        It 'Throws a descriptive error when the latest artifacts of projects come from different commits' {
            $artifacts = @(
                (MockArtifact 'proj1-main-Apps-1.0.5.0' -sha 'sha5' -createdAt '2026-11-04T15:00:00Z'),
                (MockArtifact 'proj2-main-Apps-1.0.4.0' -sha 'sha4' -createdAt '2026-11-04T14:00:00Z')
            )
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=1*' } -MockWith {
                [PSCustomObject]@{ total_count = $artifacts.Count; Artifacts = $artifacts }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*page=2*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1","proj2"]' } |
                Should -Throw -ExpectedMessage "*doesn't contain all projects*proj2-main-Apps-1.0.4.0*proj2*sha4*sha5*"
        }
    }
}
