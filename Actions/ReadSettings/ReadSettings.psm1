function ValidateSettings($Settings) {
    $ObsoletedSettings = [ordered]@{
        "*-Projects" = @{ type = "Error"; message = "The setting should be replaced by using the Projects property in the DeployTo* setting in .github/AL-Go-Settings.json instead" }
        "*_Projects" = @{ type = "Error"; message = "The setting should be replaced by using the Projects property in the DeployTo* setting in .github/AL-Go-Settings.json instead" }
        "cache*" = @{ type = "Warning"; message =  "The setting 'enableCodeCop' is no longer supported" }
    }

    $foundError = $false

    $ObsoletedSettings.Keys | ForEach-Object {
        $obsoletedSettingName = $_
        $obsoletedSetting = $ObsoletedSettings[$obsoletedSettingName]

        # Check if the setting is present in the settings file
        if ($Settings.Keys -contains $obsoletedSetting) {
            if ($obsoletedSetting.Type -eq "Warning") {
                Write-Host "::Warning::The setting $obsoletedSetting has been obsoleted. $($obsoletedSetting.message). This warning will become an error in a future release."
            } else {
                Write-Host "::Error::. $($obsoletedSetting.message)."
                $foundError = $true
            }
        }

        # Check if there's a setting that matches the pattern
        $Settings.Keys | Where-Object { $_ -like $obsoletedSettingName } | ForEach-Object {
            if ($obsoletedSetting.Type -eq "Warning") {
                Write-Host "::Warning::The setting $_ has been obsoleted. $($obsoletedSetting.message). This warning will become an error in a future release."
            } else {
                Write-Host "::Error::$($obsoletedSetting.message)."
                $foundError = $true
            }
        }
    }

    # Throw an error if any obsolete settings were found
    if ($foundError) {
        throw "Obsolete settings found. Please remove them from your settings file."
    }
}