Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "ReadSettings Action Tests" {
    BeforeAll {
        $actionName = "ReadSettings"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        # Mock Write-Host { }
        Mock Out-Host { }
    }

    BeforeEach {
        $testFolder = (Join-Path ([System.IO.Path]::GetTempPath()) "readSettingsActionTest")
        New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
        $env:GITHUB_ENV = (Join-Path $testFolder "githubEnv")
        $env:GITHUB_OUTPUT = (Join-Path $testFolder "githubOutput")
        New-Item -Path $env:GITHUB_ENV -ItemType file -Force | Out-Null
        New-Item -Path $env:GITHUB_OUTPUT -ItemType file -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $testFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "GitHubRunnerJson" = "GitHubRunner in compressed Json format"
            "GitHubRunnerShell" = "Shell for GitHubRunner jobs"
            "SelectedSettingsJson" = "Selected settings from the get parameter in compressed JSON format"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Settings in get param are correctly added to SelectedSettingsJson output' {
        & $scriptPath `
            -project '' `
            -get 'shortLivedArtifactsRetentionDays,powerPlatformSolutionFolder'

        # Read the output file content
        $outputContent = Get-Content $env:GITHUB_OUTPUT

        # Find the SelectedSettingsJson line and extract its value
        $selectedSettingsLine = $outputContent | Where-Object { $_ -match '^SelectedSettingsJson=(.*)$' }
        $selectedSettingsLine | Should -Not -BeNullOrEmpty

        # Extract the JSON value from the line
        if ($selectedSettingsLine -match '^SelectedSettingsJson=(.*)$') {
            $jsonValue = $Matches[1]

            # Parse the JSON to verify it's valid
            $settingsObject = $jsonValue | ConvertFrom-Json

            # Verify the expected properties are present
            $settingsObject.PSObject.Properties.Name | Should -Contain 'shortLivedArtifactsRetentionDays'
            $settingsObject.PSObject.Properties.Name | Should -Contain 'powerPlatformSolutionFolder'

            # Verify the values are correct (assuming default values)
            $settingsObject.shortLivedArtifactsRetentionDays | Should -Be 1
            $settingsObject.powerPlatformSolutionFolder | Should -Be ''
        } else {
            throw "Could not extract JSON value from SelectedSettingsJson output"
        }
    }
}
