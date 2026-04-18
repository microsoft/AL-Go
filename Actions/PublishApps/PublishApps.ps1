Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
DownloadAndImportBcContainerHelper

if ($project -eq ".") { $project = "" }
$baseFolder = $ENV:GITHUB_WORKSPACE
$projectPath = Join-Path $baseFolder $project

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting
$settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

$containerName = $env:containerName
if (-not $containerName) {
    throw "containerName environment variable is not set. Ensure SetupBuildEnvironment ran successfully."
}

$credential = New-Object pscredential 'admin', (ConvertTo-SecureString -String $env:containerPassword -AsPlainText -Force)
$tenant = "default"

$secrets = if ($env:Secrets) { $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable } else { @{} }

# Configure NuGet feed credentials for missing dependency resolution
$gitHubPackagesContext = ""
if ($secrets.Keys -contains 'gitHubPackagesContext') {
    $gitHubPackagesContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.'gitHubPackagesContext'))
}

if ($bcContainerHelperConfig.ContainsKey('TrustedNuGetFeeds')) {
    foreach ($trustedNuGetFeed in $bcContainerHelperConfig.TrustedNuGetFeeds) {
        if ($trustedNuGetFeed.PSObject.Properties.Name -eq 'Token') {
            if ($trustedNuGetFeed.Token -ne '') {
                OutputWarning -message "Auth token for NuGet feed is defined in settings. This is not recommended. Use a secret instead."
            }
        }
        else {
            $tokenValue = ''
            if ($trustedNuGetFeed.url -like 'https://nuget.pkg.github.com/*') {
                $tokenValue = $token
            }
            $trustedNuGetFeed | Add-Member -MemberType NoteProperty -Name 'Token' -Value $tokenValue
        }
        if ($trustedNuGetFeed.PSObject.Properties.Name -eq 'AuthTokenSecret' -and $trustedNuGetFeed.AuthTokenSecret) {
            $authTokenSecret = $trustedNuGetFeed.AuthTokenSecret
            if ($secrets.Keys -contains $authTokenSecret) {
                $authToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$authTokenSecret"))
                $trustedNuGetFeed.Token = GetAccessToken -token $authToken -repositories @() -permissions @{"packages"="read";"metadata"="read"}
            }
            else {
                OutputWarning -message "Secret $authTokenSecret needed for trusted NuGetFeeds cannot be found"
            }
        }
    }
}
else {
    $bcContainerHelperConfig.TrustedNuGetFeeds = @()
}
if ($settings.trustMicrosoftNuGetFeeds) {
    $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{
        "url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
        "token" = ''
    })
}

# Read dependency apps and test apps from JSON files
$installApps = @()
$installTestApps = @()

if ($installAppsJson -and (Test-Path $installAppsJson)) {
    $installApps = Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json
}
if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    $installTestApps = Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json
}

# Separate compiled app files from pure dependency files
# CompileApps appends compiled apps to the dependency JSON - they're the ones in .buildartifacts
$buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
$compiledApps = @()
$compiledTestApps = @()
$dependencyApps = @()
$dependencyTestApps = @()

foreach ($app in $installApps) {
    $appPath = "$app".Trim('()')
    if ($appPath -like "*$([System.IO.Path]::DirectorySeparatorChar).buildartifacts$([System.IO.Path]::DirectorySeparatorChar)*" -or $appPath -like "*/.buildartifacts/*") {
        $compiledApps += $appPath
    }
    else {
        $dependencyApps += $app
    }
}
foreach ($app in $installTestApps) {
    $appPath = "$app".Trim('()')
    if ($appPath -like "*$([System.IO.Path]::DirectorySeparatorChar).buildartifacts$([System.IO.Path]::DirectorySeparatorChar)*" -or $appPath -like "*/.buildartifacts/*") {
        $compiledTestApps += $appPath
    }
    else {
        $dependencyTestApps += $app
    }
}

# Step 1: Install dependency apps to container
if ($dependencyApps) {
    OutputGroupStart -Message "Installing dependency apps"
    $appFiles = @()
    foreach ($app in $dependencyApps) {
        $appPath = "$app".Trim('()')
        if ($appPath -and (Test-Path $appPath)) {
            $appFiles += $appPath
        }
    }
    if ($appFiles) {
        $sortedAppFiles = Sort-AppFilesByDependencies -appFiles $appFiles -WarningAction SilentlyContinue
        Publish-BcContainerApp -containerName $containerName -tenant $tenant -credential $credential `
            -appFile $sortedAppFiles -skipVerification -sync -install -upgrade -ignoreIfAppExists
    }
    OutputGroupEnd
}

# Step 2: Import test toolkit
$needTestToolkit = $settings.installTestRunner -or $settings.installTestFramework -or $settings.installTestLibraries -or $settings.installPerformanceToolkit
if ($needTestToolkit) {
    OutputGroupStart -Message "Importing test toolkit"
    $testToolkitParams = @{
        "containerName"              = $containerName
        "includeTestLibrariesOnly"   = [bool]$settings.installTestLibraries
        "includeTestFrameworkOnly"   = !$settings.installTestLibraries -and ($settings.installTestFramework -or $settings.installPerformanceToolkit)
        "includeTestRunnerOnly"      = !$settings.installTestLibraries -and !$settings.installTestFramework -and ($settings.installTestRunner -or $settings.installPerformanceToolkit)
        "includePerformanceToolkit"  = [bool]$settings.installPerformanceToolkit
        "doNotUseRuntimePackages"    = $true
    }
    Import-TestToolkitToBcContainer @testToolkitParams
    OutputGroupEnd
}

# Step 3: Install dependency test apps to container
if ($dependencyTestApps) {
    OutputGroupStart -Message "Installing dependency test apps"
    $appFiles = @()
    foreach ($app in $dependencyTestApps) {
        $appPath = "$app".Trim('()')
        if ($appPath -and (Test-Path $appPath)) {
            $appFiles += $appPath
        }
    }
    if ($appFiles) {
        $sortedAppFiles = Sort-AppFilesByDependencies -appFiles $appFiles -WarningAction SilentlyContinue
        Publish-BcContainerApp -containerName $containerName -tenant $tenant -credential $credential `
            -appFile $sortedAppFiles -skipVerification -sync -install -upgrade -ignoreIfAppExists
    }
    OutputGroupEnd
}

# Step 4: Install previous release for upgrade testing
if (-not $settings.skipUpgrade) {
    OutputGroupStart -Message "Installing previous release for upgrade testing"
    try {
        $branchForRelease = if ($ENV:GITHUB_BASE_REF) { $ENV:GITHUB_BASE_REF } else { $ENV:GITHUB_REF_NAME }
        $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $branchForRelease
        if ($latestRelease) {
            Write-Host "Using $($latestRelease.name) (tag $($latestRelease.tag_name)) as previous release"
            $artifactsFolder = Join-Path $baseFolder "artifacts"
            if (-not (Test-Path $artifactsFolder)) {
                New-Item $artifactsFolder -ItemType Directory | Out-Null
            }
            DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder -mask "Apps"
            $previousApps = @(Get-ChildItem -Path $artifactsFolder | ForEach-Object { $_.FullName })
            if ($previousApps) {
                $previousApps | ForEach-Object {
                    Publish-BcContainerApp -containerName $containerName -tenant $tenant -credential $credential `
                        -appFile $_ -skipVerification -sync -install
                }
            }
        }
        else {
            Write-Host "No previous release found"
        }
    }
    catch {
        OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
    }
    OutputGroupEnd
}

# Step 5: Publish compiled apps
if ($compiledApps) {
    OutputGroupStart -Message "Publishing compiled apps"
    $sortedCompiledApps = Sort-AppFilesByDependencies -appFiles $compiledApps -WarningAction SilentlyContinue
    Publish-BcContainerApp -containerName $containerName -tenant $tenant -credential $credential `
        -appFile $sortedCompiledApps -skipVerification -sync -install -upgrade -ignoreIfAppExists
    OutputGroupEnd
}

# Step 6: Publish compiled test apps
if ($compiledTestApps) {
    OutputGroupStart -Message "Publishing compiled test apps"
    $sortedCompiledTestApps = Sort-AppFilesByDependencies -appFiles $compiledTestApps -WarningAction SilentlyContinue
    Publish-BcContainerApp -containerName $containerName -tenant $tenant -credential $credential `
        -appFile $sortedCompiledTestApps -skipVerification -sync -install -upgrade -ignoreIfAppExists
    OutputGroupEnd
}

# Step 7: Generate dependency artifact
if ($settings.generateDependencyArtifact) {
    $dependenciesFolder = Join-Path $buildArtifactFolder "Dependencies"
    if (-not (Test-Path $dependenciesFolder)) {
        New-Item -ItemType Directory -Path $dependenciesFolder | Out-Null
    }
    foreach ($app in $dependencyApps) {
        $appPath = "$app".Trim('()')
        if ($appPath -and (Test-Path $appPath)) {
            Copy-Item -Path $appPath -Destination $dependenciesFolder -Force
        }
    }
}
