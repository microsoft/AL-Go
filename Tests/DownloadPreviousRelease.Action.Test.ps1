Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "DownloadPreviousRelease Action Tests" {
    BeforeAll {
        $actionName = "DownloadPreviousRelease"
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

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "PreviousAppsPath" = "Path to the folder containing the downloaded previous release apps."
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    Context 'Download Previous Release' {
        BeforeAll {
            . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1")
        }

        BeforeEach {
            # Set up the function from the action script
            Invoke-Expression $actionScript

            # Mock dependencies
            Mock Get-BasePath { return $TestDrive }
            Mock OutputGroupStart {}
            Mock OutputGroupEnd {}
            Mock OutputWarning {}
            Mock OutputError {}

            # Set up GITHUB_OUTPUT
            $script:githubOutputFile = Join-Path $TestDrive "github_output.txt"
            $env:GITHUB_OUTPUT = $script:githubOutputFile
            '' | Set-Content $script:githubOutputFile

            # Set env vars used by the script
            $env:GITHUB_REF_NAME = 'main'
            $env:GITHUB_API_URL = 'https://api.github.com'
            $env:GITHUB_REPOSITORY = 'testorg/testrepo'
        }

        AfterEach {
            Remove-Item -Path $env:GITHUB_OUTPUT -Force -ErrorAction SilentlyContinue
            $env:GITHUB_OUTPUT = ''
            $env:GITHUB_REF_NAME = ''
            $env:GITHUB_API_URL = ''
            $env:GITHUB_REPOSITORY = ''
            $env:GITHUB_BASE_REF = ''
        }

        It 'Downloads previous release apps and outputs path' {
            $mockRelease = @{ name = 'v1.0'; tag_name = '1.0.0' }
            Mock GetLatestRelease { return $mockRelease }
            Mock DownloadRelease {
                # Simulate unpacked app file in the target path
                $appFile = Join-Path $path "TestPublisher_TestApp_1.0.0.0.app"
                New-Item -Path $appFile -ItemType File -Force | Out-Null
            }

            DownloadPreviousRelease -token 'dummy' -project '.'

            Should -Invoke GetLatestRelease -Times 1
            Should -Invoke DownloadRelease -Times 1
            $output = Get-Content $script:githubOutputFile -Raw
            $output | Should -Match 'PreviousAppsPath='
        }

        It 'Warns when no previous release is found' {
            Mock GetLatestRelease { return $null }

            DownloadPreviousRelease -token 'dummy' -project '.'

            Should -Invoke OutputWarning -Times 1 -ParameterFilter { $message -eq 'No previous release found' }
            $output = Get-Content $script:githubOutputFile -Raw
            $output | Should -Match 'PreviousAppsPath='
        }

        It 'Uses wildcard for root project to match release assets' {
            $mockRelease = @{ name = 'v1.0'; tag_name = '1.0.0' }
            Mock GetLatestRelease { return $mockRelease }
            Mock DownloadRelease {}

            DownloadPreviousRelease -token 'dummy' -project '.'

            Should -Invoke DownloadRelease -Times 1 -ParameterFilter { $projects -eq '*' }
        }
    }
}
