function ValidateSettings($Settings) {
    $ObsoletedSettings = [ordered]@{
        "*-Projects" = @{ type = "Error"; message = "The setting '*-Projects' is no longer supported" }
        "*_Projects" = @{ type = "Error"; message = "The setting '*-Projects' is no longer supported" }
        "cache*" = @{ type = "Error"; message =  "The setting 'enableCodeCop' is no longer supported" }
    }

    $ObsoletedSettings.Keys | ForEach-Object {
        $obsoletedSettingName = $_
        $obsoletedSetting = $ObsoletedSettings[$obsoletedSettingName]

        Write-Host "Checking for obsoleted setting '$obsoletedSettingName'" -ForegroundColor DarkGray

        if ($Settings.Keys -contains $obsoletedSetting) {
            if ($obsoletedSetting.Type -eq "Warning") {
                Write-Host "::Warning::$($obsoletedSetting.message). This warning will become an error in a future release."
            } else {
                Write-Host "::Error::$($obsoletedSetting.message)."
            }
        }

        $Settings.Keys | Where-Object { $_ -like $obsoletedSettingName } | ForEach-Object {
            if ($obsoletedSetting.Type -eq "Warning") {
                Write-Host "::Warning::$($obsoletedSetting.message). This warning will become an error in a future release."
            } else {
                Write-Host "::Error::$($obsoletedSetting.message)."
            }
        }
    }
}