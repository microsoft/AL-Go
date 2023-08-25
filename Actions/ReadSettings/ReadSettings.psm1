function ValidateSettings($Settings) {
    $ObsoletedSettings = Get-Content -Path (Join-Path $PSScriptRoot "ObsoletedSettings.json") | ConvertFrom-Json | ConvertTo-HashTable

    $foundError = $false

    $ObsoletedSettings.Keys | ForEach-Object {
        $obsoletedSettingName = $_
        $obsoletedSetting = $ObsoletedSettings[$obsoletedSettingName]

        # Check if the setting is present in the settings file
        if ($Settings.Keys -contains $obsoletedSettingName) {
            PrintObsoleteMessage -SettingName $obsoletedSettingName -Message $obsoletedSetting.message -Type $obsoletedSetting.Type
            if ($obsoletedSetting.Type -eq "Error") {
                $foundError = $true
            }
        }

        # Check if there's a setting that matches the pattern
        $Settings.Keys | Where-Object { $_ -like $obsoletedSettingName } | ForEach-Object {
            PrintObsoleteMessage -Setting $_ -Message $obsoletedSetting.message -Type $obsoletedSetting.Type
            if ($obsoletedSetting.Type -eq "Error") {
                $foundError = $true
            }
        }
    }

    # Throw an error if any obsolete settings were found
    if ($foundError) {
        throw "Obsolete settings found. Please update your Al-Go settings."
    }
}

function PrintObsoleteMessage($SettingName, $Message, $Type) {
    if ($Type -eq "Warning") {
        Write-Host "::Warning::The Al-Go setting $SettingName has been obsoleted. $Message This warning will become an error in a future release."
    } else {
        Write-Host "::Error::The Al-Go setting $SettingName has been obsoleted. $Message"
    }
}