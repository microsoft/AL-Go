Get-Module IncrementVersionNumber | Remove-Module -Force
Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

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

Describe "Set-VersionInSettingsFile tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\Actions\AL-Go-Helper.ps1" -Resolve)
        Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\Actions\IncrementVersionNumber\IncrementVersionNumber.psm1" -Resolve) -Force

        $settingsFile = "<not set>" # Might be used in tests, used in AfterEach

        function New-TestSettingsFilePath {
            param(
                [string] $repoVersion = '0.1'
            )

            # Create test JSON settings file in the temp folder
            $settingsFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).json"
            $settingsFileContent = [ordered]@{
                "repoVersion" = $repoVersion
                "otherSetting" = "otherSettingValue"
            }
            $settingsFileContent | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8

            return $settingsFile
        }
    }

    It 'Set-VersionInSettingsFile -settingsFilePath not found' {
        $nonExistingFile = Join-Path ([System.IO.Path]::GetTempPath()) "unknown.json"
        $settingName = 'repoVersion'
        $newValue = '1.0'

        { Set-VersionInSettingsFile -settingsFilePath $nonExistingFile -settingName $settingName -newValue $newValue } | Should -Throw "Settings file ($nonExistingFile) not found."
    }

    It 'Set-VersionInSettingsFile version setting not found' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion2'
        $newValue = '1.0'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Not -Throw

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent | Should -Not -Contain $settingName
        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
        $newSettingsContent.repoVersion | Should -Be "0.1"
    }

    It 'Set-VersionInSettingsFile version setting not found and Force is set' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion2'
        $newValue = '1.0'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue -Force } | Should -Not -Throw

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        # Check the new setting is created
        $newSettingsContent.$settingName | Should -Be "1.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
        $newSettingsContent.repoVersion | Should -Be "0.1"
    }

    It 'Set-VersionInSettingsFile setting same value' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.0'
        $settingName = 'repoVersion'
        $newValue = '1.0'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue -Force } | Should -Not -Throw

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json

        # Check that the other setting are not changed
        $newSettingsContent.$settingName | Should -Be "1.0"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.2 is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '+0.2'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - incremental version number $newValue is not allowed. Allowed incremental version numbers are: +1, +0.1, +0.0.1"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +3 is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '+3'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - incremental version number $newValue is not allowed. Allowed incremental version numbers are: +1, +0.1, +0.0.1"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue 1.2.3.4 is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '1.2.3.4'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build (e.g. 1.0, 1.2 or 1.3.0)"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue -1 is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '-1'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build (e.g. 1.0, 1.2 or 1.3.0)"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue -1 is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '-1'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build (e.g. 1.0, 1.2 or 1.3.0)"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue abcd is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = 'abcd'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build (e.g. 1.0, 1.2 or 1.3.0)"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue a.b is not allowed' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = 'a.b'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor or Major.Minor.Build (e.g. 1.0, 1.2 or 1.3.0)"

        # Check that the settings are not changed
        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "0.1"
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue 1.0 is set' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '1.0'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue 2.0 throws an error because it''s not incremented' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '2.0'
        $settingName = 'repoVersion'
        $newValue = '1.0'

        { Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue } | Should -Throw "The new version number ($newValue) is less than the old version number (2.0). The version number must be incremented."

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "2.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +1 increments the major version number and sets the minor version number to 0' {
        $settingsFile = New-TestSettingsFilePath
        $settingName = 'repoVersion'
        $newValue = '+1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.1 incremenFilents the minor version number' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.3"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.1 succeeds even if the new version string is less than the old version string' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.9'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.10"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.1 succeeds even if the new version string is less than the old version string' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.9.2'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.10.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.0.1 succeeds even if the new version string is less than the old version string' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.9.2'
        $settingName = 'repoVersion'
        $newValue = '+0.0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.9.3"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.0.1 adds another segment if the version number only has 2 segments' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.9'
        $settingName = 'repoVersion'
        $newValue = '+0.0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.9.1"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue is set and build and revision are set to 0'{
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2.1.2'
        $settingName = 'repoVersion'
        $newValue = '2.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "2.1.0.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.1 incremenFilents the minor version number and build and revision are set to 0' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2.3.4'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.3.0.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.0.1 incremenFilents the minor version number and revision is set to 0' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2.3.4'
        $settingName = 'repoVersion'
        $newValue = '+0.0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.2.4.0"

        # Check that the other setting are not changed
        $newSettingsContent.otherSetting | Should -Be "otherSettingValue"
    }

    It 'Set-VersionInSettingsFile -newValue +0.1 makes build and revision 0 if they are initially set' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2.3.4'
        $settingName = 'repoVersion'
        $newValue = '+0.1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "1.3.0.0"
    }

    It 'Set-VersionInSettingsFile -newValue +1 makes build and revision 0 if they are initially set' {
        $settingsFile = New-TestSettingsFilePath -repoVersion '1.2.3.4'
        $settingName = 'repoVersion'
        $newValue = '+1'

        Set-VersionInSettingsFile -settingsFilePath $settingsFile -settingName $settingName -newValue $newValue

        $newSettingsContent = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
        $newSettingsContent.$settingName | Should -Be "2.0.0.0"
    }

    AfterEach {
        Remove-Item $settingsFile -Force -ErrorAction Ignore
    }
}
