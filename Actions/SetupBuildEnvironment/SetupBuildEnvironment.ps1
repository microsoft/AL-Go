Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "ArtifactUrl to use", Mandatory = $false)]
    [string] $artifact = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
DownloadAndImportBcContainerHelper

if ($project -eq ".") { $project = "" }
$baseFolder = $ENV:GITHUB_WORKSPACE
$projectPath = Join-Path $baseFolder $project

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
if ($artifact) {
    $settings.artifact = $artifact
}
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting

# Determine if container is needed: we need it for publishing and running tests
if ($settings.doNotPublishApps) {
    Write-Host "doNotPublishApps is set - no build environment needed"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "needsContainer=false"
    return
}

$hasTests = ($settings.testFolders -and $settings.testFolders.Count -gt 0)
$hasBcptTests = ($settings.bcptTestFolders -and $settings.bcptTestFolders.Count -gt 0)
$hasPageScriptingTests = ($settings.pageScriptingTests -and $settings.pageScriptingTests.Count -gt 0)
$needsTestToolkit = $settings.installTestRunner -or $settings.installTestFramework -or $settings.installTestLibraries -or $settings.installPerformanceToolkit

$wantsUnitTests = ($hasTests -or $needsTestToolkit) -and -not $settings.doNotRunTests
$wantsBcptTests = $hasBcptTests -and -not $settings.doNotRunBcptTests
$wantsPageScriptingTests = $hasPageScriptingTests -and -not $settings.doNotRunPageScriptingTests

if (-not ($wantsUnitTests -or $wantsBcptTests -or $wantsPageScriptingTests)) {
    Write-Host "No tests to run - no container needed"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "needsContainer=false"
    return
}

if (-not $isWindows) {
    throw "A container is required for testing but containers are only supported on Windows runners."
}

Assert-DockerIsRunning

$containerName = GetContainerName($project)

# Read secrets
$secrets = if ($env:Secrets) { $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable } else { @{} }

$licenseFileUrl = ""
$keyVaultCertificateUrl = ""
$keyVaultCertificatePassword = ""
$keyVaultClientId = ""
'licenseFileUrl','keyVaultCertificateUrl','keyVaultCertificatePassword','keyVaultClientId' | ForEach-Object {
    if ($secrets.Keys -contains $_) {
        Set-Variable -Name $_ -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_")))
    }
}

# Generate container credentials
$password = [guid]::NewGuid().ToString().Substring(0, 20) + "Ab1!"
Write-Host "::add-mask::$password"
$credential = New-Object pscredential 'admin', (ConvertTo-SecureString -String $password -AsPlainText -Force)

# Determine generic image (WarmupBuildEnvironment already started the pull in background)
$genericImageName = Get-BestGenericImageName
Write-Host "Waiting for docker image $genericImageName (background pull should be in progress)"
docker pull --quiet $genericImageName

# Handle volume mapping for self-hosted runners
$containerBaseFolder = $null
if ($bcContainerHelperConfig.useVolumes -and $bcContainerHelperConfig.hostHelperFolder -eq "HostHelperFolder") {
    $allVolumes = "{$(((docker volume ls --format "'{{.Name}}': '{{.Mountpoint}}'") -join ",").Replace('\','\\').Replace("'",'"'))}" | ConvertFrom-Json | ConvertTo-HashTable
    $containerBaseFolder = Join-Path $allVolumes.hostHelperFolder $containerName
    if (Test-Path $containerBaseFolder) {
        Remove-Item -Path $containerBaseFolder -Recurse -Force
    }
    New-Item -Path $containerBaseFolder -ItemType Directory | Out-Null
    Copy-Item -Path $ENV:GITHUB_WORKSPACE -Destination $containerBaseFolder -Recurse -Force
    $baseFolder = Join-Path $containerBaseFolder (Get-Item -Path $ENV:GITHUB_WORKSPACE).BaseName
    $projectPath = Join-Path $baseFolder $project
}

$sharedFolder = ""
if ($project) {
    $sharedFolder = $baseFolder
}

# Create container
Write-Host "Creating container $containerName"
$newContainerParams = @{
    "accept_eula"          = $true
    "containerName"        = $containerName
    "artifactUrl"          = $settings.artifact.replace('{INSIDERSASTOKEN}','')
    "useGenericImage"      = $genericImageName
    "Credential"           = $credential
    "auth"                 = 'UserPassword'
    "updateHosts"          = $true
    "vsixFile"             = $settings.vsixFile
    "licenseFile"          = $licenseFileUrl
    "EnableTaskScheduler"  = [bool]$settings.enableTaskScheduler
    "AssignPremiumPlan"    = [bool]$settings.assignPremiumPlan
    "additionalParameters" = @("--volume ""$($projectPath):c:\sources""")
}
if ($settings.memoryLimit) {
    $newContainerParams["memoryLimit"] = $settings.memoryLimit
}
if ($sharedFolder) {
    $newContainerParams.additionalParameters += @("--volume ""$($sharedFolder):c:\shared""")
}

# Image cache for self-hosted runners
$gitHubHostedRunner = $settings.gitHubRunner -like "windows-*" -or $settings.gitHubRunner -like "ubuntu-*"
if (-not $gitHubHostedRunner -and $settings.cacheImageName) {
    $newContainerParams["imageName"] = $settings.cacheImageName
    Flush-ContainerHelperCache -cache 'all,exitedcontainers' -keepdays $settings.cacheKeepDays
}

New-BcContainer @newContainerParams
Invoke-ScriptInBcContainer $containerName -scriptblock { $progressPreference = 'SilentlyContinue' }

# KeyVault certificate setup
if ($keyVaultCertificateUrl -and $keyVaultClientId -and $keyVaultCertificatePassword) {
    Write-Host "Setting up KeyVault certificate"
    Set-BcContainerKeyVaultAadAppAndCertificate -containerName $containerName `
        -pfxFile $keyVaultCertificateUrl `
        -pfxPassword (ConvertTo-SecureString -String $keyVaultCertificatePassword -AsPlainText -Force) `
        -clientId $keyVaultClientId
}

# Export state for downstream actions
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "containerName=$containerName"
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "needsContainer=true"
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "containerPassword=$password"
if ($containerBaseFolder) {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "containerBaseFolder=$containerBaseFolder"
}
