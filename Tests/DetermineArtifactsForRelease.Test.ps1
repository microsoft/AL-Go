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
            param([string] $name, [string] $sha = 'abc123')
            [PSCustomObject]@{
                name = $name
                expired = $false
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

        It 'Throws original error when a project has no artifacts of any kind' {
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*actions/artifacts*' } -MockWith {
                [PSCustomObject]@{ total_count = 0; Artifacts = @() }
            }

            { & $scriptPath -buildVersion 'latest' -GITHUB_TOKEN 'tok' -TOKENFORPUSH 'tok' -ProjectsJson '["proj1"]' } |
                Should -Throw -ExpectedMessage '*No artifacts found for this project*'
        }
    }
}
