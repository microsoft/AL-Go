Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "WorkflowInitialize Action Tests" {
    BeforeAll {
        $actionName = "WorkflowInitialize"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
          "correlationId" = "A correlation Id for the workflow"
          "telemetryScopeJson" = "A telemetryScope that covers the workflow"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    It 'Test Test-AL-Go-Repository' {

        function TestSettingsFiles {
            Param(
                [string]$ALGoOrgSettings,
                [string]$ALGoRepoSettings,
                [string]$repoSettings,
                [string]$projectSettings,
                [string]$project1Settings
            )

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
            New-Item -Path $tempDir -ItemType Directory | Out-Null
            try {
                $githubFolder = Join-Path $tempDir '.github'
                New-Item -Path $githubFolder -ItemType Directory | Out-Null
                $ALGoFolder = Join-Path $tempDir '.AL-Go'
                New-Item -Path $ALGoFolder -ItemType Directory | Out-Null
                $Project1ALGoFolder = Join-Path $tempDir 'Project1/.AL-Go'
                New-Item -Path $Project1ALGoFolder -ItemType Directory | Out-Null
                $ENV:ALGoOrgSettings = $ALGoOrgSettings
                $ENV:ALGoRepoSettings = $ALGoRepoSettings
                Set-Content -Path (Join-Path $githubFolder 'AL-Go-Settings.json') -Value $repoSettings -Encoding UTF8
                Set-Content -Path (Join-Path $ALGoFolder 'settings.json') -Value $projectSettings -Encoding UTF8
                Set-Content -Path (Join-Path $Project1ALGoFolder 'settings.json') -Value $project1Settings -Encoding UTF8
                Test-ALGoRepository -baseFolder $tempDir
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force
            }
        }

        . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)
        . (Join-Path $PSScriptRoot "..\Actions\AL-Go-TestRepoHelper.ps1" -Resolve)

        TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings '{}' `
            -project1Settings '{}'

        TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{"templateUrl":"https://github.com/microsoft/AL-Go-PTE@latest"}' `
            -projectSettings '{}' `
            -project1Settings '{}'

        TestSettingsFiles `
            -ALGoOrgSettings '{"templateUrl":"https://github.com/microsoft/AL-Go-PTE@latest"}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings '{}' `
            -project1Settings '{}'

        {TestSettingsFiles `
            -ALGoOrgSettings ' {}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings '{}' `
            -project1Settings '{}' }| Should -Throw

        {TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings ' {}' `
            -repoSettings '{}' `
            -projectSettings '{}' `
            -project1Settings '{}' }| Should -Throw

        {TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings ' {}' `
            -projectSettings '{}' `
            -project1Settings '{}' }| Should -Throw

        {TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings ' {}' `
            -project1Settings '{}' }| Should -Throw

        {TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings '{}' `
            -project1Settings ' {}' }| Should -Throw

        {TestSettingsFiles `
            -ALGoOrgSettings '{}' `
            -ALGoRepoSettings '{}' `
            -repoSettings '{}' `
            -projectSettings '{"templateUrl":"https://github.com/microsoft/AL-Go-PTE@latest"}' `
            -project1Settings '{}' }| Should -Throw
    }
}
