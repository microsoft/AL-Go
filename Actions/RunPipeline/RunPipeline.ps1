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
    [string] $baselineWorkflowSHA = '',
    [Parameter(HelpMessage = "Dependencies of the built project in compressed JSON format", Mandatory = $false)]
    [string] $projectDependenciesJson = '{}'
)

$containerBaseFolder = $null
$projectPath = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
    DownloadAndImportBcContainerHelper
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking

    # Import Code Coverage module for ALTestRunner functionality
    # This makes Run-AlTests available globally for custom RunTestsInBcContainer overrides
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\TestRunner\ALTestRunner.psm1" -Resolve) -Force -DisableNameChecking

    if ($isWindows) {
        Assert-DockerIsRunning
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

    if ($settings.workspaceCompilation.enabled -and $settings.doNotPublishApps) {
        OutputColor -Message "Workspace compilation complete; doNotPublishApps is set. Exiting." -Color Yellow
        return
    }

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

    $isTestProject = $settings.projectsToTest -and $settings.projectsToTest.Count -gt 0
    if ((-not $settings.appFolders) -and (-not $settings.testFolders) -and (-not $settings.bcptTestFolders)) {
        if (-not $isTestProject) {
            Write-Host "Repository is empty, exiting"
            exit
        }
        Write-Host "Test project: no local app/test folders, will install and test apps from upstream projects"
    }

    $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
    if (-not (Test-Path $buildArtifactFolder)) {
        New-Item $buildArtifactFolder -ItemType Directory | Out-Null
    } elseif(-not ($settings.workspaceCompilation.enabled)) {
        OutputDebug -message "Build artifacts folder $buildArtifactFolder already exists. Previous build artifacts might interfere with the current build."
    }

    # When using workspace compilation, apps are already compiled - pass empty folders to Run-AlPipeline
    if ($settings.workspaceCompilation.enabled) {
        $appFolders = @()
        $testFolders = @()
        $bcptTestFolders = $settings.bcptTestFolders
    }
    else {
        $appFolders = $settings.appFolders
        $testFolders = $settings.testFolders
        $bcptTestFolders = $settings.bcptTestFolders
    }

    if ((-not $settings.workspaceCompilation.enabled) -and $baselineWorkflowSHA -and $baselineWorkflowRunId -ne '0' -and $settings.incrementalBuilds.mode -eq 'modifiedApps') {
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
        "Apps" = @()
        "TestApps" = @()
    }

    if ($installAppsJson -and (Test-Path $installAppsJson)) {
        try {
            $install.Apps = Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
        try {
            $install.TestApps = Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    if ($settings.runTestsInAllInstalledTestApps) {
        # Trim parentheses from test apps. Run-ALPipeline will skip running tests in test apps wrapped in ()
        $install.TestApps = $install.TestApps | ForEach-Object { $_.TrimStart("(").TrimEnd(")") }
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
        if ($settings.workspaceCompilation.enabled) {
            OutputWarning -message "skipUpgrade is ignored when workspaceCompilation is enabled." # TODO: Missing implementation when workspace compilation is enabled (AB#620310)
        } else {
            OutputGroupStart -Message "Locating previous release"
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
            finally {
                OutputGroupEnd
            }
        }
    }

    $additionalCountries = $settings.additionalCountries

    $imageName = ""
    if (-not $gitHubHostedRunner) {
        $imageName = $settings.cacheImageName
        if ($imageName) {
            OutputGroupStart -Message "Flush ContainerHelper Cache"
            Flush-ContainerHelperCache -cache 'all,exitedcontainers' -keepdays $settings.cacheKeepDays
            OutputGroupEnd
        }
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    $versionNumber = Get-VersionNumber -Settings $settings

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
    $scriptOverrides = Get-ScriptOverrides -ALGoFolderName $ALGoFolderName -OverrideScriptNames $runAlPipelineOverrides
    $scriptOverrides.Keys | ForEach-Object { Trace-Information -Message "Using override for $_" }
    $runAlPipelineParams += $scriptOverrides

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
                        try {
                            Publish-BcNuGetPackageToContainer -containerName $parameters.containerName -tenant $parameters.tenant -skipVerification -appSymbolsFolder $parameters.appSymbolsFolder @publishParams
                        } catch {
                            OutputWarning -message "Failed to publish app $appid version $version to container $($parameters.containerName). Error was: $($_.Exception.Message)."
                        }
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

    # Add RunTestsInBcContainer override to use ALTestRunner with code coverage support
    if ($settings.enableCodeCoverage) {
        # Read codeCoverageSetup settings with defaults
        $codeCoverageSetup = if ($settings.ContainsKey('codeCoverageSetup')) { $settings.codeCoverageSetup } else { $null }
        $ccSetup = @{}
        if ($codeCoverageSetup) {
            if ($codeCoverageSetup -is [hashtable]) {
                $codeCoverageSetup.GetEnumerator() | ForEach-Object { $ccSetup[$_.Key] = $_.Value }
            } else {
                $codeCoverageSetup.PSObject.Properties | ForEach-Object { $ccSetup[$_.Name] = $_.Value }
            }
        }
        $ccTrackingType = if ($ccSetup['trackingType']) { $ccSetup['trackingType'] } else { 'PerRun' }
        $ccProduceMap = if ($ccSetup['produceCodeCoverageMap']) { $ccSetup['produceCodeCoverageMap'] } else { 'PerCodeunit' }
        [string[]]$ccExcludePatterns = @()
        if ($ccSetup['excludeFilesPattern']) { $ccExcludePatterns = @($ccSetup['excludeFilesPattern']) }
        if ($ccExcludePatterns.Count -gt 0) {
            Write-Host "Code coverage exclude patterns: $($ccExcludePatterns -join ', ')"
        }

        if ($runAlPipelineParams.Keys -notcontains 'RunTestsInBcContainer') {
            Write-Host "Adding RunTestsInBcContainer override with code coverage support"

            # Capture variables for use in scriptblock
            $ccBuildArtifactFolder = $buildArtifactFolder
            $ccTrackingTypeCapture = $ccTrackingType
            $ccProduceMapCapture = $ccProduceMap

            $runAlPipelineParams += @{
                "RunTestsInBcContainer" = {
                    Param([Hashtable]$parameters)

                    $containerName = $parameters.containerName
                    $credential = $parameters.credential
                    $extensionId = $parameters.extensionId
                    $appName = $parameters.appName

                    # Handle both JUnit and XUnit result file names
                    $resultsFilePath = $null
                    $resultsFormat = 'JUnit'
                    if ($parameters.JUnitResultFileName) {
                        $resultsFilePath = $parameters.JUnitResultFileName
                        $resultsFormat = 'JUnit'
                    } elseif ($parameters.XUnitResultFileName) {
                        $resultsFilePath = $parameters.XUnitResultFileName
                        $resultsFormat = 'XUnit'
                    }

                    # Handle append mode for result file accumulation across test apps
                    $appendToResults = $false
                    $tempResultsFilePath = $null
                    if ($resultsFilePath -and ($parameters.AppendToJUnitResultFile -or $parameters.AppendToXUnitResultFile)) {
                        $appendToResults = $true
                        $tempResultsFilePath = Join-Path ([System.IO.Path]::GetDirectoryName($resultsFilePath)) "TempTestResults_$([Guid]::NewGuid().ToString('N')).xml"
                    }

                    # Get container web client URL for connecting from host
                    $containerConfig = Get-BcContainerServerConfiguration -ContainerName $containerName
                    $publicWebBaseUrl = $containerConfig.PublicWebBaseUrl
                    if (-not $publicWebBaseUrl) {
                        # Fallback to constructing URL from container name
                        $publicWebBaseUrl = "http://$($containerName):80/BC/"
                    }
                    # Ensure tenant parameter is included (required for client services connection)
                    $tenant = if ($parameters.tenant) { $parameters.tenant } else { "default" }
                    if ($publicWebBaseUrl -notlike "*tenant=*") {
                        if ($publicWebBaseUrl.Contains("?")) {
                            $serviceUrl = "$publicWebBaseUrl&tenant=$tenant"
                        } else {
                            $serviceUrl = "$($publicWebBaseUrl.TrimEnd('/'))/?tenant=$tenant"
                        }
                    } else {
                        $serviceUrl = $publicWebBaseUrl
                    }
                    Write-Host "Using ServiceUrl: $serviceUrl"

                    # Code coverage output path
                    $codeCoverageOutputPath = Join-Path $ccBuildArtifactFolder "CodeCoverage"
                    if (-not (Test-Path $codeCoverageOutputPath)) {
                        New-Item -Path $codeCoverageOutputPath -ItemType Directory | Out-Null
                    }
                    Write-Host "Code coverage output path: $codeCoverageOutputPath"

                    # Run tests with ALTestRunner from the host
                    $testRunParams = @{
                        ServiceUrl = $serviceUrl
                        Credential = $credential
                        AutorizationType = 'NavUserPassword'
                        TestSuite = if ($parameters.testSuite) { $parameters.testSuite } else { 'DEFAULT' }
                        Detailed = $true
                        DisableSSLVerification = $true
                        ResultsFormat = $resultsFormat
                        CodeCoverageTrackingType = $ccTrackingTypeCapture
                        ProduceCodeCoverageMap = $ccProduceMapCapture
                        CodeCoverageOutputPath = $codeCoverageOutputPath
                        CodeCoverageFilePrefix = "CodeCoverage_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                    }

                    if ($extensionId) {
                        $testRunParams.ExtensionId = $extensionId
                    }

                    if ($appName) {
                        $testRunParams.AppName = $appName
                    }

                    if ($resultsFilePath) {
                        $testRunParams.ResultsFilePath = if ($appendToResults) { $tempResultsFilePath } else { $resultsFilePath }
                        $testRunParams.SaveResultFile = $true
                    }

                    # Forward optional pipeline parameters
                    if ($parameters.disabledTests) {
                        $testRunParams.DisabledTests = $parameters.disabledTests
                    }
                    if ($parameters.testCodeunitRange) {
                        $testRunParams.TestCodeunitsRange = $parameters.testCodeunitRange
                    }
                    elseif ($parameters.testCodeunit -and $parameters.testCodeunit -ne "*") {
                        $testRunParams.TestCodeunitsRange = $parameters.testCodeunit
                    }
                    if ($parameters.testFunction -and $parameters.testFunction -ne "*") {
                        $testRunParams.TestProcedureRange = $parameters.testFunction
                    }
                    if ($parameters.requiredTestIsolation) {
                        $testRunParams.RequiredTestIsolation = $parameters.requiredTestIsolation
                    }
                    if ($parameters.testType) {
                        $testRunParams.TestType = $parameters.testType
                    }
                    if ($parameters.testRunnerCodeunitId) {
                        # Map BCApps test runner codeunit IDs to Run-AlTests TestIsolation values
                        # 130450 = Codeunit isolation (default), 130451 = Disabled isolation
                        $testRunParams.TestIsolation = if ($parameters.testRunnerCodeunitId -eq "130451") { "Disabled" } else { "Codeunit" }
                    }

                    Run-AlTests @testRunParams

                    # Determine which file to check for this app's results
                    $checkResultsFile = if ($appendToResults) { $tempResultsFilePath } else { $resultsFilePath }
                    $testsPassed = $true

                    if ($checkResultsFile -and (Test-Path $checkResultsFile)) {
                        # Parse results to determine pass/fail
                        try {
                            [xml]$testResults = Get-Content $checkResultsFile -Encoding UTF8
                            if ($testResults.testsuites) {
                                $failures = 0; $errors = 0
                                if ($testResults.testsuites.testsuite) {
                                    foreach ($ts in $testResults.testsuites.testsuite) {
                                        if ($ts.failures) { $failures += [int]$ts.failures }
                                        if ($ts.errors) { $errors += [int]$ts.errors }
                                    }
                                }
                                $testsPassed = ($failures -eq 0 -and $errors -eq 0)
                            }
                            elseif ($testResults.assemblies) {
                                $failed = if ($testResults.assemblies.assembly.failed) { [int]$testResults.assemblies.assembly.failed } else { 0 }
                                $testsPassed = ($failed -eq 0)
                            }
                        }
                        catch {
                            Write-Host "Warning: Could not parse test results file: $_"
                        }

                        # Merge this app's results into the consolidated file if append mode
                        if ($appendToResults) {
                            if (-not (Test-Path $resultsFilePath)) {
                                Copy-Item -Path $tempResultsFilePath -Destination $resultsFilePath
                            }
                            else {
                                try {
                                    [xml]$source = Get-Content $tempResultsFilePath -Encoding UTF8
                                    [xml]$target = Get-Content $resultsFilePath -Encoding UTF8
                                    $rootElement = if ($resultsFormat -eq 'JUnit') { 'testsuites' } else { 'assemblies' }
                                    foreach ($node in $source.$rootElement.ChildNodes) {
                                        if ($node.NodeType -eq 'Element') {
                                            $imported = $target.ImportNode($node, $true)
                                            $target.$rootElement.AppendChild($imported) | Out-Null
                                        }
                                    }
                                    $target.Save($resultsFilePath)
                                }
                                catch {
                                    Write-Host "Warning: Could not merge test results, copying instead: $_"
                                    Copy-Item -Path $tempResultsFilePath -Destination $resultsFilePath -Force
                                }
                            }
                            Remove-Item $tempResultsFilePath -Force -ErrorAction SilentlyContinue
                        }
                    }

                    return $testsPassed
                }.GetNewClosure()
            }
        } else {
            OutputWarning -message "enableCodeCoverage is set to true, but a custom RunTestsInBcContainer override was found. The custom override will be used and code coverage data may not be collected. To use the built-in code coverage support, remove your custom RunTestsInBcContainer override."
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
        Write-Host "Adding translationfile feature"
        $settings.features += "translationfile"
    }

    if ($settings.preprocessorSymbols.Count -gt 0) {
        Write-Host "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
    }
    $runAlPipelineParams["preprocessorsymbols"] = $settings.preprocessorSymbols
    $runAlPipelineParams["features"] = $settings.features

    # Set environment variable for buildArtifactFolder so custom override scripts can access it
    # This is needed for code coverage support in repos with custom RunTestsInBcContainer overrides
    $env:AL_GO_BUILD_ARTIFACT_FOLDER = $buildArtifactFolder
    Write-Host "Build artifact folder: $buildArtifactFolder"

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
        -appFolders $appFolders `
        -testFolders $testFolders `
        -bcptTestFolders $bcptTestFolders `
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
        -appVersion ($versionNumber.MajorMinorVersion) -appBuild ($versionNumber.BuildNumber) -appRevision ($versionNumber.RevisionNumber) `
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

    # Process code coverage files to Cobertura format
    if ($settings.enableCodeCoverage) {
        $codeCoveragePath = Join-Path $buildArtifactFolder "CodeCoverage"
        if (Test-Path $codeCoveragePath) {
            $coverageFiles = @(Get-ChildItem -Path $codeCoveragePath -Filter "*.dat" -File -ErrorAction SilentlyContinue)
            if ($coverageFiles.Count -gt 0) {
                Write-Host "Processing $($coverageFiles.Count) code coverage file(s) to Cobertura format..."
                try {
                    $coverageProcessorModule = Join-Path $PSScriptRoot "..\.Modules\TestRunner\CoverageProcessor\CoverageProcessor.psm1"
                    Import-Module $coverageProcessorModule -Force -DisableNameChecking

                    $coberturaOutputPath = Join-Path $codeCoveragePath "cobertura.xml"

                    # Resolve app source paths for coverage denominator
                    # Collect appFolders from this project + parent projects (dependency chain)
                    # This ensures test-only projects measure coverage against the correct app source
                    $sourcePath = $ENV:GITHUB_WORKSPACE
                    $appSourcePaths = @()

                    # Add current project's app folders
                    if ($settings.appFolders -and $settings.appFolders.Count -gt 0) {
                        foreach ($folder in $settings.appFolders) {
                            $absPath = Join-Path $projectPath $folder
                            if (Test-Path $absPath) {
                                $appSourcePaths += @((Resolve-Path $absPath).Path)
                            }
                        }
                        Write-Host "Project app folders ($($appSourcePaths.Count) resolved):"
                        $appSourcePaths | ForEach-Object { Write-Host "  $_" }
                    }

                    # Walk project dependencies to collect parent projects' app folders
                    try {
                        $projectDeps = $projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
                        $parentProjects = @()
                        if ($projectDeps -and $project -and $projectDeps.ContainsKey($project)) {
                            $parentProjects = @($projectDeps[$project])
                        }
                        if ($parentProjects.Count -gt 0) {
                            Write-Host "Resolving app folders from $($parentProjects.Count) parent project(s): $($parentProjects -join ', ')"
                            foreach ($parentProject in $parentProjects) {
                                $parentSettings = ReadSettings -project $parentProject -baseFolder $baseFolder
                                ResolveProjectFolders -baseFolder $baseFolder -project $parentProject -projectSettings ([ref] $parentSettings)
                                $parentProjectPath = Join-Path $baseFolder $parentProject
                                if ($parentSettings.appFolders -and $parentSettings.appFolders.Count -gt 0) {
                                    foreach ($folder in $parentSettings.appFolders) {
                                        $absPath = Join-Path $parentProjectPath $folder
                                        if (Test-Path $absPath) {
                                            $resolved = (Resolve-Path $absPath).Path
                                            if ($appSourcePaths -notcontains $resolved) {
                                                $appSourcePaths += @($resolved)
                                                Write-Host "  + $resolved (from $parentProject)"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        OutputWarning -message "Could not resolve project dependencies for coverage: $($_.Exception.Message)"
                    }

                    if ($appSourcePaths.Count -eq 0) {
                        Write-Host "No app source paths resolved, scanning entire workspace for source files"
                    } else {
                        Write-Host "Coverage source: $($appSourcePaths.Count) app folder(s) resolved"
                    }
                    Write-Host "Source path root: $sourcePath"

                    if ($coverageFiles.Count -eq 1) {
                        # Single coverage file
                        $coverageStats = Convert-BCCoverageToCobertura `
                            -CoverageFilePath $coverageFiles[0].FullName `
                            -SourcePath $sourcePath `
                            -AppSourcePaths $appSourcePaths `
                            -ExcludePatterns $ccExcludePatterns `
                            -OutputPath $coberturaOutputPath
                    } else {
                        # Multiple coverage files - merge them
                        $coverageStats = Merge-BCCoverageToCobertura `
                            -CoverageFiles ($coverageFiles.FullName) `
                            -SourcePath $sourcePath `
                            -AppSourcePaths $appSourcePaths `
                            -ExcludePatterns $ccExcludePatterns `
                            -OutputPath $coberturaOutputPath
                    }

                    if ($coverageStats) {
                        Write-Host "Code coverage: $($coverageStats.CoveragePercent)% ($($coverageStats.CoveredLines)/$($coverageStats.TotalLines) lines)"
                    }
                }
                catch {
                    OutputWarning -message "Failed to process code coverage to Cobertura format: $($_.Exception.Message)"
                }
            }
        }
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
