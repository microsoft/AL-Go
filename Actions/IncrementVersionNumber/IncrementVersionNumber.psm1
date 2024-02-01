<#
    .Synopsis
        Changes a version setting value in a settings file. The setting value must be a version number in one of the following formats: 1.0 or 1.2.3.4
    .Parameter settingsFilePath
        Path to the settings file. The settings file must be a JSON file.
    .Parameter settingName
        Name of the setting to change.
    .Parameter newValue
        New value of the setting. If the value starts with a +, the new value will be added to the old value. Else the new value will replace the old value.
    .Parameter incremental
        If set, the new value will be added to the old value. The old value must be a version number. The new value must be a version number.
#>
function Set-VersionSettingInFile($settingsFilePath, $settingName, $newValue) {
    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    try {
        $settingFileContent = Get-Content $settingsFilePath -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Settings file ($settingsFilePath) is malformed: $_"
    }

    if (-not ($settingFileContent.PSObject.Properties.Name -eq $settingName)) {
        Write-Host "Setting $settingName not found in $settingsFilePath"
        return
    }

    # Check if the new value is incremental.
    $incremental = "$newValue".StartsWith('+')
    if ($incremental) {
        $newValue = $newValue.TrimStart('+')
    }

    $oldValue = [System.Version] $settingFileContent.$settingName
    $newValue = [System.Version] $newValue # Convert to System.Version to make sure the system properties (Build, Revision) are set

    # If Build or Revision is -1 (not set), use the old value
    $newBuildValue = $newValue.Build
    if($newBuildValue -eq -1) {
        $newBuildValue = $oldValue.Build
    }

    $newRevisionValue = $newValue.Revision
    if($newRevisionValue -eq -1) {
        $newRevisionValue = $oldValue.Revision
    }

    $newMajorValue = $newValue.Major
    if($incremental) {
        $newMajorValue = $oldValue.Major + $newValue.Major
    }

    $newMinorValue = $newValue.Minor
    if($incremental) {
        $newMinorValue = $oldValue.Minor + $newValue.Minor
    }

    # Convert to array to make sure the version properties (Build, Revision) are set
    $versions = @($newMajorValue, $newMinorValue)
    if($newBuildValue -ne -1) {
        $versions += $newBuildValue
    }

    if($newRevisionValue -ne -1) {
        $versions += $newRevisionValue
    }

    # Construct the new version number. Cast to System.Version to validate if the version number is valid.
    $newValue = [System.Version] "$($versions -join '.')"

    Write-Host "Changing $settingName from $oldValue to $newValue in $settingsFilePath"
    $settingFileContent.$settingName = $newValue.ToString()
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
        If set, the new version number will be added to the old version number. The old version number must be a version number.
#>
function Set-ProjectVersion($projectPath, $projectSettings, $newVersion) {
    # Set repoVersion in project settings (if it exists)
    $projectSettingsPath = Join-Path $projectPath $ALGoSettingsFile # $ALGoSettingsFile is defined in AL-Go-Helper.ps1
    Set-VersionSettingInFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $newVersion | Out-Null

    # Check if the project uses repoVersion versioning strategy
    $useRepoVersion = (($projectSettings.PSObject.Properties.Name -eq "versioningStrategy") -and (($projectSettings.versioningStrategy -band 16) -eq 16))
    if ($useRepoVersion) {
        $newVersion = $projectSettings.repoVersion
    }

    # Set version in app.json files
    $allAppFolders = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders)
    $allAppFolders | ForEach-Object {
        $folder = Join-Path $projectPath $_
        $appJsonFile = Join-Path $folder "app.json"

        Set-VersionSettingInFile -settingsFilePath $appJsonFile -settingName 'version' -newValue $newVersion | Out-Null
    }
}

Export-ModuleMember -Function Set-VersionSettingInFile, Set-ProjectVersion