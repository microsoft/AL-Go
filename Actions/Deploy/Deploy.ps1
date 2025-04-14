Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Path to the downloaded artifacts to deploy", Mandatory = $true)]
    [string] $artifactsFolder,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "The settings for all Deployment Environments", Mandatory = $true)]
    [string] $deploymentEnvironmentsJson,
    [Parameter(HelpMessage = "Artifacts version. Used to check if this is a deployment from a PR", Mandatory = $false)]
    [string] $artifactsVersion = ''
)

function CheckIfAppNeedsInstallOrUpgrade {
    Param(
        [PSCustomObject] $appJson,
        $installedApp,
        [string] $installMode
    )

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
                Write-Host "::WARNING::$msg Set DependencyInstallMode to 'upgrade' or 'forceUpgrade' to upgrade dependencies."
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

function InstallOrUpgradeApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )

    $schemaSyncMode = 'Add'
    if ($installMode -eq 'ForceUpgrade') {
        $schemaSyncMode = 'Force'
        $installMode = 'upgrade'
    }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempPath | Out-Null
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
                    Write-Host "::WARNING::Dependency AppSource App $($appJson.name) is published in Dev scoope. Cannot upgrade."
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

function InstallUnknownDependencies {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )

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
            if ($needsUpgrade) {
                if ($installedApp.publishedAs.Trim() -eq 'Dev') {
                    Write-Host "::WARNING::Dependency AppSource App $($appJson.name) is published in Dev scoope. Cannot upgrade."
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

Import-Module (Join-Path -Path $PSScriptRoot "Deploy.psm1")
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$deploymentEnvironments = $deploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deploymentSettings = $deploymentEnvironments."$environmentName"
$buildMode = $deploymentSettings.buildMode
if ($null -eq $buildMode -or $buildMode -eq 'default') {
    $buildMode = ''
}
$envName = $environmentName.Split(' ')[0]
$secrets = $env:Secrets | ConvertFrom-Json
$settings = $env:Settings | ConvertFrom-Json

$authContext = $null
foreach($secretName in "$($envName)-AuthContext","$($envName)_AuthContext","AuthContext") {
    if ($secrets."$secretName") {
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName"))
        break
    }
}
if (-not $authContext) {
    $msg = "No Authentication Context found for environment ($environmentName). You must create an environment secret called AUTHCONTEXT or a repository secret called $($envName)_AUTHCONTEXT in order to deploy to this environment."
    # No AuthContext secret provided, if deviceCode is present, use it - else give an error
    if ($env:deviceCode) {
        $authContext = "{""deviceCode"":""$($env:deviceCode)""}"
    }
    elseif ($type -eq 'CD' -and (-not $deploymentSettings.continuousDeployment)) {
        # Continuous Deployment is undefined in settings - we will not ignore the environment if no AuthContext is provided
        OutputNotice -message $msg
        exit
    }
    else {
        throw $msg
    }
}

$apps = @()
$dependencies = @()
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
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
                throw "Invalid PR id: $prId"
            }
            $artifactVersionFilter = "PR$prId-*"
            $refname = GetHeadRefFromPRId -repository $ENV:GITHUB_REPOSITORY -prId $prId -token $token
        }
        Write-Host "project '$project'"

        $allApps = @()
        $projectApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildMode)Apps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
        $projectTestApps = @()
        if ($deploymentSettings.includeTestAppsInSandboxEnvironment) {
            Write-Host "Including test apps for deployment"
            $projectTestApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildMode)TestApps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
        }
        if ($deploymentSettings.excludeAppIds) {
            Write-Host "Excluding apps with ids $($deploymentSettings.excludeAppIds) from deployment"
        }
        if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
            $dependencies += @((Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($buildMode)Dependencies-$artifactVersionFilter/*.app")) | ForEach-Object { $_.FullName } )
        }
        if (!($projectApps)) {
            if ($project -ne '*') {
                throw "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildMode)Apps-<version>."
            }
        }
        else {
            $allApps += $projectApps
        }
        if ($deploymentSettings.includeTestAppsInSandboxEnvironment -and !($projectTestApps)) {
            if ($project -ne '*') {
                Write-Host "::warning::There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildMode)TestApps-<version>."
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
                                Write-Host "::WARNING::Test-TestLibraries can't be installed - skipping app $($app.Name)"
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
    throw "Artifact $artifactsFolder was not found. Make sure that the artifact files exist and files are not corrupted."
}

# Calculate unknown dependencies for all apps and known dependencies
$unknownDependencies = @()
Sort-AppFilesByDependencies -appFiles @($apps + $dependencies) -unknownDependencies ([ref]$unknownDependencies) -WarningAction SilentlyContinue | Out-Null

Write-Host "Apps to deploy"
$apps | ForEach-Object {
    Write-Host "- $([System.IO.Path]::GetFileName($_))"
}

if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
    Write-Host "Dependencies to $($deploymentSettings.DependencyInstallMode)"
    if ($dependencies) {
        $dependencies | ForEach-Object {
            Write-Host "- $([System.IO.Path]::GetFileName($_))"
        }
    }
    else {
        Write-Host "- None"
    }
}

Set-Location $ENV:GITHUB_WORKSPACE

# Use Get-ChildItem to support Linux (case sensitive filenames) as well as Windows
$customScript = Get-ChildItem -Path (Join-Path $ENV:GITHUB_WORKSPACE '.github') | Where-Object { $_.Name -eq "DeployTo$($deploymentSettings.EnvironmentType).ps1" } | ForEach-Object { $_.FullName }
if ($customScript) {
    Write-Host "Executing custom deployment script $customScript"
    $parameters = @{
        "type" = $type
        "AuthContext" = $authContext
        "Apps" = $apps
        "Dependencies" = $dependencies
    } + $deploymentSettings
    . $customScript -parameters $parameters
}
else {
    try {
        $authContextParams = $authContext | ConvertFrom-Json | ConvertTo-HashTable
        $bcAuthContext = New-BcAuthContext @authContextParams
        if ($null -eq $bcAuthContext) {
            throw "Authentication failed"
        }
    } catch {
        throw "Authentication failed. $([environment]::Newline) $($_.exception.message)"
    }

    $environmentUrl = "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.EnvironmentName)"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "environmentUrl=$environmentUrl"
    Write-Host "EnvironmentUrl: $environmentUrl"
    $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$environmentUrl/deployment/url"
    if ($response.Status -eq "DoesNotExist") {
        OutputError -message "Environment with name $($deploymentSettings.EnvironmentName) does not exist in the current authorization context."
        exit
    }
    if ($response.Status -ne "Ready") {
        OutputError -message "Environment with name $($deploymentSettings.EnvironmentName) is not ready (Status is $($response.Status))."
        exit
    }

    try {
        $sandboxEnvironment = ($response.environmentType -eq 1)
        $scope = $deploymentSettings.Scope
        if ($null -eq $scope) {
            if ($settings.Type -eq 'AppSource App' -or ($sandboxEnvironment -and !($bcAuthContext.ClientSecret -or $bcAuthContext.ClientAssertion))) {
                # Sandbox and not S2S -> use dev endpoint (Publish-BcContainerApp)
                $scope = 'Dev'
            }
            else {
                $scope = 'PTE'
            }
        }
        elseif (@('Dev','PTE') -notcontains $scope) {
            throw "Invalid Scope $($scope). Valid values are Dev and PTE."
        }
        if (!$sandboxEnvironment -and $type -eq 'CD' -and !($deploymentSettings.continuousDeployment)) {
            # Continuous deployment is undefined in settings - we will not deploy to production environments
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment"
        }
        elseif (!$sandboxEnvironment -and $deploymentSettings.includeTestAppsInSandboxEnvironment) {
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment, as test apps can only be deployed to sandbox environments"
        }
        elseif (!$sandboxEnvironment -and $artifactsVersion -like "PR_*") {
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment, as deploying from a PR is only supported in sandbox environments"
        }
        else {
            if ($dependencies) {
                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName -Apps $dependencies -installMode $deploymentSettings.DependencyInstallMode
            }
            if ($unknownDependencies) {
                InstallUnknownDependencies -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName -Apps $unknownDependencies -installMode $deploymentSettings.DependencyInstallMode
            }
            if ($scope -eq 'Dev') {
                if (!$sandboxEnvironment) {
                    throw "Scope Dev is only valid for sandbox environments"
                }
                $parameters = @{
                    "bcAuthContext" = $bcAuthContext
                    "environment" = $deploymentSettings.EnvironmentName
                    "appFile" = $apps
                }
                if ($deploymentSettings.SyncMode) {
                    if (@('Add','ForceSync', 'Clean', 'Development') -notcontains $deploymentSettings.SyncMode) {
                        throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the development endpoint. Valid values are Add, ForceSync, Development and Clean."
                    }
                    Write-Host "Using $($deploymentSettings.SyncMode)"
                    $parameters += @{ "SyncMode" = $deploymentSettings.SyncMode }
                }
                Write-Host "Publishing apps using development endpoint"
                Publish-BcContainerApp @parameters -useDevEndpoint -checkAlreadyInstalled -excludeRuntimePackages -replacePackageId
            }
            else {
                # Use automation API for production environments (Publish-PerTenantExtensionApps)
                $parameters = @{
                    "bcAuthContext" = $bcAuthContext
                    "environment" = $deploymentSettings.EnvironmentName
                    "appFiles" = $apps
                }
                if ($deploymentSettings.SyncMode) {
                    if (@('Add','ForceSync') -notcontains $deploymentSettings.SyncMode) {
                        throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the automation API. Valid values are Add and ForceSync."
                    }
                    Write-Host "Using $($deploymentSettings.SyncMode)"
                    $syncMode = $deploymentSettings.SyncMode
                    if ($syncMode -eq 'ForceSync') { $syncMode = 'Force' }
                    $parameters += @{ "SchemaSyncMode" = $syncMode }
                }
                Write-Host "Publishing apps using automation API"
                Publish-PerTenantExtensionApps @parameters
            }
        }
    }
    catch {
        OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
        exit
    }
}
