Param(
    [string] $actor,
    [string] $token,
    [string] $settingsJson = '{"AppBuild":"";"AppRevision":""}',
    [string] $secretsJson = '{"insiderSasToken":"";"licenseFileUrl":"";"CodeSignCertificateUrl":"";"CodeSignCertificatePassword":"";"KeyVaultCertificateUrl":"";"KeyVaultCertificatePassword":"";"KeyVaultClientId":""}',
    [string] $licenseFileUrl = "",
    [string] $insiderSasToken = "",
    [string] $CodeSignCertificateUrl = "",
    [string] $CodeSignCertificatePw = "",
    [string] $KeyVaultCertificateUrl = "",
    [string] $KeyVaultCertificatePw = "",
    [string] $KeyVaultClientId = "",
    [int] $appBuild = -1,
    [int] $appRevision = -1
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    $runAlPipelineParams = @{}

    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper

    $environment = 'GitHubActions'
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $workflowName = $env:GITHUB_WORKFLOW
    $containerName = "bc$env:GITHUB_RUN_ID"

    if ([int]$appBuild -eq -1 -and [int]$appRevision -eq -1 -and $licenseFileUrl -eq "" -and $codeSignCertificateUrl -eq "" -and $CodeSignCertificatePw -eq "" -and $KeyVaultCertificateUrl -eq "" -and $KeyVaultCertificatePw -eq "" -and $KeyVaultClientId -eq "") {

        Write-Host "use settings and secrets"
        
        $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
        $appBuild = $settings.AppBuild
        $appRevision = $settings.AppRevision

        $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
        'licenseFileUrl','insiderSasToken','CodeSignCertificateUrl','CodeSignCertificatePw','KeyVaultCertificateUrl','KeyVaultCertificatePw','KeyVaultClientId' | ForEach-Object {
            if ($secrets.ContainsKey($_)) {
                $value = $secrets."$_"
            }
            else {
                $value = ""
            }
            Set-Variable -Name $_ -Value $value
        }
    }
    else {
        $settings = ReadSettings -baseFolder $baseFolder -workflowName $workflowName
    }

    $bcContainerHelperConfig.TelemetryConnectionString = "InstrumentationKey=84bd9223-67d4-4378-8590-9e4a46023be2;IngestionEndpoint=https://westeurope-1.in.applicationinsights.azure.com/"
    $bcContainerHelperConfig.UseExtendedTelemetry = $true

    if ($settings.type -eq "AppSource App") {
        if ($licenseFileUrl -eq "") {
            OutputError -message "When building an AppSource App, you need to create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
            exit
        }
    }

    $repo = AnalyzeRepo -settings $settings -insiderSasToken $insiderSasToken -licenseFileUrl $licenseFileUrl

    if (-not $repo.appFolders) {
        exit
    }

    $artifact = $repo.artifact
    $installApps = $repo.installApps
    $installTestApps = $repo.installTestApps
    $doNotRunTests = $repo.doNotRunTests

    # Analyze app.json version dependencies before launching pipeline

    # Analyze InstallApps and InstallTestApps before launching pipeline

    # Check if insidersastoken is used (and defined)

    if ($CodeSignCertificateUrl -and $CodeSignCertificatePw) {
        $runAlPipelineParams += @{ 
            "CodeSignCertPfxFile" = $codeSignCertificateUrl
            "CodeSignCertPfxPassword" = ConvertTo-SecureString -string $codeSignCertificatePw -AsPlainText -Force
        }
    }
    if ($KeyVaultCertificateUrl -and $KeyVaultCertificatePw -and $KeyVaultClientId) {
        $runAlPipelineParams += @{ 
            "KeyVaultCertPfxFile" = $KeyVaultCertificateUrl
            "keyVaultCertPfxPassword" = ConvertTo-SecureString -string $keyVaultCertificatePw -AsPlainText -Force
            "keyVaultClientId" = $keyVaultClientId
        }
    }

    try {
        $appsVersion = [Version]"$($repo.repoVersion).$appBuild.$appRevision"
        $previousApps = @()
        $releasesJson = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        $latestRelease = $releasesJson | Where-Object { ($appsVersion -gt [Version]$_.tag_name) -and (-not ($_.prerelease -or $_.draft)) } | Select-Object -First 1
        if ($latestRelease) {
            Write-Host "Using $($latestRelease.name) as previous release"
            $previousApps += @(DownloadRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease)
        }
        else {
            OutputWarning -message "No previous release to $appsVersion found"
        }
    }
    catch {
        OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
        exit
    }

    $additionalCountries = @()
    
    $imageName = ""
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
        -licenseFile $LicenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -previousApps $previousApps `
        -appFolders $repo.appFolders `
        -testFolders $repo.testFolders `
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
        -azureDevOps:($environment -eq 'AzureDevOps') `
        -gitLab:($environment -eq 'GitLab') `
        -gitHubActions:($environment -eq 'GitHubActions') `
        -failOn 'error' `
        -AppSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
        -AppSourceCopSupportedCountries @() `
        -additionalCountries $additionalCountries `
        -buildArtifactFolder $buildArtifactFolder `
        -CreateRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild -appRevision $appRevision `
        -uninstallRemovedApps
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
