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

Describe "Set-VersionSettingInFile tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\Actions\AL-Go-Helper.ps1" -Resolve)
        Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\Actions\IncrementVersionNumber\IncrementVersionNumber.psm1" -Resolve) -Force

        $settingsFilePath = "<not set>" # Might be used in tests, used in AfterEach

        function New-TestSettingsFile {
            param(
                [string] $repoVersion = '0.1'
            )

            # Create test JSON settings file in the temp folder
            $settingsFilePath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).json"
            $settingsFileContent = [ordered]@{
                "repoVersion" = $repoVersion
                "otherSetting" = "otherSettingValue"
            }
            $settingsFileContent | ConvertTo-Json | Set-Content $settingsFilePath -Encoding UTF8

            return $settingsFilePath
        }
    }

    It 'Set-VersionSettingInFile -settingsFilePath not found' {
        $nonExistingFile = Join-Path ([System.IO.Path]::GetTempPath()) "UnknownFile.json"
        $settingName = 'repoVersion'
        $newValue = '1.0'

        { Set-VersionSettingInFile -settingsFilePath $nonExistingFile -settingName $settingName -newValue $newValue } | Should -Throw "Settings file ($nonExistingFile) not found."
    }

    It 'Set-VersionSettingInFile -settingName not found' {
        $settingsFilePath = New-TestSettingsFile
        $settingName = 'repoVersion2'
        $newValue = '1.0'

        { Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue } | Should -Not -Throw

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent | Should -Not -Contain $settingName
        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
        $newSettingsContent.repoVersion | Should -Be "0.1"
    }

    It 'Set-VersionSettingInFile -newValue is set' {
        $settingsFilePath = New-TestSettingsFile
        $settingName = 'repoVersion'
        $newValue = '1.0'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionSettingInFile -newValue is added to the old value (minor version)' {
        $settingsFilePath = New-TestSettingsFile
        $settingName = 'repoVersion'
        $newValue = '+0.2'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.3"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionSettingInFile -newValue is added to the old value (major value)' {
        $settingsFilePath = New-TestSettingsFile
        $settingName = 'repoVersion'
        $newValue = '+1.0'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.1"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionSettingInFile -newValue is added to the old value (major and minor value)' {
        $settingsFilePath = New-TestSettingsFile -repoVersion '1.2'
        $settingName = 'repoVersion'
        $newValue = '+3.4'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "4.6"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionSettingInFile -newValue is set and build and revision are kept from the old value'{
        $settingsFilePath = New-TestSettingsFile -repoVersion '1.2.0.0'
        $settingName = 'repoVersion'
        $newValue = '2.1'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "2.1.0.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionSettingInFile -newValue is added and build and revision are kept from the old value' {
        $settingsFilePath = New-TestSettingsFile -repoVersion '1.2.3.4'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionSettingInFile -settingsFilePath $settingsFilePath -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.3.3.4"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    AfterEach {
        Remove-Item $settingsFilePath -Force -ErrorAction Ignore
    }
}
