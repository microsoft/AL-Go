. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
        Get the head ref from a PR
    .PARAMETER repository
        Repository to search in
    .PARAMETER prId
        The PR Id
    .PARAMETER token
        The GitHub token running the action
#>
function GetHeadRefFromPRId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $prId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $pullsURI = "https://api.github.com/repos/$repository/pulls/$prId"
    Write-Host "- $pullsURI"
    $pr = (InvokeWebRequest -Headers $headers -Uri $pullsURI).Content | ConvertFrom-Json

    return $pr.head.ref
}

<#
    .SYNOPSIS
        Get apps and dependencies from artifacts
    .PARAMETER token
        The GitHub token running the action
    .PARAMETER artifactsFolder
        The folder where artifacts are stored
    .PARAMETER deploymentSettings
        Deployment settings for the action
    .PARAMETER artifactsVersion
        Version of the artifacts to use (optional) - This is only used for PR deployments and should take the form of PR_X
#>
function GetAppsAndDependenciesFromArtifacts {
    Param(
        [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $artifactsFolder,
        [Parameter(Mandatory = $true)]
        [hashtable] $deploymentSettings,
        [Parameter(Mandatory = $false)]
        [string] $artifactsVersion = ''
    )
    OutputDebugFunctionCall
    OutputGroupStart -Message "GetAppsAndDependenciesFromArtifacts"
    $apps = @()
    $dependencies = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
    $TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"

    # Determine buildMode prefix for artifact names based on settings
    $buildModePrefix = 'default'
    if ($deploymentSettings.Keys -contains "buildMode") {
        $buildModePrefix = $deploymentSettings.buildMode
    }

    # If buildMode is not defined or is 'default', set it to empty string
    if ($null -eq $buildModePrefix -or $buildModePrefix -eq 'default') {
        $buildModePrefix = ''
    }

    if (Test-Path $artifactsFolder -PathType Container) {
        $deploymentSettings.Projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_').Replace('/','_')
            $artifactVersionFilter = '*.*.*.*'
            $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
            # Artifacts from PRs are named differently - project-ref-Apps-PRx-date
            if ($artifactsVersion -like "PR_*") {
                $prId = $artifactsVersion.SubString(3)
                $intId = 0
                if (!([Int]::TryParse($prId, [ref] $intId))) {
                    OutputGroupEnd
                    throw "Invalid PR id: $prId"
                }
                $artifactVersionFilter = "PR$prId-*"
                $refname = (GetHeadRefFromPRId -repository $ENV:GITHUB_REPOSITORY -prId $prId -token $token).Replace('/','_')
            }
            Write-Host "project '$project'"

            $allApps = @()
            OutputDebug -message "projectApps filter: $project-$refname-$($buildModePrefix)Apps-$artifactVersionFilter"
            $projectApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildModePrefix)Apps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            $projectTestApps = @()
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment) {
                Write-Host "Including test apps for deployment"
                OutputDebug -message "projectTestApps filter: $project-$refname-$($buildModePrefix)TestApps-$artifactVersionFilter"
                $projectTestApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildModePrefix)TestApps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            }
            if ($deploymentSettings.excludeAppIds) {
                Write-Host "Excluding apps with ids $($deploymentSettings.excludeAppIds) from deployment"
            }
            if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
                OutputDebug -message "projectDependencies filter: $project-$refname-$($buildModePrefix)Dependencies-$artifactVersionFilter/*.app"
                $dependencies += @((Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($buildModePrefix)Dependencies-$artifactVersionFilter/*.app")) | ForEach-Object { $_.FullName } )
            }
            if (!($projectApps)) {
                if ($project -ne '*') {
                    OutputGroupEnd
                    throw "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildModePrefix)Apps-<version>."
                }
            }
            else {
                $allApps += $projectApps
            }
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment -and !($projectTestApps)) {
                if ($project -ne '*') {
                    OutputWarning -message "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildModePrefix)TestApps-<version>."
                }
            }
            else {
                $allApps += $projectTestApps
            }
            # Go through all .app files and exclude any with ids in the excludeAppIds list
            # Also exclude apps with direct dependencies on Tests-TestLibraries
            if ($allApps) {
                foreach($folder in $allApps) {
                    foreach($app in (Get-ChildItem -Path $folder -Filter "*.app")) {
                        Write-Host "Processing app: $($app.Name)"
                        $appJson = Get-AppJsonFromAppFile -appFile $app.FullName
                        if ($appJson.id -notin $deploymentSettings.excludeAppIds) {
                            # If app should be included, verify that it does not depend on Tests-TestLibraries
                            $unknownDependenciesForApp = @()
                            Sort-AppFilesByDependencies -appFiles @($app.FullName) -unknownDependencies ([ref]$unknownDependenciesForApp) -WarningAction SilentlyContinue | Out-Null
                            $unknownDependenciesForApp | ForEach-Object {
                                if ($_.Split(':')[0] -eq $TestsTestLibrariesAppId) {
                                    OutputWarning -message "Test-TestLibraries can't be installed - skipping app $($app.Name)"
                                    continue
                                }
                            }

                            $apps += $app.FullName
                            Write-Host "App $($app.Name) with id $($appJson.id) included in deployment"
                        }
                        else {
                            Write-Host "App $($app.Name) with id $($appJson.id) excluded from deployment"
                        }
                    }
                }
            }
        }
    }
    else {
        OutputGroupEnd
        throw "Artifact $artifactsFolder was not found. Make sure that the artifact files exist and files are not corrupted."
    }
    OutputGroupEnd
    return $apps, $dependencies
}

<#
    .SYNOPSIS
        Check if an app needs to be installed or upgraded based on the app.json and the installed version.
    .PARAMETER appJson
        The app.json object of the app to check.
    .PARAMETER installedApp
        The installed app object to compare against.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function CheckIfAppNeedsInstallOrUpgrade {
    Param(
        [PSCustomObject] $appJson,
        $installedApp,
        [string] $installMode
    )
    OutputDebugFunctionCall

    $needsInstall = $false
    $needsUpgrade = $false
    if ($installedApp) {
        $dependencyVersion = [version]::new($appJson.Version)
        $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)
        if ($dependencyVersion -gt $installedVersion) {
            $msg = "Dependency app $($appJson.name) is already installed in version $installedVersion, which is lower than $dependencyVersion."
            if ($installMode -eq 'upgrade') {
                Write-Host "$msg Needs upgrade."
                $needsUpgrade = $true
            }
            else {
                OutputWarning -message "$msg Set DependencyInstallMode to 'upgrade' or 'forceUpgrade' to upgrade dependencies."
            }
        }
        elseif ($dependencyVersion -lt $installedVersion) {
            Write-Host "Dependency app $($appJson.name) is already installed in version $installedVersion, which is higher than $dependencyVersion, used in app.json."
        }
        else {
            Write-Host "Dependency app $($appJson.name) is already installed in version $installedVersion."
        }
    }
    else {
        Write-Host "Dependency app $($appJson.name) is not installed."
        $needsInstall = ($installMode -ne 'ignore')
    }
    return $needsInstall, $needsUpgrade
}

# Check if the apps are already installed and emit a warning if the installed version is higher than the version in the app file
<#
    .SYNOPSIS
        Check installed apps against the provided app files and emit warnings if the installed version is higher than the version in the app file.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to check installed apps in.
    .PARAMETER appFiles
        The list of app files to check against installed apps.
#>
function CheckInstalledApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $appFiles
    )
    OutputDebugFunctionCall

    $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
    foreach($appFile in $appFiles) {
        # Get AppJson (works for full .app files, symbol files and also runtime packages)
        $appJson = Get-AppJsonFromAppFile -appFile $appFile
        $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }

        # Check if the version of the installed app is lower than the version in the app file
        if ($installedApp) {
            $currentVersion = [version]::new($appJson.Version)
            $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)

            if ($currentVersion -lt $installedVersion) {
                OutputWarning -message "App $($appJson.name) is already installed in version $installedVersion, which is higher than $currentVersion, used in app.json. In order to install version $currentVersion, the higher version must be uninstalled first."
            }
        }
    }
}

<#
    .SYNOPSIS
        Install or upgrade apps in Business Central.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to install or upgrade apps in.
    .PARAMETER apps
        The list of app files to install or upgrade.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function InstallOrUpgradeApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )
    OutputDebugFunctionCall

    $schemaSyncMode = 'Add'
    if ($installMode -eq 'ForceUpgrade') {
        $schemaSyncMode = 'Force'
        $installMode = 'upgrade'
    }

    $tempPath = NewTemporaryFolder
    try {
        Copy-AppFilesToFolder -appFiles $apps -folder $tempPath | Out-Null
        $apps = @(Get-ChildItem -Path $tempPath -Filter *.app | ForEach-Object { $_.FullName })
        $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
        $PTEsToInstall = @()
        # Run through all apps and install or upgrade AppSource apps first (and collect PTEs)
        foreach($app in $apps) {
            # Get AppJson (works for full .app files, symbol files and also runtime packages)
            $appJson = Get-AppJsonFromAppFile -appFile $app
            $isPTE = ($appjson.idRanges.from -lt 100000 -and $appjson.idRanges.from -ge 50000)
            $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
            $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode
            if ($needsUpgrade) {
                if (-not $isPTE -and $installedApp.publishedAs.Trim() -eq 'Dev') {
                    OutputWarning -message "Dependency AppSource App $($appJson.name) is published in Dev scope. Cannot upgrade."
                    $needsUpgrade = $false
                }
            }
            if ($needsUpgrade -or $needsInstall) {
                if ($isPTE) {
                    $PTEsToInstall += $app
                }
                else {
                    Install-BcAppFromAppSource -bcAuthContext $bcAuthContext -environment $environment -appId $appJson.id -acceptIsvEula -installOrUpdateNeededDependencies -allowInstallationOnProduction
                    # Update installed apps list as dependencies may have changed / been installed
                    $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
                }
            }
        }
        if ($PTEsToInstall) {
            # Install or upgrade PTEs
            Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $PTEsToInstall -SchemaSyncMode $schemaSyncMode
        }
    }
    finally {
        Remove-Item -Path $tempPath -Force -Recurse
    }
}

<#
    .SYNOPSIS
        Install unknown dependencies in Business Central.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to install unknown dependencies in.
    .PARAMETER apps
        The list of unknown dependency apps to install.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function InstallUnknownDependencies {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )
    OutputDebugFunctionCall

    Write-Host "Installing unknown dependencies: $($apps -join ', ')"
    try {
        $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
        # Run through all apps and install or upgrade AppSource apps first (and collect PTEs)
        foreach($app in $apps) {
            # The output of Sort-AppFilesByDependencies is in the format of "AppId:AppName"
            $appId, $appName = $app.Split(':')
            $appVersion = ""
            if ($appName -like 'Microsoft__EXCLUDE_*') {
                Write-Host "App $appName is ignored as it is marked as EXCLUDE"
                continue
            }
            elseif ($appName -match "_(\d+\.\d+\.\d+\.\d+)\.app$") {
                $appVersion = $matches.1
            } else {
                Write-Host "Version not found or incorrect format for unknown dependency $app"
                continue
            }
            # Create a fake appJson with the properties used in CheckIfAppNeedsInstallOrUpgrade
            $appJson = @{
                "name" = $appName
                "id" = $appId
                "Version" = $appVersion
            }

            $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
            $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode
            OutputDebug -message "Checking app $($appJson.name): needsInstall=$needsInstall, needsUpgrade=$needsUpgrade"
            if ($needsUpgrade) {
                if ($installedApp.publishedAs.Trim() -eq 'Dev') {
                    OutputWarning -message "Dependency AppSource App $($appJson.name) is published in Dev scope. Cannot upgrade."
                    $needsUpgrade = $false
                }
            }
            if ($needsUpgrade -or $needsInstall) {
                Install-BcAppFromAppSource -bcAuthContext $bcAuthContext -environment $environment -appId $appJson.id -acceptIsvEula -installOrUpdateNeededDependencies -allowInstallationOnProduction
                # Update installed apps list as dependencies may have changed / been installed
                $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
            }
        }
    }
    finally {
        Write-Host "Unknown dependencies installed or upgraded"
    }
}
