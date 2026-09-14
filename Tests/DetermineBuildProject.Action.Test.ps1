Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "DetermineBuildProject Action Tests" {
    BeforeAll {
        $actionName = "DetermineBuildProject"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    Context 'Determine whether to build a skipped project' {
        BeforeAll {
            . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1")
        }

        BeforeEach {
            # Set up the function from the action script
            Invoke-Expression $actionScript

            # Set up GITHUB_OUTPUT
            $script:githubOutputFile = Join-Path $TestDrive "github_output.txt"
            $env:GITHUB_OUTPUT = $script:githubOutputFile
            '' | Set-Content $script:githubOutputFile

            # Set env vars used by the script
            $env:Settings = '{}'
            $script:workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -Path $script:workspace -ItemType Directory -Force | Out-Null
            $env:GITHUB_WORKSPACE = $script:workspace
            $env:GITHUB_API_URL = 'https://api.github.com'
            $env:GITHUB_REPOSITORY = 'testorg/testrepo'

            # By default no baseline artifacts are found, so the project needs to be built
            Mock GetArtifactsFromWorkflowRun { return $null }
            Mock DownloadArtifact {}
        }

        AfterEach {
            Remove-Item -Path $env:GITHUB_OUTPUT -Force -ErrorAction SilentlyContinue
            $env:GITHUB_OUTPUT = ''
            $env:Settings = ''
            $env:GITHUB_WORKSPACE = ''
            $env:GITHUB_API_URL = ''
            $env:GITHUB_REPOSITORY = ''
        }

        It 'Downloads the Default build mode artifacts (no build mode prefix) for a skipped Default build' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'Default'

            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'Apps' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly -ParameterFilter { $mask -eq 'DefaultApps' }
        }

        It 'Downloads the build mode-prefixed artifacts for a skipped non-Default build' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'BC27'

            # The BC27 dimension must download the BC27-prefixed artifacts, not the Default (unprefixed) ones
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'BC27Apps' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'BC27TestApps' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'BC27Dependencies' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly -ParameterFilter { $mask -eq 'Apps' }
        }

        It 'Never build mode-prefixes the PowerPlatformSolution mask (always built with Default build mode)' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'BC27'

            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'PowerPlatformSolution' }
            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly -ParameterFilter { $mask -eq 'BC27PowerPlatformSolution' }
        }

        It 'Defaults to the Default build mode when no build mode is provided' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123'

            Should -Invoke GetArtifactsFromWorkflowRun -Times 1 -Exactly -ParameterFilter { $mask -eq 'Apps' }
        }

        It 'Extracts downloaded artifacts into the build mode-agnostic folder name' {
            Mock GetArtifactsFromWorkflowRun {
                if ($mask -eq 'BC27Apps') { return @{ name = 'ProjectA-main-BC27Apps-1.0.0.0' } } else { return $null }
            }
            Mock DownloadArtifact {
                # Simulate a downloaded zip file
                $zipFile = Join-Path $path "artifact.zip"
                New-Item -Path $zipFile -ItemType File -Force | Out-Null
                return $zipFile
            }
            Mock Expand-Archive {}
            Mock Remove-Item {}

            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'BC27'

            # The extraction target must be the unprefixed 'Apps' folder that later build steps read from
            Should -Invoke Expand-Archive -Times 1 -Exactly -ParameterFilter { $DestinationPath -like '*.buildartifacts*Apps' -and $DestinationPath -notlike '*BC27Apps' }
        }

        It 'Sets BuildIt=True when no baseline artifacts are available' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '["ProjectA"]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'BC27'

            $output = Get-Content $script:githubOutputFile -Raw
            $output | Should -Match 'BuildIt=True'
        }

        It 'Sets BuildIt=True for a project that is not skipped without downloading artifacts' {
            DetermineBuildProject -token 'dummy' -skippedProjectsJson '[]' -project 'ProjectA' -baselineWorkflowRunId '123' -buildMode 'BC27'

            Should -Invoke GetArtifactsFromWorkflowRun -Times 0 -Exactly
            $output = Get-Content $script:githubOutputFile -Raw
            $output | Should -Match 'BuildIt=True'
        }
    }
}
