Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"AppBuild":"", "AppRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePassword":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePassword":"","KeyVaultClientId":""}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null

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

    $runAlPipelineParams = @{}
    $environment = 'GitHubActions'
    if ($project  -eq ".") { $project = "" }
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW
    $containerName = GetContainerName($project)

    Write-Host "use settings and secrets"
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision
    'licenseFileUrl','insiderSasToken','CodeSignCertificateUrl','CodeSignCertificatePassword','KeyVaultCertificateUrl','KeyVaultCertificatePassword','KeyVaultClientId' | ForEach-Object {
        if ($secrets.ContainsKey($_)) {
            $value = $secrets."$_"
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }

    $repo = AnalyzeRepo -settings $settings -baseFolder $baseFolder -insiderSasToken $insiderSasToken
    if ((-not $repo.appFolders) -and (-not $repo.testFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    if ($settings.type -eq "AppSource App" ) {
        if ($licenseFileUrl -eq "") {
            OutputError -message "When building an AppSource App, you need to create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
            exit
        }
    }

    $artifact = $repo.artifact
    $installApps = $repo.installApps
    $installTestApps = $repo.installTestApps
    $doNotBuildTests = $repo.doNotBuildTests
    $doNotRunTests = $repo.doNotRunTests

    if ($settings.appDependencyProbingPaths) {
        Write-Host "Downloading dependencies ..."
        $installApps += Get-dependencies -probingPathsJson $settings.appDependencyProbingPaths -token $token
    }
    
    # Analyze app.json version dependencies before launching pipeline

    # Analyze InstallApps and InstallTestApps before launching pipeline

    # Check if insidersastoken is used (and defined)

    if ($CodeSignCertificateUrl -and $CodeSignCertificatePassword) {
        $runAlPipelineParams += @{ 
            "CodeSignCertPfxFile" = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -string $codeSignCertificatePassword -AsPlainText -Force
        }
    }
    if ($KeyVaultCertificateUrl -and $KeyVaultCertificatePassword -and $KeyVaultClientId) {
        $runAlPipelineParams += @{ 
            "KeyVaultCertPfxFile" = $KeyVaultCertificateUrl
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -string $keyVaultCertificatePassword -AsPlainText -Force
            "keyVaultClientId" = $keyVaultClientId
        }
    }

    try {
        $previousApps = @()
        $releasesJson = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        $latestRelease = $releasesJson | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
        if ($latestRelease) {
            Write-Host "Using $($latestRelease.name) as previous release"
            $artifactsFolder = Join-Path $baseFolder "artifacts"
            New-Item $artifactsFolder -ItemType Directory | Out-Null
            DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder
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

    $additionalCountries = $repo.additionalCountries

    $imageName = ""
    if ($repo.gitHubRunner -ne "windows-latest") {
        $imageName = $repo.cacheImageName
        Flush-ContainerHelperCache -keepdays 3
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if (($repo.versioningStrategy -band 16) -eq 16) {
        $runAlPipelineParams += @{
            "appVersion" = $repo.repoVersion
        }
    }
    
    $buildArtifactFolder = Join-Path $baseFolder "output"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

    $allTestResults = "testresults*.xml"
    $testResultsFile = Join-Path $baseFolder "TestResults.xml"
    $testResultsFiles = Join-Path $baseFolder $allTestResults
    if (Test-Path $testResultsFiles) {
        Remove-Item $testResultsFiles -Force
    }
    
    "containerName=$containerName" | Add-Content $ENV:GITHUB_ENV

    Set-Location $baseFolder
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ALGoFolder "$ScriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $scriptName"
            $runAlPipelineParams += @{
                "$scriptName" = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }
    
    Write-Host "Invoke Run-AlPipeline"
    Run-AlPipeline @runAlPipelineParams `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $artifact.replace('{INSIDERSASTOKEN}',$insiderSasToken) `
        -companyName $repo.companyName `
        -memoryLimit $repo.memoryLimit `
        -baseFolder $baseFolder `
        -sharedFolder $sharedFolder `
        -licenseFile $LicenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -previousApps $previousApps `
        -appFolders $repo.appFolders `
        -testFolders $repo.testFolders `
        -doNotBuildTests:$doNotBuildTests `
        -doNotRunTests:$doNotRunTests `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -installTestRunner:$repo.installTestRunner `
        -installTestFramework:$repo.installTestFramework `
        -installTestLibraries:$repo.installTestLibraries `
        -installPerformanceToolkit:$repo.installPerformanceToolkit `
        -enableCodeCop:$repo.enableCodeCop `
        -enableAppSourceCop:$repo.enableAppSourceCop `
        -enablePerTenantExtensionCop:$repo.enablePerTenantExtensionCop `
        -enableUICop:$repo.enableUICop `
        -customCodeCops:$repo.customCodeCops `
        -azureDevOps:($environment -eq 'AzureDevOps') `
        -gitLab:($environment -eq 'GitLab') `
        -gitHubActions:($environment -eq 'GitHubActions') `
        -failOn 'error' `
        -AppSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -buildArtifactFolder $buildArtifactFolder `
        -CreateRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild -appRevision $appRevision `
        -uninstallRemovedApps

        TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
