Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '',
    [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowRunId = '0',
    [Parameter(HelpMessage = "SHA of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowSHA = ''
)

$containerBaseFolder = $null
$projectPath = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
    DownloadAndImportBcContainerHelper
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking

    if ($isWindows) {
        # Pull docker image in the background
        $genericImageName = Get-BestGenericImageName
        Start-Job -ScriptBlock {
            docker pull --quiet $using:genericImageName
        } | Out-Null
    }

    $containerName = GetContainerName($project)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count-2]
    $owner = $ap[$ap.Count-4]

    if ($owner -ne "microsoft") {
        $verstr = "dev"
    }
    else {
        $verstr = $branch
    }

    $runAlPipelineParams = @{
        "sourceRepositoryUrl" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
        "sourceCommit" = $ENV:GITHUB_SHA
        "buildBy" = "AL-Go for GitHub,$verstr"
        "buildUrl" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY/actions/runs/$ENV:GITHUB_RUN_ID"
    }
    if ($project  -eq ".") { $project = "" }
    $baseFolder = $ENV:GITHUB_WORKSPACE
    if ($bcContainerHelperConfig.useVolumes -and $bcContainerHelperConfig.hostHelperFolder -eq "HostHelperFolder") {
        $allVolumes = "{$(((docker volume ls --format "'{{.Name}}': '{{.Mountpoint}}'") -join ",").Replace('\','\\').Replace("'",'"'))}" | ConvertFrom-Json | ConvertTo-HashTable
        $containerBaseFolder = Join-Path $allVolumes.hostHelperFolder $containerName
        if (Test-Path $containerBaseFolder) {
            Remove-Item -Path $containerBaseFolder -Recurse -Force
        }
        Write-Host "Creating temp folder"
        New-Item -Path $containerBaseFolder -ItemType Directory | Out-Null
        Copy-Item -Path $ENV:GITHUB_WORKSPACE -Destination $containerBaseFolder -Recurse -Force
        $baseFolder = Join-Path $containerBaseFolder (Get-Item -Path $ENV:GITHUB_WORKSPACE).BaseName
    }

    $projectPath = Join-Path $baseFolder $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $baseFolder
    }
    $workflowName = "$env:GITHUB_WORKFLOW".Trim()

    Write-Host "use settings and secrets"
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
    # ENV:Secrets is not set when running Pull_Request trigger
    if ($env:Secrets) {
        $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $secrets = @{}
    }

    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl','codeSignCertificateUrl','codeSignCertificatePassword','keyVaultCertificateUrl','keyVaultCertificatePassword','keyVaultClientId','gitHubPackagesContext','applicationInsightsConnectionString' | ForEach-Object {
        # Secrets might not be read during Pull Request runs
        if ($secrets.Keys -contains $_) {
            $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $value = ""
        }

        Set-Variable -Name $_ -Value $value
    }

    $analyzeRepoParams = @{}

    if ($artifact) {
        # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
        $settings.artifact = $artifact
        $gitHubHostedRunner = $settings.gitHubRunner -like "windows-*" -or $settings.gitHubRunner -like "ubuntu-*"
        if ($gitHubHostedRunner -and $settings.useCompilerFolder) {
            # If we are running GitHub hosted agents and UseCompilerFolder is set (and we have an artifactUrl), we need to set the artifactCachePath
            $runAlPipelineParams += @{
                "artifactCachePath" = Join-Path $ENV:RUNNER_TEMP ".artifactcache"
            }
            $analyzeRepoParams += @{
                "doNotCheckArtifactSetting" = $true
            }
        }
    }

    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project @analyzeRepoParams
    $settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

    if ((-not $settings.appFolders) -and (-not $settings.testFolders) -and (-not $settings.bcptTestFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

    if ($baselineWorkflowSHA -and $baselineWorkflowRunId -ne '0' -and $settings.incrementalBuilds.mode -eq 'modifiedApps') {
        # Incremental builds are enabled and we are only building modified apps
        try {
            $modifiedFiles = @(Get-ModifiedFiles -baselineSHA $baselineWorkflowSHA)
            OutputMessageAndArray -message "Modified files" -arrayOfStrings $modifiedFiles
            $buildAll = Get-BuildAllApps -baseFolder $baseFolder -project $project -modifiedFiles $modifiedFiles
        }
        catch {
            OutputNotice -message "Failed to calculate modified files since $baselineWorkflowSHA, building all apps"
            $buildAll = $true
        }
        if (!$buildAll) {
            Write-Host "Get unmodified apps from baseline workflow run"
            # Downloaded apps are placed in the build artifacts folder, which is detected by Run-AlPipeline, meaning only non-downloaded apps are built
            Get-UnmodifiedAppsFromBaselineWorkflowRun `
                -token $token `
                -settings $settings `
                -baseFolder $baseFolder `
                -project $project `
                -baselineWorkflowRunId $baselineWorkflowRunId `
                -modifiedFiles $modifiedFiles `
                -buildArtifactFolder $buildArtifactFolder `
                -buildMode $buildMode `
                -projectPath $projectPath
        }
    }

    if ($bcContainerHelperConfig.ContainsKey('TrustedNuGetFeeds')) {
        Write-Host "Reading TrustedNuGetFeeds"
        foreach($trustedNuGetFeed in $bcContainerHelperConfig.TrustedNuGetFeeds) {
            if ($trustedNuGetFeed.PSObject.Properties.Name -eq 'Token') {
                if ($trustedNuGetFeed.Token -ne '') {
                    OutputWarning -message "Auth token for NuGet feed is defined in settings. This is not recommended. Use a secret instead and specify the secret name in the AuthTokenSecret property"
                }
            }
            else {
                $tokenValue = ''
                if ($trustedNuGetFeed.url -like 'https://nuget.pkg.github.com/*') {
                    # GitHub Packages might be public, but they still require a token with read:packages permissions (not necessarily to the specific feed)
                    # instead of using a blank token, we use the GitHub token (which has read packages permissions) provided to the action
                    $tokenValue = $token
                }
                $trustedNuGetFeed | Add-Member -MemberType NoteProperty -Name 'Token' -Value $tokenValue
            }
            if ($trustedNuGetFeed.PSObject.Properties.Name -eq 'AuthTokenSecret' -and $trustedNuGetFeed.AuthTokenSecret) {
                $authTokenSecret = $trustedNuGetFeed.AuthTokenSecret
                if ($secrets.Keys -notcontains $authTokenSecret) {
                    OutputWarning -message "Secret $authTokenSecret needed for trusted NuGetFeeds cannot be found"
                }
                else {
                    $authToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$authTokenSecret"))
                    $trustedNuGetFeed.Token = GetAccessToken -token $authToken -repositories @() -permissions @{"packages"="read";"metadata"="read"}
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

    $install = @{
        "Apps" = $settings.installApps
        "TestApps" = $settings.installTestApps
    }

    if ($installAppsJson -and (Test-Path $installAppsJson)) {
        try {
            $install.Apps += @(Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json)
        }
        catch {
            throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
        try {
            $install.TestApps += @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    if ($settings.runTestsInAllInstalledTestApps) {
        # Trim parentheses from test apps. Run-ALPipeline will skip running tests in test apps wrapped in ()
        $install.TestApps = $install.TestApps | ForEach-Object { $_.TrimStart("(").TrimEnd(")") }
    }

    # Replace secret names in install.apps and install.testApps
    foreach($list in @('Apps','TestApps')) {
        $install."$list" = @($install."$list" | ForEach-Object {
            $pattern = '.*(\$\{\{\s*([^}]+?)\s*\}\}).*'
            $url = $_
            if ($url -match $pattern) {
                $finalUrl = $url.Replace($matches[1],[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($matches[2])")))
            }
            else {
                $finalUrl = $url
            }
            # Check validity of URL
            if ($finalUrl -like 'http*://*') {
                try {
                    Invoke-WebRequest -Method Head -UseBasicParsing -Uri $finalUrl | Out-Null
                }
                catch {
                    throw "Setting: install$($list) contains an inaccessible URL: $($url). Error was: $($_.Exception.Message)"
                }
            }
            return $finalUrl
        })
    }

    # Analyze app.json version dependencies before launching pipeline

    # Analyze InstallApps and InstallTestApps before launching pipeline


    # Check if codeSignCertificateUrl+Password is used (and defined)
    if (!$settings.doNotSignApps -and $codeSignCertificateUrl -and $codeSignCertificatePassword -and !$settings.keyVaultCodesignCertificateName) {
        OutputWarning -message "Using the legacy CodeSignCertificateUrl and CodeSignCertificatePassword parameters. Consider using the new Azure Keyvault signing instead. Go to https://aka.ms/ALGoSettings#keyVaultCodesignCertificateName to find out more"
        $runAlPipelineParams += @{
            "CodeSignCertPfxFile" = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -string $codeSignCertificatePassword
        }
    }
    if ($applicationInsightsConnectionString) {
        $runAlPipelineParams += @{
            "applicationInsightsConnectionString" = $applicationInsightsConnectionString
        }
    }

    if ($keyVaultCertificateUrl -and $keyVaultCertificatePassword -and $keyVaultClientId) {
        Trace-Information -Message "Enabling key vault access for apps"

        $runAlPipelineParams += @{
            "KeyVaultCertPfxFile" = $keyVaultCertificateUrl
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -string $keyVaultCertificatePassword
            "keyVaultClientId" = $keyVaultClientId
        }
    }

    $previousApps = @()
    if (!$settings.skipUpgrade) {
        Write-Host "::group::Locating previous release"
        try {
            $branchForRelease = if ($ENV:GITHUB_BASE_REF) { $ENV:GITHUB_BASE_REF } else { $ENV:GITHUB_REF_NAME }
            $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $branchForRelease
            if ($latestRelease) {
                Write-Host "Using $($latestRelease.name) (tag $($latestRelease.tag_name)) as previous release"
                $artifactsFolder = Join-Path $baseFolder "artifacts"
                if(-not (Test-Path $artifactsFolder)) {
                    New-Item $artifactsFolder -ItemType Directory | Out-Null
                }
                DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder -mask "Apps"
                $previousApps += @(Get-ChildItem -Path $artifactsFolder | ForEach-Object { $_.FullName })
            }
            else {
                OutputWarning -message "No previous release found"
            }
        }
        catch {
            OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
            exit
        }
        Write-Host "::endgroup::"
    }

    $additionalCountries = $settings.additionalCountries

    $imageName = ""
    if (-not $gitHubHostedRunner) {
        $imageName = $settings.cacheImageName
        if ($imageName) {
            Write-Host "::group::Flush ContainerHelper Cache"
            Flush-ContainerHelperCache -cache 'all,exitedcontainers' -keepdays $settings.cacheKeepDays
            Write-Host "::endgroup::"
        }
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($settings.versioningStrategy -eq -1) {
        $artifactVersion = [Version]$settings.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif (($settings.versioningStrategy -band 16) -eq 16) {
        # For versioningStrategy +16, the version number is taken from repoVersion setting
        $repoVersion = [System.Version]$settings.repoVersion
        if (($settings.versioningStrategy -band 15) -eq 3) {
            # For versioning strategy 3, we need to get the build number from repoVersion setting
            $appBuild = $repoVersion.Build
            if ($appBuild -eq -1) {
                Write-Warning "RepoVersion setting only contains Major.Minor version. When using versioningStrategy 3, it should contain 3 digits"
                $appBuild = 0
            }
        }
        $runAlPipelineParams += @{
            "appVersion" = "$($repoVersion.Major).$($repoVersion.Minor)"
        }
    }

    $allTestResults = "testresults*.xml"
    $testResultsFile = Join-Path $projectPath "TestResults.xml"
    $testResultsFiles = Join-Path $projectPath $allTestResults
    if (Test-Path $testResultsFiles) {
        Remove-Item $testResultsFiles -Force
    }

    $buildOutputFile = Join-Path $projectPath "BuildOutput.txt"
    $containerEventLogFile = Join-Path $projectPath "ContainerEventLog.evtx"

    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "containerName=$containerName"

    Set-Location $projectPath
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ALGoFolderName "$ScriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $scriptName"
            Trace-Information -Message "Using override for $scriptName"

            $runAlPipelineParams += @{
                "$scriptName" = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }

    if ($runAlPipelineParams.Keys -notcontains 'RemoveBcContainer') {
        $runAlPipelineParams += @{
            "RemoveBcContainer" = {
                Param([Hashtable]$parameters)
                Remove-BcContainerSession -containerName $parameters.ContainerName -killPsSessionProcess
                Remove-BcContainer @parameters
            }
        }
    }

    if ($runAlPipelineParams.Keys -notcontains 'ImportTestDataInBcContainer') {
        if (($settings.configPackages) -or ($settings.Keys | Where-Object { $_ -like 'configPackages.*' })) {
            Write-Host "Adding Import Test Data override"
            Write-Host "Configured config packages:"
            $settings.Keys | Where-Object { $_ -like 'configPackages*' } | ForEach-Object {
                Write-Host "- $($_):"
                $settings."$_" | ForEach-Object {
                    Write-Host "  - $_"
                }
            }
            $runAlPipelineParams += @{
                "ImportTestDataInBcContainer" = {
                    Param([Hashtable]$parameters)
                    $country = Get-BcContainerCountry -containerOrImageName $parameters.containerName
                    $prop = "configPackages.$country"
                    if ($settings.Keys -notcontains $prop) {
                        $prop = "configPackages"
                    }
                    if ($settings."$prop") {
                        Write-Host "Importing config packages from $prop"
                        $settings."$prop" | ForEach-Object {
                            $configPackage = $_.Split(',')[0].Replace('{COUNTRY}',$country)
                            $packageId = $_.Split(',')[1]
                            UploadImportAndApply-ConfigPackageInBcContainer `
                                -containerName $parameters.containerName `
                                -companyName $settings.companyName `
                                -Credential $parameters.credential `
                                -Tenant $parameters.tenant `
                                -ConfigPackage $configPackage `
                                -PackageId $packageId
                        }
                    }
               }
            }
        }
    }

    if ((($bcContainerHelperConfig.ContainsKey('TrustedNuGetFeeds') -and ($bcContainerHelperConfig.TrustedNuGetFeeds.Count -gt 0)) -or ($gitHubPackagesContext)) -and ($runAlPipelineParams.Keys -notcontains 'InstallMissingDependencies')) {
        if ($githubPackagesContext) {
            $gitHubPackagesCredential = $gitHubPackagesContext | ConvertFrom-Json
        }
        else {
            $gitHubPackagesCredential = [PSCustomObject]@{ "serverUrl" = ''; "token" = '' }
        }
        $runAlPipelineParams += @{
            "InstallMissingDependencies" = {
                Param([Hashtable]$parameters)
                foreach($missingDependency in $parameters.missingDependencies) {
                    $appid = $missingDependency.Split(':')[0]
                    $appName = $missingDependency.Split(':')[1]
                    $version = $appName.SubString($appName.LastIndexOf('_')+1)
                    $version = [System.Version]$version.SubString(0,$version.Length-4)

                    # If dependency app is already installed, skip it
                    # If dependency app is already published, synchronize and install it
                    if ($parameters.ContainsKey('containerName')) {
                        $appInfo = Get-BcContainerAppInfo -containerName $parameters.containerName -tenantSpecificProperties | Where-Object { $_.AppId -eq $appid }
                        if ($appInfo) {
                            # App already exists
                            if (-not $appInfo.isInstalled) {
                                Sync-BcContainerApp -containerName $parameters.containerName -tenant $parameters.tenant -appPublisher $appInfo.Publisher -appName $appInfo.Name -appVersion "$($appInfo.version)"
                                Install-BcContainerApp -containerName $parameters.containerName -tenant $parameters.tenant -appPublisher $appInfo.Publisher -appName $appInfo.Name -appVersion "$($appInfo.version)"
                            }
                            continue
                        }
                    }

                    $publishParams = @{
                        "nuGetServerUrl" = $gitHubPackagesCredential.serverUrl
                        "nuGetToken" = GetAccessToken -token $gitHubPackagesCredential.token -permissions @{"packages"="read";"contents"="read";"metadata"="read"} -repositories @()
                        "packageName" = $appId
                        "version" = $version
                        "select" = $settings.nuGetFeedSelectMode
                    }
                    if ($parameters.ContainsKey('CopyInstalledAppsToFolder')) {
                        $publishParams += @{
                            "CopyInstalledAppsToFolder" = $parameters.CopyInstalledAppsToFolder
                        }
                    }
                    if ($parameters.ContainsKey('containerName')) {
                        Publish-BcNuGetPackageToContainer -containerName $parameters.containerName -tenant $parameters.tenant -skipVerification -appSymbolsFolder $parameters.appSymbolsFolder @publishParams -ErrorAction SilentlyContinue
                    }
                    else {
                        if ($parameters.ContainsKey('installedApps') -and $parameters.ContainsKey('installedCountry')) {
                            foreach($installedApp in $parameters.installedApps) {
                                if ($installedApp.Id -eq $platformAppId) {
                                    $publishParams += @{
                                        "installedApps" = $parameters.installedApps
                                        "installedPlatform" = ([System.Version]$installedApp.Version)
                                        "installedCountry" = $parameters.installedCountry
                                    }
                                    break
                                }
                            }
                        }
                        Download-BcNuGetPackageToFolder -folder $parameters.appSymbolsFolder @publishParams | Out-Null
                    }
                }
            }
        }
    }

    "enableTaskScheduler",
    "assignPremiumPlan",
    "doNotBuildTests",
    "doNotRunTests",
    "doNotRunBcptTests",
    "doNotRunPageScriptingTests",
    "doNotPublishApps",
    "installTestRunner",
    "installTestFramework",
    "installTestLibraries",
    "installPerformanceToolkit",
    "enableCodeCop",
    "enableAppSourceCop",
    "enablePerTenantExtensionCop",
    "enableUICop",
    "enableCodeAnalyzersOnTestApps",
    "useCompilerFolder",
    "reportSuppressedDiagnostics" | ForEach-Object {
        if ($settings."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    if ($buildMode -eq 'Translated') {
        if ($runAlPipelineParams.Keys -notcontains 'features') {
            $runAlPipelineParams["features"] = @()
        }
        Write-Host "Adding translationfile feature"
        $runAlPipelineParams["features"] += "translationfile"
    }

    if ($runAlPipelineParams.Keys -notcontains 'preprocessorsymbols') {
        $runAlPipelineParams["preprocessorsymbols"] = @()
    }

    if ($settings.ContainsKey('preprocessorSymbols')) {
        Write-Host "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $runAlPipelineParams["preprocessorsymbols"] += $settings.preprocessorSymbols
    }

    Write-Host "Invoke Run-AlPipeline with buildmode $buildMode"
    Run-AlPipeline @runAlPipelineParams `
        -accept_insiderEula `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $settings.artifact.replace('{INSIDERSASTOKEN}','') `
        -vsixFile $settings.vsixFile `
        -companyName $settings.companyName `
        -memoryLimit $settings.memoryLimit `
        -baseFolder $projectPath `
        -sharedFolder $sharedFolder `
        -licenseFile $licenseFileUrl `
        -installApps $install.apps `
        -installTestApps $install.testApps `
        -installOnlyReferencedApps:$settings.installOnlyReferencedApps `
        -generateDependencyArtifact `
        -updateDependencies:$settings.updateDependencies `
        -previousApps $previousApps `
        -appFolders $settings.appFolders `
        -testFolders $settings.testFolders `
        -bcptTestFolders $settings.bcptTestFolders `
        -pageScriptingTests $settings.pageScriptingTests `
        -restoreDatabases $settings.restoreDatabases `
        -buildOutputFile $buildOutputFile `
        -containerEventLogFile $containerEventLogFile `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -customCodeCops $settings.customCodeCops `
        -gitHubActions `
        -failOn $settings.failOn `
        -treatTestFailuresAsWarnings:$settings.treatTestFailuresAsWarnings `
        -rulesetFile $settings.rulesetFile `
        -generateErrorLog:$settings.trackALAlertsInGitHub `
        -enableExternalRulesets:$settings.enableExternalRulesets `
        -appSourceCopMandatoryAffixes $settings.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -obsoleteTagMinAllowedMajorMinor $settings.obsoleteTagMinAllowedMajorMinor `
        -buildArtifactFolder $buildArtifactFolder `
        -pageScriptingTestResultsFile (Join-Path $buildArtifactFolder 'PageScriptingTestResults.xml') `
        -pageScriptingTestResultsFolder (Join-Path $buildArtifactFolder 'PageScriptingTestResultDetails') `
        -CreateRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild -appRevision $appRevision `
        -uninstallRemovedApps

    if ($containerBaseFolder) {
        Write-Host "Copy artifacts and build output back from build container"
        $destFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
        Copy-Item -Path (Join-Path $projectPath ".buildartifacts") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $projectPath ".output") -Destination $destFolder -Recurse -Force
        Copy-Item -Path (Join-Path $projectPath "testResults*.xml") -Destination $destFolder
        Copy-Item -Path (Join-Path $projectPath "bcptTestResults*.json") -Destination $destFolder
        Copy-Item -Path $buildOutputFile -Destination $destFolder -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $containerEventLogFile -Destination $destFolder -Force -ErrorAction SilentlyContinue
    }

    # check for new warnings
    Import-Module (Join-Path $PSScriptRoot ".\CheckForWarningsUtils.psm1" -Resolve) -DisableNameChecking

    Test-ForNewWarnings -token $token `
        -project $project `
        -settings $settings `
        -buildMode $buildMode `
        -baselineWorkflowRunId $baselineWorkflowRunId `
        -prBuildOutputFile $buildOutputFile
}
catch {
    throw
}
finally {
    try {
        if (Test-BcContainer -containerName $containerName) {
            Write-Host "Get Event Log from container"
            $eventlogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
            Copy-Item -Path $eventLogFile -Destination $containerEventLogFile
            if ($project) {
                # Copy event log to project folder if multiproject
                $destFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
                Copy-Item -Path $containerEventLogFile -Destination $destFolder
            }
        }
    }
    catch {
        Write-Host "Error getting event log from container: $($_.Exception.Message)"
    }
    if ($containerBaseFolder -and (Test-Path $containerBaseFolder) -and $projectPath -and (Test-Path $projectPath)) {
        Write-Host "Removing temp folder"
        Remove-Item -Path (Join-Path $projectPath '*') -Recurse -Force
        Write-Host "Done"
    }
}
