<#
    .Synopsis
        Changes a version setting value in a settings file.
    .Parameter settingsFilePath
        Path to the settings file. The settings file must be a JSON file.
    .Parameter settingName
        Name of the setting to change. The setting must be a version number.
    .Parameter newValue
        New value of the setting. Allowed values are: +1 (increment major version number), +0.1 (increment minor version number), or a version number in the format Major.Minor (e.g. 1.0 or 1.2
#>
function Set-VersionSettingInFile {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $settingsFilePath,
        [Parameter(Mandatory = $true)]
        [string] $settingName,
        [Parameter(Mandatory = $true)]
        [string] $newValue
    )

    #region Validate parameters
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

    # Validate new version value
    if ($newValue.StartsWith('+')) {
        # Handle incremental version number

        $allowedIncrementalVersionNumbers = @('+1', '+0.1')
        if (-not $allowedIncrementalVersionNumbers.Contains($newValue)) {
            throw "Incremental version number $newValue is not allowed. Allowed incremental version numbers are: $($allowedIncrementalVersionNumbers -join ', ')"
        }
    }
    else {
        # Handle absolute version number

        $versionNumberFormat = '^\d+\.\d+$' # Major.Minor
        if (-not ($newValue -match $versionNumberFormat)) {
            throw "Version number $newValue is not in the correct format. The version number must be in the format Major.Minor (e.g. 1.0 or 1.2)"
        }
    }
    #endregion

    $oldValue = [System.Version] $settingFileContent.$settingName
    $versions = @() # an array to hold the version numbers: major, minor, build, revision

    switch($newValue) {
        '+1' {
            # Increment major version number
            $versions += $oldValue.Major + 1
            $versions += 0
        }
        '+0.1' {
            # Increment minor version number
            $versions += $oldValue.Major
            $versions += $oldValue.Minor + 1

        }
        default {
            # Absolute version number
            $versions += $newValue.Split('.')
        }
    }

    # Include build and revision numbers if they exist in the old version number
    if ($oldValue.Build -ne -1) {
        $versions += $oldValue.Build
        if ($oldValue.Revision -ne -1) {
            $versions += $oldValue.Revision
        }
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