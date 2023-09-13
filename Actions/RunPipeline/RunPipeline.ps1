Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [ValidateSet('Default', 'Translated', 'Clean')]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '[]',
    [Parameter(HelpMessage = "A JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '[]'
)

$telemetryScope = $null
$containerBaseFolder = $null
$projectPath = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0080' -parentTelemetryScopeJson $parentTelemetryScopeJson

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
    $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl','insiderSasToken','codeSignCertificateUrl','*codeSignCertificatePassword','keyVaultCertificateUrl','*keyVaultCertificatePassword','keyVaultClientId','gitHubPackagesContext','applicationInsightsConnectionString' | ForEach-Object {
        # Secrets might not be read during Pull Request runs
        if ($secrets.Keys -contains $_) {
            $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $value = ""
        }
        # Secrets preceded by an asterisk are returned encrypted.
        # Variable name should not include the asterisk
        Set-Variable -Name $_.TrimStart('*') -Value $value
    }

    $analyzeRepoParams = @{}
    # If UseCompilerFolder is set, set the parameter on Run-AlPipeline
    if ($settings.useCompilerFolder) {
        $runAlPipelineParams += @{
            "useCompilerFolder" = $true
        }
    }
    if ($artifact) {
        # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
        $settings.artifact = $artifact
        $gitHubHostedRunner = $settings.gitHubRunner -like "windows-*" -or $settings.gitHubRunner -like "ubuntu-*"
        if ($gitHubHostedRunner -and $settings.useCompilerFolder) {
            # If we are running GitHub hosted agents and UseCompilerFolder is set (and we have an artifactUrl), we need to set the artifactCachePath
            $runAlPipelineParams += @{
                "artifactCachePath" = Join-Path $ENV:GITHUB_WORKSPACE ".artifactcache"
            }
            $analyzeRepoParams += @{
                "doNotCheckArtifactSetting" = $true
            }
        }
    }

    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -insiderSasToken $insiderSasToken @analyzeRepoParams
    $settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

    if ((-not $settings.appFolders) -and (-not $settings.testFolders) -and (-not $settings.bcptTestFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    if ($settings.type -eq "AppSource App" ) {
        if ($licenseFileUrl -eq "") {
            OutputWarning -message "When building an AppSource App, you should create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
        }
    }

    $installApps = $settings.installApps
    $installTestApps = $settings.installTestApps

    $installApps += $installAppsJson | ConvertFrom-Json
    $installTestApps += $installTestAppsJson | ConvertFrom-Json

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
            $latestRelease = GetLatestRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -ref $ENV:GITHUB_REF_NAME
            if ($latestRelease) {
                Write-Host "Using $($latestRelease.name) (tag $($latestRelease.tag_name)) as previous release"
                $artifactsFolder = Join-Path $baseFolder "artifacts"
                New-Item $artifactsFolder -ItemType Directory | Out-Null
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
        $runAlPipelineParams += @{
            "appVersion" = $settings.repoVersion
        }
    }

    $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

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

    if ($gitHubPackagesContext -and ($runAlPipelineParams.Keys -notcontains 'InstallMissingDependencies')) {
        $gitHubPackagesCredential = $gitHubPackagesContext | ConvertFrom-Json
        $runAlPipelineParams += @{
            "InstallMissingDependencies" = {
                Param([Hashtable]$parameters)
                $parameters.missingDependencies | ForEach-Object {
                    $appid = $_.Split(':')[0]
                    $appName = $_.Split(':')[1]
                    $version = $appName.SubString($appName.LastIndexOf('_')+1)
                    $version = [System.Version]$version.SubString(0,$version.Length-4)
                    $publishParams = @{
                        "nuGetServerUrl" = $gitHubPackagesCredential.serverUrl
                        "nuGetToken" = $gitHubPackagesCredential.token
                        "packageName" = "AL-Go-$appId"
                        "version" = $version
                    }
                    if ($parameters.ContainsKey('CopyInstalledAppsToFolder')) {
                        $publishParams += @{
                            "CopyInstalledAppsToFolder" = $parameters.CopyInstalledAppsToFolder
                        }
                    }
                    if ($parameters.ContainsKey('containerName')) {
                        Publish-BcNuGetPackageToContainer -containerName $parameters.containerName -tenant $parameters.tenant -skipVerification @publishParams
                    }
                    else {
                        Copy-BcNuGetPackageToFolder -appSymbolsFolder $parameters.appSymbolsFolder @publishParams
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
    "doNotPublishApps",
    "installTestRunner",
    "installTestFramework",
    "installTestLibraries",
    "installPerformanceToolkit",
    "enableCodeCop",
    "enableAppSourceCop",
    "enablePerTenantExtensionCop",
    "enableUICop" | ForEach-Object {
        if ($settings."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    switch($buildMode){
        'Clean' {
            $preprocessorsymbols = $settings.cleanModePreprocessorSymbols

            if (!$preprocessorsymbols) {
                throw "No cleanModePreprocessorSymbols defined in settings.json for this project. Please add the preprocessor symbols to use when building in clean mode or disable CLEAN mode."
            }

            if ($runAlPipelineParams.Keys -notcontains 'preprocessorsymbols') {
                $runAlPipelineParams["preprocessorsymbols"] = @()
            }

            Write-Host "Adding Preprocessor symbols: $preprocessorsymbols"
            $runAlPipelineParams["preprocessorsymbols"] += $preprocessorsymbols
        }
        'Translated' {
            if ($runAlPipelineParams.Keys -notcontains 'features') {
                $runAlPipelineParams["features"] = @()
            }
            $runAlPipelineParams["features"] += "translationfile"
        }
    }

    Write-Host "Invoke Run-AlPipeline with buildmode $buildMode"
    Run-AlPipeline @runAlPipelineParams `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $settings.artifact.replace('{INSIDERSASTOKEN}',$insiderSasToken) `
        -vsixFile $settings.vsixFile `
        -companyName $settings.companyName `
        -memoryLimit $settings.memoryLimit `
        -baseFolder $projectPath `
        -sharedFolder $sharedFolder `
        -licenseFile $licenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -installOnlyReferencedApps:$settings.installOnlyReferencedApps `
        -generateDependencyArtifact:$settings.generateDependencyArtifact `
        -updateDependencies:$settings.updateDependencies `
        -previousApps $previousApps `
        -appFolders $settings.appFolders `
        -testFolders $settings.testFolders `
        -bcptTestFolders $settings.bcptTestFolders `
        -buildOutputFile $buildOutputFile `
        -containerEventLogFile $containerEventLogFile `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -customCodeCops $settings.customCodeCops `
        -gitHubActions `
        -failOn $settings.failOn `
        -treatTestFailuresAsWarnings:$settings.treatTestFailuresAsWarnings `
        -rulesetFile $settings.rulesetFile `
        -appSourceCopMandatoryAffixes $settings.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -obsoleteTagMinAllowedMajorMinor $settings.obsoleteTagMinAllowedMajorMinor `
        -buildArtifactFolder $buildArtifactFolder `
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

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
finally {
    try {
        if (Test-BcContainer -containerName $containerName) {
            Write-Host "Get Event Log from container"
            $eventlogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
            Copy-Item -Path $eventLogFile -Destination $containerEventLogFile
            $destFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
            Copy-Item -Path $containerEventLogFile -Destination $destFolder
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
