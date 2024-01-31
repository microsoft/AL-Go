<#
    .Synopsis
        Changes a setting value in a settings file.
    .Parameter settingsFilePath
        Path to the settings file.
    .Parameter settingName
        Name of the setting to change.
    .Parameter newValue
        New value of the setting.
    .Parameter incremental
        If set, the new value will be added to the old value. The old value must be a version number.
#>
function Set-SettingInFile($settingsFilePath, $settingName, $newValue, [switch] $incremental) {
    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    $settingFileContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json

    if (-not ($settingFileContent.PSObject.Properties.Name -eq $settingName)) {
        Write-Host "Setting $settingName not found in $settingsFilePath"
        return
    }

    $oldValue = $settingFileContent.$settingName

    if ($incremental) {
        $oldValue = [System.Version]$oldValue
        $newValue = [System.Version]$newValue

        $newValue = "$($newValue.Major + $oldValue.Major).$($newValue.Minor + $oldValue.Minor)"
    }

    Write-Host "Changing $settingName from $oldValue to $newValue in $settingsFilePath"
    $settingFileContent.$settingName = $newValue
    $settingFileContent | Set-JsonContentLF -path $settingsFilePath
}

<#
    .Synopsis
        Changes the version number of a project.
    .Description
        Changes the version number of a project. The version number is changed in the project settings file (value for 'repoVersion') and in the app.json files of all apps in the project.
    .Parameter baseFolder
        Base folder of the repository.
    .Parameter project
        Name of the project (relative to the base folder).
    .Parameter newVersion
        New version number.
    .Parameter incremental
        If set, the new version number will be added to the old version number.
#>
function Set-ProjectVersion($projectPath, $projectSettings, $newVersion, [switch] $incremental) {
    $projectSettingsPath = Join-Path $projectPath $ALGoSettingsFile
    Set-SettingInFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $newVersion -incremental:$incremental | Out-Null

    # Check if the project uses repoVersion versioning strategy
    $useRepoVersion = (($projectSettings.PSObject.Properties.Name -eq "versioningStrategy") -and (($projectSettings.versioningStrategy -band 16) -eq 16))

    $folders = @($projectSettings.appFolders) + @($projectSettings.testFolders)
    $folders | ForEach-Object {
        $folder = $_
        $folder = Join-Path $projectPath $folder
        Write-Host "Modifying app.json in folder $folder"

        $appJsonFile = Join-Path $folder "app.json"
        try {
            if ($useRepoVersion) {
                $appVersion = $projectSettings.repoVersion
                $incremental = $false # Don't increment the version number if the project uses repoVersion versioning strategy
            }

            Set-SettingInFile -settingsFilePath $appJsonFile -settingName 'version' -newValue $appVersion -incremental:$incremental | Out-Null
        }
        catch {
            throw "Application manifest file($appJsonFile) is malformed: $_"
        }
    }
}

Export-ModuleMember -Function Set-SettingInFile, Set-ProjectVersion