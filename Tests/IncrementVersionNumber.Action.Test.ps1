Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "IncrementVersionNumber Action Tests" {
    BeforeAll {
        $actionName = "IncrementVersionNumber"
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
            "contents" = "write"
            "pull-requests" = "write"
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # Call action
}

Describe "Set-SettingInFile tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\Actions\AL-Go-Helper.ps1" -Resolve)
        Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\Actions\IncrementVersionNumber\IncrementVersionNumber.psm1" -Resolve) -Force
    }

    BeforeEach {
        # Create test JSON settings file in the temp folder
        $settingsFilePath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).json"
        $settingsFileContent = [ordered]@{
            "repoVersion" = "0.1"
            "otherSetting" = "otherSettingValue"
        }
        $settingsFileContent | ConvertTo-Json | Set-Content $settingsFilePath -Encoding UTF8
    }

    It 'Set-SettingInFile -settingsFilePath not found' {
        $nonExistingFile = Join-Path ([System.IO.Path]::GetTempPath()) "UnknownFile.json"
        $settingName = 'repoVersion'
        $newValue = '1.0'
        $incremental = $false

        { Set-SettingInFile -settingsFilePath $nonExistingFile -settingName $settingName -newValue $newValue -incremental:$incremental } | Should -Throw "Settings file ($nonExistingFile) not found."
    }

    It 'Set-SettingInFile -settingName not found' {
        $settingName = 'repoVersion2'
        $newValue = '1.0'
        $incremental = $false

        { Set-SettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue -incremental:$incremental } | Should -Not -Throw

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent | Should -Not -Contain $settingName
        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
        $newSettingsContent.repoVersion | Should -Be "0.1"
    }

    It 'Set-SettingInFile -newValue is set' {
        $settingName = 'repoVersion'
        $newValue = '1.0'
        $incremental = $false

        Set-SettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue -incremental:$incremental

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-SettingInFile -newValue is added to the old value' {
        $settingName = 'repoVersion'
        $newValue = '0.1'
        $incremental = $true

        Set-SettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue -incremental:$incremental

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.2"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    AfterEach {
        Remove-Item $settingsFilePath -Force
    }
}
