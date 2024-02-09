<#
    .Synopsis
        Changes a version setting value in a settings file.
    .Parameter settingsFilePath
        Path to a JSON file containing the settings.
    .Parameter settingName
        Name of the setting to change. The setting must be a version number.
    .Parameter newValue
        New value of the setting. Allowed values are: +1 (increment major version number), +0.1 (increment minor version number), or a version number in the format Major.Minor (e.g. 1.0 or 1.2
#>
function Set-VersionInSettingsFile {
    param(
        [Parameter(Mandatory = $true)]
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
        $settingFileContent = Get-Content $settingsFilePath -Encoding UTF8 -Raw | ConvertFrom-Json
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
    .Parameter newValue
        New version number. If the version number starts with a +, the new version number will be added to the old version number. Else the new version number will replace the old version number.
#>
function Set-VersionInAppManifests($projectPath, $projectSettings, $newValue) {

    # Check if the project uses repoVersion versioning strategy
    $useRepoVersion = (($projectSettings.PSObject.Properties.Name -eq "versioningStrategy") -and (($projectSettings.versioningStrategy -band 16) -eq 16))
    if ($useRepoVersion) {
        $newValue = $projectSettings.repoVersion
    }

    $allAppFolders = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders)
    # Set version in app.json files
    $allAppFolders | ForEach-Object {
        $appFolder = Join-Path $projectPath $_
        $appJson = Join-Path $appFolder "app.json"

        Set-VersionInSettingsFile -settingsFilePath $appJson -settingName 'version' -newValue $newValue
    }
}

<#
    .Synopsis
        Changes the version number of dependencies in app.json files.
    .Description
        Changes the version number of dependencies in app.json files.
        The version number of the dependencies is changed to the version number of the app that the dependency refers to. If the app is not found, the version number of the dependency is not changed.
    .Parameter appFolders
        Array of paths to the app folders. Each app folder must contain an app.json file. The apps are used to get the version number of the dependencies.
#>
function Set-DependenciesVersionInAppManifests {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $appFolders
    )

    # Get all apps info: app ID and app version
    $appsInfos = @($appFolders | ForEach-Object {
        $appJson = Join-Path $_ "app.json"
        $app = Get-Content -Path $appJson -Encoding UTF8 -Raw | ConvertFrom-Json
        return [PSCustomObject]@{
            Id = $app.id
            Version = $app.version
        }
    })

    # Update dependencies in app.json files
    $appFolders | ForEach-Object {
        $appJsonPath = Join-Path $_ "app.json"

        $appJson = Get-Content -Path $appJsonPath -Encoding UTF8 -Raw | ConvertFrom-Json

        $dependencies = $appJson.dependencies

        $dependencies | ForEach-Object {
            $dependency = $_
            $appInfo = $appsInfos | Where-Object { $_.Id -eq $dependency.id }
            if ($appInfo) {
                Write-Host "Updating dependency app $($dependency.id) in $appJsonPath from $($dependency.version) to $($appInfo.Version)"
                $dependency.version = $appInfo.Version
            }
        }

        $appJson | Set-JsonContentLF -Path $appJsonPath
    }
}

Export-ModuleMember -Function Set-VersionInSettingsFile, Set-VersionInAppManifests, Set-DependenciesVersionInAppManifests