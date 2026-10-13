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
        Unpublish old, uninstalled versions of the deployed apps from a Business Central environment.
    .DESCRIPTION
        After a new version of a Per Tenant Extension is installed, previous versions remain published (but uninstalled)
        and clutter Extension Management. This function unpublishes those old versions using the automation API v2.0
        Microsoft.NAV.unpublish action. Only versions that are not installed AND older than a currently installed version
        of the same app (matched by app id) are unpublished. This is only supported for PTE deployments (automation API).
        The function is non-fatal: any failure is reported as a warning and never fails the deployment.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to unpublish old app versions from.
    .PARAMETER appFiles
        The list of deployed app files. Only the app id is read from these files to identify which apps to clean up;
        for each such app, published versions are compared against the version currently installed in the environment
        (not the deployed artifact version), and uninstalled versions older than the installed version are unpublished.
#>
function UnpublishOldAppVersions {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $appFiles
    )
    OutputDebugFunctionCall

    try {
        # Deployed app ids read from the .app files
        $deployedApps = @($appFiles | ForEach-Object {
            $appJson = Get-AppJsonFromAppFile -appFile $_
            [PSCustomObject]@{ Id = $appJson.id }
        })
        if ($deployedApps.Count -eq 0) {
            return
        }

        $authContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        $headers = @{ "Authorization" = "Bearer $($authContext.AccessToken)" }
        $automationApiUrl = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/v2.0/$environment/api/microsoft/automation/v2.0"

        $companies = (Invoke-RestMethod -Method Get -Uri "$automationApiUrl/companies" -Headers $headers -UseBasicParsing).value
        if (-not $companies) {
            OutputWarning -message "Could not find any company in environment $environment - skipping unpublish of old app versions."
            return
        }
        $companyId = $companies[0].id
        $companyUrl = "$automationApiUrl/companies($companyId)"
        $extensions = @((Invoke-RestMethod -Method Get -Uri "$companyUrl/extensions" -Headers $headers -UseBasicParsing).value)

        $application = $extensions | Where-Object { $_.displayName -eq 'Application' -and $_.isInstalled } | Select-Object -First 1
        if (-not $application) {
            OutputWarning -message "Could not determine the Business Central version in environment $environment - skipping unpublish of old app versions."
            return
        }
        $applicationVersion = [version]::new($application.versionMajor, $application.versionMinor, $application.versionBuild, $application.versionRevision)
        if ($applicationVersion -lt [version]'25.4.0.0') {
            OutputWarning -message "Unpublishing old app versions requires Business Central 25.4 or later; environment $environment is running $applicationVersion."
            return
        }

        foreach($deployed in $deployedApps) {
            # All published versions of this app (installed and uninstalled)
            $matching = @($extensions | Where-Object { $_.id -eq $deployed.Id })
            if ($matching.Count -le 1) {
                # Only one (or no) published version - nothing to clean up
                continue
            }
            # Use the currently installed version as the cleanup threshold. The environment may have a newer
            # version installed than the deployed artifact, which Publish-PerTenantExtensionApps treats as success.
            $installedVersions = @($matching | Where-Object { $_.isInstalled } | ForEach-Object { [version]::new($_.versionMajor, $_.versionMinor, $_.versionBuild, $_.versionRevision) })
            if ($installedVersions.Count -eq 0) {
                # No installed version - nothing to clean up against
                continue
            }
            $installedVersion = @($installedVersions | Sort-Object -Descending)[0]
            foreach($old in $matching) {
                $oldVersion = [version]::new($old.versionMajor, $old.versionMinor, $old.versionBuild, $old.versionRevision)
                if ($old.isInstalled -or $oldVersion -ge $installedVersion) {
                    # Keep anything still installed and any version at or above the installed version
                    continue
                }
                Write-Host "Unpublishing $($old.displayName) v$oldVersion"
                try {
                    Invoke-RestMethod -Method Post -Headers $headers -Body '{}' -ContentType 'application/json' -UseBasicParsing `
                        -Uri "$companyUrl/extensions($($old.packageId))/Microsoft.NAV.unpublish" | Out-Null
                }
                catch {
                    OutputWarning -message "Failed to unpublish $($old.displayName) v$($oldVersion): $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        OutputWarning -message "Unpublishing old app versions in environment $environment failed: $($_.Exception.Message)"
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
