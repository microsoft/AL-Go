<#
    .Synopsis
        Changes a version setting value in a settings file. The setting value must be a version number in one of the following formats: 1.0 or 1.2.3.4
    .Parameter settingsFilePath
        Path to the settings file. The settings file must be a JSON file.
    .Parameter settingName
        Name of the setting to change.
    .Parameter newValue
        New value of the setting. If the value starts with a +, the new value will be added to the old value. Else the new value will replace the old value.
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
    $settingFileContent | Set-JsonContentLF -Path $settingsFilePath

    return @{
        name = $settingFileContent.name
        version = $settingFileContent.version
        publisher = $settingFileContent.publisher
    }
}

<#
    .Synopsis
        Changes the version number of a project.
    .Description
        Changes the version number of a project.
        The version number is changed in the project settings file (value for 'repoVersion') and in the app.json files of all apps in the project, as well as all references to the apps in the dependencies of the app.json files.
    .Parameter baseFolder
        Base folder of the repository.
    .Parameter project
        Name of the project (relative to the base folder).
    .Parameter newVersion
        New version number. If the version number starts with a +, the new version number will be added to the old version number. Else the new version number will replace the old version number.
#>
function Set-ProjectVersion($projectPath, $projectSettings, $newVersion, $ALGOsettingsFile) {
    # Set repoVersion in project settings (if it exists)
    $projectSettingsPath = Join-Path $projectPath $ALGoSettingsFile
    Set-VersionSettingInFile -settingsFilePath $projectSettingsPath -settingName 'repoVersion' -newValue $newVersion | Out-Null

    # Check if the project uses repoVersion versioning strategy
    $useRepoVersion = (($projectSettings.PSObject.Properties.Name -eq "versioningStrategy") -and (($projectSettings.versioningStrategy -band 16) -eq 16))
    if ($useRepoVersion) {
        $newVersion = $projectSettings.repoVersion
    }

    $allAppFolders = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders)
    # Set version in app.json files
    $appInfos = $allAppFolders | ForEach-Object {
        $folder = Join-Path $projectPath $_
        $appJsonFile = Join-Path $folder "app.json"

        $appInfo = Set-VersionSettingInFile -settingsFilePath $appJsonFile -settingName 'version' -newValue $newVersion
        return $appInfo
    }

    # Set the version in the dependencies in app.json files
    $allAppFolders | ForEach-Object {
        $folder = Join-Path $projectPath $_
        $appJsonFile = Join-Path $folder "app.json"

        $appJsonContent = Get-Content $appJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $dependencies = $appJsonContent.dependencies
        if ($null -ne $dependencies) {
            $dependencies | ForEach-Object {
                $dependency = $_
                # Find the version of the dependency in the appInfos. If it's found, it means the dependency is part of the project and the version should be set.
                $dependencyAppInfo = $appInfos | Where-Object { $_.name -eq $dependency.name -and $_.publisher -eq $dependency.publisher }
                if ($null -ne $dependencyAppInfo) {
                    $dependency.version = $dependencyAppInfo.version
                }
            }
            $appJsonContent.dependencies = $dependencies
            $appJsonContent | Set-JsonContentLF -Path $appJsonFile
        }
    }
}

Export-ModuleMember -Function Set-VersionSettingInFile, Set-ProjectVersion