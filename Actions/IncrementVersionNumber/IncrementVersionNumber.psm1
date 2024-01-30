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
    if (-not (Test-Path $settingFilePath)) {
        throw "Settings file ($settingFilePath) not found."
    }

    Write-Host "Reading settings from $settingFilePath"
    $settingFileContent = Get-Content $settingFilePath -Encoding UTF8 | ConvertFrom-Json

    if (-not ($settingFileContent.PSObject.Properties.Name -eq $settingName)) {
        Write-Host "Setting $settingName not found in $settingFilePath"
        return
    }

    $oldValue = $settingFileContent.$settingName

    if ($incremental) {
        $oldValue = [System.Version]$oldValue
        $newValue = [System.Version]$newValue

        $newValue = "$($newValue.Major + $oldValue.Major).$($newValue.Minor + $oldValue.Minor)"
    }

    Write-Host "Changing $settingName from $oldValue to $newValue in $settingFilePath"
    $settingFileContent.$settingName = $newValue
    $settingFileContent | Set-JsonContentLF -path $settingFilePath
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
function Set-ProjectVersion($baseFolder, $project, $newVersion, [switch] $incremental) {
    $projectSettingsPath = Join-Path $project $ALGoSettingsFile
    Set-SettingInFile -settingsFilePath (Join-Path $baseFolder $projectSettingsPath) -settingName 'repoVersion' -newValue $newVersion -incremental:$incremental | Out-Null

    # Resolve project folders to get all app folders that contain an app.json file
    $projectSettings = ReadSettings -baseFolder $baseFolder -project $project
    ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $projectSettings)

    # Check if the project uses repoVersion versioning strategy
    $useRepoVersion = (($projectSettings.PSObject.Properties.Name -eq "versioningStrategy") -and (($projectSettings.versioningStrategy -band 16) -eq 16))

    $folders = @($projectSettings.appFolders) + @($projectSettings.testFolders)

    Write-Host "Folders: $folders"

    $folders | ForEach-Object {
        $folder = $_
        $folder = Join-Path $project $folder
        $folder = Join-Path $baseFolder $folder
        Write-Host "Modifying app.json in folder $folder"

        $appJsonFile = Join-Path $folder "app.json"
        try {
            $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
            if ($useRepoVersion) {
                $appVersion = $projectSettings.repoVersion
            }
            elseif ($incremental) {
                $oldVersion = [System.Version] $appJson.Version
                $newVersion = [System.Version] $newVersion

                $appVersion = [System.Version]"$($newVersion.Major+$oldVersion.Major).$($newVersion.Minor+$oldVersion.Minor).0.0"
            }
            else {
                $appVersion = $newVersion
            }
            $appJson.Version = "$appVersion"
            $appJson | Set-JsonContentLF -path $appJsonFile
        }
        catch {
            throw $_ # "Application manifest file($appJsonFile) is malformed."
        }
    }
}

Export-ModuleMember -Function Set-SettingInFile, Set-ProjectVersion