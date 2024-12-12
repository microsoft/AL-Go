<#
    .Synopsis
        Changes a version setting value in a settings file.
    .Description
        Changes a version setting value in a settings file.
        If the setting does not exist in the settings file, the function does nothing, unless the Force parameter is specified.
    .Parameter settingsFilePath
        Path to a JSON file containing the settings.
    .Parameter settingName
        Name of the setting to change. The setting must be a version number.
    .Parameter newValue
        New value of the setting. Allowed values are: +1 (increment major version number), +0.1 (increment minor version number), or a version number in the format Major.Minor (e.g. 1.0 or 1.2
    .Parameter Force
        If specified, the function will create the setting if it does not exist in the settings file.
#>
function Set-VersionInSettingsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $settingsFilePath,
        [Parameter(Mandatory = $true)]
        [string] $settingName,
        [Parameter(Mandatory = $true)]
        [string] $newValue,
        [switch] $Force
    )

    #region Validate parameters
    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    try {
        $settingsJson = Get-Content $settingsFilePath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    catch {
        throw "Settings file ($settingsFilePath) is malformed: $_"
    }

    $settingExists = [bool] ($settingsJson.PSObject.Properties.Name -eq $settingName)
    if ((-not $settingExists) -and (-not $Force)) {
        Write-Host "Setting $settingName not found in $settingsFilePath"
        return
    }

    # Add the setting if it does not exist
    if (-not $settingExists) {
        $settingsJson | Add-Member -MemberType NoteProperty -Name $settingName -Value $null
    }

    $oldVersion = [System.Version] $settingsJson.$settingName
    # Validate new version value
    if ($newValue.StartsWith('+')) {
        # Handle incremental version number

        # Defensive check. Should never happen.
        $allowedIncrementalVersionNumbers = @('+1', '+0.1', '+0.0.1')
        if (-not $allowedIncrementalVersionNumbers.Contains($newValue)) {
            throw "Unexpected error - incremental version number $newValue is not allowed. Allowed incremental version numbers are: $($allowedIncrementalVersionNumbers -join ', ')"
        }
        # Defensive check. Should never happen.
        if($null -eq $oldVersion) {
            throw "Unexpected error - the setting $settingName does not exist in the settings file. It must exist to be able to increment the version number."
        }
    }
    else {
        # Handle absolute version number

        # Defensive check. Should never happen.
        $versionNumberFormat = '^\d+\.\d+(\.\d+)?$' # Major.Minor or Major.Minor.Build
        if (-not ($newValue -match $versionNumberFormat)) {
            throw "Unexpected error - version number $newValue is not in the correct format. The version number must be in the format Major.Minor[.Build] (e.g. 1.0, 1.2 or 1.3.0)"
        }
    }
    #endregion

    $versionNumbers = @() # an array to hold the version numbers: major, minor, build, revision

    switch($newValue) {
        '+1' {
            # Increment major version number
            $versionNumbers += $oldVersion.Major + 1
            $versionNumbers += 0
            # Include build number if it exists in the old version number
            if ($oldVersion.Build -ne -1) {
                $versionNumbers += 0
            }
        }
        '+0.1' {
            # Increment minor version number
            $versionNumbers += $oldVersion.Major
            $versionNumbers += $oldVersion.Minor + 1
            # Include build number if it exists in the old version number
            if ($oldVersion.Build -ne -1) {
                $versionNumbers += 0
            }
        }
        '+0.0.1' {
            # Increment minor version number
            $versionNumbers += $oldVersion.Major
            $versionNumbers += $oldVersion.Minor
            $versionNumbers += $oldVersion.Build + 1
        }
        default {
            # Absolute version number
            $versionNumbers += $newValue.Split('.')
            if ($versionNumbers.Count -eq 2 -and $oldVersion.Build -ne -1) {
                $versionNumbers += 0
            }
        }
    }

    # Include revision numbers if it exist in the old version number
    if ($oldVersion -and ($oldVersion.Revision -ne -1)) {
        $versionNumbers += 0 # Always set the revision number to 0
    }

    # Construct the new version number. Cast to System.Version to validate if the version number is valid.
    $newVersion = [System.Version] "$($versionNumbers -join '.')"

    if($newVersion -lt $oldVersion) {
        throw "The new version number ($newVersion) is less than the old version number ($oldVersion). The version number must be incremented."
    }

    if($newVersion -eq $oldVersion) {
        Write-Host "The setting $settingName is already set to $newVersion in $settingsFilePath"
        return
    }

    if($null -eq $oldVersion) {
        Write-Host "Setting setting $settingName to $newVersion in $settingsFilePath"
    }
    else {
        Write-Host "Changing $settingName from $oldVersion to $newVersion in $settingsFilePath"
    }

    $settingsJson.$settingName = $newVersion.ToString()
    $settingsJson | Set-JsonContentLF -Path $settingsFilePath
}

<#
    .Synopsis
        Checks if a setting exists in a settings file.
    .Description
        Checks if a setting exists in a settings file.
    .Parameter settingsFilePath
        Path to a JSON file containing the settings.
    .Parameter settingName
        Name of the setting to check.
#>
function Test-SettingExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $settingsFilePath,
        [Parameter(Mandatory = $true)]
        [string] $settingName
    )

    if (-not (Test-Path $settingsFilePath)) {
        throw "Settings file ($settingsFilePath) not found."
    }

    Write-Host "Reading settings from $settingsFilePath"
    try {
        $settingsJson = Get-Content $settingsFilePath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    catch {
        throw "Settings file ($settingsFilePath) is malformed: $_"
    }

    $settingExists = [bool] ($settingsJson.PSObject.Properties.Name -eq $settingName)
    return $settingExists
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

    # Get all distinct app folders
    $distinctAppFolders = $appFolders | Sort-Object -Unique

    # Get all apps info: app ID and app version
    $appsInfos = @($distinctAppFolders | ForEach-Object {
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
            $appInfo = $appsInfos | Where-Object { $_.Id -eq $dependency.id } | Select-Object -First 1
            if ($appInfo) {
                Write-Host "Updating dependency app $($dependency.id) in $appJsonPath from $($dependency.version) to $($appInfo.Version)"
                $dependency.version = $appInfo.Version
            }
        }

        $appJson | Set-JsonContentLF -Path $appJsonPath
    }
}

<#
    .Synopsis
        Sets the version number of a Power Platform solution.
    .Description
        Sets the version number of a Power Platform solution.
        The version number is changed in the Solution.xml file of the Power Platform solution.
    .Parameter powerPlatformSolutionPath
        Path to the Power Platform solution.
    .Parameter newValue
        New version number. If the version number starts with a +, the new version number will be added to the old version number. Else the new version number will replace the old version number.
        Allowed values are: +1 (increment major version number), +0.1 (increment minor version number), or a full version number (e.g. major.minor.build.revision).
#>
function Set-PowerPlatformSolutionVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $powerPlatformSolutionPath,
        [Parameter(Mandatory = $true)]
        [string] $newValue
    )

    Write-Host "Updating Power Platform solution version"
    $files = Get-ChildItem -Path $powerPlatformSolutionPath -filter 'Solution.xml' -Recurse -File | Where-Object { $_.Directory.Name -eq "other" }
    if (-not $files) {
        Write-Host "Power Platform solution file not found"
    }
    else {
        foreach ($file in $files) {
            $xml = [xml](Get-Content -Encoding UTF8 -Path $file.FullName)
            if ($newValue.StartsWith('+')) {
                # Increment version
                $versionNumbers = $xml.SelectNodes("//Version")[0].InnerText.Split(".")
                switch($newValue) {
                    '+1' {
                        # Increment major version number
                        $versionNumbers[0] = "$(([int]$versionNumbers[0])+1)"
                    }
                    '+0.1' {
                        # Increment minor version number
                        $versionNumbers[1] = "$(([int]$versionNumbers[1])+1)"
                    }
                    default {
                        throw "Unexpected version number $newValue"
                    }
                }
                $newVersion = [string]::Join(".", $versionNumbers)
            }
            else {
                $newVersion = $newValue
            }

            Write-Host "Updating $($file.FullName) with new version $newVersion"
            $xml.SelectNodes("//Version")[0].InnerText = $newVersion
            $xml.Save($file.FullName)
        }
    }
}

Export-ModuleMember -Function Set-VersionInSettingsFile, Set-VersionInAppManifests, Set-DependenciesVersionInAppManifests, Set-PowerPlatformSolutionVersion, Test-SettingExists
