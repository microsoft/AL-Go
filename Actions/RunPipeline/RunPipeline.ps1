Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Project Dependencies in compressed Json format", Mandatory = $false)]
    [string] $projectDependenciesJson = "",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"appBuild":"", "appRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"","licenseFileUrl":"","codeSignCertificateUrl":"","codeSignCertificatePassword":"","keyVaultCertificateUrl":"","keyVaultCertificatePassword":"","keyVaultClientId":"","storageContext":"","applicationInsightsConnectionString":""}',
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [ValidateSet('Default', 'Translated', 'Clean')]
    [string] $buildMode = 'Default'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null
$containerBaseFolder = $null
$projectPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE 

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0080' -parentTelemetryScopeJson $parentTelemetryScopeJson

    # Pull docker image in the background
    $genericImageName = Get-BestGenericImageName
    Start-Job -ScriptBlock {
        docker pull --quiet $genericImageName
    } -ArgumentList $genericImageName | Out-Null

    $containerName = GetContainerName($project)

    $runAlPipelineParams = @{}
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
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl','insiderSasToken','codeSignCertificateUrl','codeSignCertificatePassword','keyVaultCertificateUrl','keyVaultCertificatePassword','keyVaultClientId','storageContext','gitHubPackagesContext','applicationInsightsConnectionString' | ForEach-Object {
        if ($secrets.Keys -contains $_) {
            $value = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }

    $repo = AnalyzeRepo -settings $settings -token $token -baseFolder $baseFolder -project $project -insiderSasToken $insiderSasToken
    if ((-not $repo.appFolders) -and (-not $repo.testFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    if ($repo.type -eq "AppSource App" ) {
        if ($licenseFileUrl -eq "") {
            OutputError -message "When building an AppSource App, you need to create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
            exit
        }
    }

    $artifact = $repo.artifact
    $installApps = $repo.installApps
    $installTestApps = $repo.installTestApps

    Write-Host "Project: $project"
    if ($project -and $repo.useProjectDependencies -and $projectDependenciesJson -ne "") {
        Write-Host "Using project dependencies: $projectDependenciesJson"

        $projectDependencies = $projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
        if ($projectDependencies.Keys -contains $project) {
            $projects = @($projectDependencies."$project") -join ","
        }
        else {
            $projects = ''
        }
        if ($projects) {
            Write-Host "Project dependencies: $projects"
            $thisBuildProbingPaths = @(@{
                "release_status" = "thisBuild"
                "version" = "latest"
                "projects" = $projects
                "repo" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
                "branch" = $ENV:GITHUB_REF_NAME
                "authTokenSecret" = $token
            })
            Get-dependencies -probingPathsJson $thisBuildProbingPaths | where-Object { $_ } | ForEach-Object {
                if ($_.startswith('(')) {
                    $installTestApps += $_    
                }
                else {
                    $installApps += $_    
                }
            }
        }
        else {
            Write-Host "No project dependencies"
        }
    }

    if ($repo.appDependencyProbingPaths) {
        Write-Host "::group::Downloading dependencies"
        Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths | ForEach-Object {
            if ($_.startswith('(')) {
                $installTestApps += $_    
            }
            else {
                $installApps += $_    
            }
        }
        Write-Host "::endgroup::"
    }

    # Analyze app.json version dependencies before launching pipeline

    # Analyze InstallApps and InstallTestApps before launching pipeline

    # Check if insidersastoken is used (and defined)

    if (!$repo.doNotSignApps -and $codeSignCertificateUrl -and $codeSignCertificatePassword) {
        $runAlPipelineParams += @{ 
            "CodeSignCertPfxFile" = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -string $codeSignCertificatePassword -AsPlainText -Force
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
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -string $keyVaultCertificatePassword -AsPlainText -Force
            "keyVaultClientId" = $keyVaultClientId
        }
    }

    $previousApps = @()
    if ($repo.skipUpgrade) {
        OutputWarning -message "Skipping upgrade tests"
    }
    else {
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

    $additionalCountries = $repo.additionalCountries

    $imageName = ""
    if ($repo.gitHubRunner -ne "windows-latest") {
        $imageName = $repo.cacheImageName
        if ($imageName) {
            Write-Host "::group::Flush ContainerHelper Cache"
            Flush-ContainerHelperCache -keepdays $repo.cacheKeepDays
            Write-Host "::endgroup::"
        }
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($repo.versioningStrategy -eq -1) {
        $artifactVersion = [Version]$repo.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif (($repo.versioningStrategy -band 16) -eq 16) {
        $runAlPipelineParams += @{
            "appVersion" = $repo.repoVersion
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

    "containerName=$containerName" | Add-Content $ENV:GITHUB_ENV

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
        if (($repo.configPackages) -or ($repo.Keys | Where-Object { $_ -like 'configPackages.*' })) {
            Write-Host "Adding Import Test Data override"
            Write-Host "Configured config packages:"
            $repo.Keys | Where-Object { $_ -like 'configPackages*' } | ForEach-Object {
                Write-Host "- $($_):"
                $repo."$_" | ForEach-Object {
                    Write-Host "  - $_"
                }
            }
            $runAlPipelineParams += @{
                "ImportTestDataInBcContainer" = {
                    Param([Hashtable]$parameters)
                    $country = Get-BcContainerCountry -containerOrImageName $parameters.containerName
                    $prop = "configPackages.$country"
                    if ($repo.Keys -notcontains $prop) {
                        $prop = "configPackages"
                    }
                    if ($repo."$prop") {
                        Write-Host "Importing config packages from $prop"
                        $repo."$prop" | ForEach-Object {
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
                    $publishParams = @{
                        "containerName" = $parameters.containerName
                        "tenant" = $parameters.tenant
                    }
                    $appid = $_.Split(':')[0]
                    $appName = $_.Split(':')[1]
                    $version = $appName.SubString($appName.LastIndexOf('_')+1)
                    $version = [System.Version]$version.SubString(0,$version.Length-4)
                    if ($parameters.Keys -contains 'CopyInstalledAppsToFolder') {
                        $publishParams += @{
                            "CopyInstalledAppsToFolder" = $parameters.CopyInstalledAppsToFolder
                        }
                    }
                    Publish-BcNuGetPackageToContainer @publishParams -nuGetServerUrl $gitHubPackagesCredential.serverUrl -nuGetToken $gitHubPackagesCredential.token -PackageName "AL-Go-$appId" -version $version -skipVerification
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
        if ($repo."$_") { $runAlPipelineParams += @{ "$_" = $true } }
    }

    switch($buildMode){
        'Clean' {
            $preprocessorsymbols = $repo.cleanModePreprocessorSymbols

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
        -artifact $artifact.replace('{INSIDERSASTOKEN}',$insiderSasToken) `
        -companyName $repo.companyName `
        -memoryLimit $repo.memoryLimit `
        -baseFolder $projectPath `
        -sharedFolder $sharedFolder `
        -licenseFile $licenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -installOnlyReferencedApps:$repo.installOnlyReferencedApps `
        -generateDependencyArtifact:$repo.generateDependencyArtifact `
        -updateDependencies:$repo.updateDependencies `
        -previousApps $previousApps `
        -appFolders $repo.appFolders `
        -testFolders $repo.testFolders `
        -bcptTestFolders $repo.bcptTestFolders `
        -buildOutputFile $buildOutputFile `
        -containerEventLogFile $containerEventLogFile `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -customCodeCops $repo.customCodeCops `
        -gitHubActions `
        -failOn $repo.failOn `
        -treatTestFailuresAsWarnings:$repo.treatTestFailuresAsWarnings `
        -rulesetFile $repo.rulesetFile `
        -appSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -obsoleteTagMinAllowedMajorMinor $repo.obsoleteTagMinAllowedMajorMinor `
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
    OutputError -message "RunPipeline action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
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
    catch {}
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    if ($containerBaseFolder -and (Test-Path $containerBaseFolder) -and $projectPath -and (Test-Path $projectPath)) {
        Write-Host "Removing temp folder"
        Remove-Item -Path (Join-Path $projectPath '*') -Recurse -Force
        Write-Host "Done"
    }
}
