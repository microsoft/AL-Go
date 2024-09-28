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
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
            "GitHubRunnerJson" = "GitHubRunner in compressed Json format"
            "GitHubRunnerShell" = "Shell for GitHubRunner jobs"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
}

Describe "ReadSettings Schema" {
    BeforeAll {
        $actionName = "ReadSettings"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $schemaPath = Join-Path $scriptRoot "settings.schema.json"
        $schema = Get-Content -Path $schemaPath -Raw
    }

    It 'Schema is valid' {
        Test-Json -json $schema | Should -Be $true
    }

    It 'Default settings match schema' {
        . (Join-Path -Path $scriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        $defaultSettings = GetDefaultSettings -repoName 'ReadSettings'
        Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema | Should -Be $true
    }

    It 'Shell setting can only be pwsh or powershell' {
        . (Join-Path -Path $scriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        $defaultSettings = GetDefaultSettings -repoName 'ReadSettings'
        $defaultSettings.shell = 42
        try {
            Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
        }
        catch {
            $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"integer`" but should be `"string`" at '/shell'"
        }

        $defaultSettings.shell = "random"
        try {
            Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
        }
        catch {
            $_.Exception.Message | Should -Be "The JSON is not valid with the schema: The string value is not a match for the indicated regular expression at '/shell'"
        }
    }
}
