Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Github-Helper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$ALGoFolder = ".AL-Go\"
$ALGoSettingsFile = ".AL-Go\settings.json"
$RepoSettingsFile = ".github\AL-Go-Settings.json"
$defaultCICDPushBranches = @( 'main', 'release/*', 'feature/*' )
$defaultCICDPullRequestBranches = @( 'main' )
$runningLocal = $local.IsPresent

$runAlPipelineOverrides = @(
    "DockerPull"
    "NewBcContainer"
    "ImportTestToolkitToBcContainer"
    "CompileAppInBcContainer"
    "GetBcContainerAppInfo"
    "PublishBcContainerApp"
    "UnPublishBcContainerApp"
    "InstallBcAppFromAppSource"
    "SignBcContainerApp"
    "ImportTestDataInBcContainer"
    "RunTestsInBcContainer"
    "GetBcContainerAppRuntimePackage"
    "RemoveBcContainer"
)

# Well known AppIds
$systemAppId = "63ca2fa4-4f03-4f2b-a480-172fef340d3f"
$baseAppId = "437dbf0e-84ff-417a-965d-ed2bb9650972"
$applicationAppId = "c1335042-3002-4257-bf8a-75c898ccb1b8"
$permissionsMockAppId = "40860557-a18d-42ad-aecb-22b7dd80dc80"
$testRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"
$anyAppId = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
$libraryAssertAppId = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
$libraryVariableStorageAppId = "5095f467-0a01-4b99-99d1-9ff1237d286f"
$systemApplicationTestLibraryAppId = "9856ae4f-d1a7-46ef-89bb-6ef056398228"
$TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
$performanceToolkitAppId = "75f1590f-55c5-4501-ae63-bada5534e852"

$performanceToolkitApps = @($performanceToolkitAppId)
$testLibrariesApps = @($systemApplicationTestLibraryAppId, $TestsTestLibrariesAppId)
$testFrameworkApps = @($anyAppId, $libraryAssertAppId, $libraryVariableStorageAppId) + $testLibrariesApps
$testRunnerApps = @($permissionsMockAppId, $testRunnerAppId) + $performanceToolkitApps + $testLibrariesApps + $testFrameworkApps

$MicrosoftTelemetryConnectionString = "InstrumentationKey=84bd9223-67d4-4378-8590-9e4a46023be2;IngestionEndpoint=https://westeurope-1.in.applicationinsights.azure.com/"

function ConvertTo-HashTable {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    $ht
}

function OutputError {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        throw $message
    }
    else {
        Write-Host "::Error::$($message.Replace("`r",'').Replace("`n",' '))"
        $host.SetShouldExit(1)
    }
}

function OutputWarning {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host -ForegroundColor Yellow "WARNING: $message"
    }
    else {
        Write-Host "::Warning::$message"
    }
}

function MaskValueInLog {
    Param(
        [string] $value
    )

    if (!$runningLocal) {
        Write-Host "::add-mask::$value"
    }
}

function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Debug::$message"
    }
}

function GetUniqueFolderName {
    Param(
        [string] $baseFolder,
        [string] $folderName
    )

    $i = 2
    $name = $folderName
    while (Test-Path (Join-Path $baseFolder $name)) {
        $name = "$folderName($i)"
        $i++
    }
    $name
}

function stringToInt {
    Param(
        [string] $str,
        [int] $default = -1
    )

    $i = 0
    if ([int]::TryParse($str.Trim(), [ref] $i)) { 
        $i
    }
    else {
        $default
    }
}

function Expand-7zipArchive {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [string] $DestinationPath
    )

    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    $use7zip = $false
    if (Test-Path -Path $7zipPath -PathType Leaf) {
        try {
            $use7zip = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($7zipPath).FileMajorPart -ge 19
        }
        catch {
            $use7zip = $false
        }
    }

    if ($use7zip) {
        OutputDebug -message "Using 7zip"
        Set-Alias -Name 7z -Value $7zipPath
        $command = '7z x "{0}" -o"{1}" -aoa -r' -f $Path, $DestinationPath
        Invoke-Expression -Command $command | Out-Null
    }
    else {
        OutputDebug -message "Using Expand-Archive"
        Expand-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
    }
}

function DownloadAndImportBcContainerHelper {
    Param(
        [string] $BcContainerHelperVersion = "",
        [string] $baseFolder = ""
    )

    $params = @{ "ExportTelemetryFunctions" = $true }
    if ($baseFolder) {
        $repoSettingsPath = Join-Path $baseFolder $repoSettingsFile
        if (-not (Test-Path $repoSettingsPath -PathType Leaf)) {
            $repoSettingsPath = Join-Path $baseFolder "..\$repoSettingsFile"
            if (-not (Test-Path $repoSettingsPath -PathType Leaf)) {
                $repoSettingsPath = Join-Path $baseFolder "..\..\$repoSettingsFile"
            }
        }
        if (Test-Path $repoSettingsPath) {
            if (-not $BcContainerHelperVersion) {
                $repoSettings = Get-Content $repoSettingsPath -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
                $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
                if ($ap -and $ap.Count -gt 4) {
                    $branch = $ap[$ap.Count-2]
                    $owner = $ap[$ap.Count-4]
                    if ($owner -eq "freddydk") {
                        $bcContainerHelperVersion = "dev"
                    }
                    elseif ($owner -eq "businesscentralapps") {
                        $bcContainerHelperVersion = "preview"
                    }
                    elseif ($owner -eq "microsoft" -and $branch -eq "preview") {
                        $bcContainerHelperVersion = "preview"
                    }
                }
                if ($bcContainerHelperVersion -eq "" -and $repoSettings.ContainsKey("BcContainerHelperVersion")) {
                    $BcContainerHelperVersion = $repoSettings.BcContainerHelperVersion
                }
            }
            $params += @{ "bcContainerHelperConfigFile" = $repoSettingsPath }
        }
    }
    if (-not $BcContainerHelperVersion) {
        $BcContainerHelperVersion = "latest"
    }

    if ($bcContainerHelperVersion -eq "none") {
        $tempName = ""
        $module = Get-Module BcContainerHelper
        if (-not $module) {
            OutputError "When setting BcContainerHelperVersion to none, you need to ensure that BcContainerHelper is installed on the build agent"
        }

        $BcContainerHelperPath = Join-Path (Split-Path $module.Path -parent) "BcContainerHelper.ps1" -Resolve
    }
    else {
        $tempName = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
        $webclient = New-Object System.Net.WebClient
        if ($BcContainerHelperVersion -eq "dev") {
            Write-Host "Downloading BcContainerHelper developer version"
            $webclient.DownloadFile("https://github.com/microsoft/navcontainerhelper/archive/dev.zip", "$tempName.zip")
        }
        else {
            Write-Host "Downloading BcContainerHelper $BcContainerHelperVersion version"
            try {
                $webclient.DownloadFile("https://bccontainerhelper.azureedge.net/public/$($BcContainerHelperVersion).zip", "$tempName.zip")
            }
            catch {
                $webclient.DownloadFile("https://bccontainerhelper.blob.core.windows.net/public/$($BcContainerHelperVersion).zip", "$tempName.zip")        
            }
        }
        Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
        Remove-Item -Path "$tempName.zip"

        $BcContainerHelperPath = (Get-Item -Path (Join-Path $tempName "*\BcContainerHelper.ps1")).FullName
    }
    . $BcContainerHelperPath @params
    $tempName
}

function CleanupAfterBcContainerHelper {
    Param(
        [string] $bcContainerHelperPath
    )

    if ($bcContainerHelperPath) {
        try {
            Write-Host "Removing BcContainerHelper"
            Remove-Module BcContainerHelper
            Remove-Item $bcContainerHelperPath -Recurse -Force
        }
        catch {}
    }
}

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # Add missing properties in OrderedDictionary

    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name
        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType) {
                throw "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | ForEach-Object { $ht[$_.Name] = $_.Value }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            $dst."$prop" += $srcElm
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}

function ReadSettings {
    Param(
        [string] $baseFolder,
        [string] $repoName = "$env:GITHUB_REPOSITORY",
        [string] $workflowName = "",
        [string] $userName = ""
    )

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    
    # Read Settings file
    $settings = [ordered]@{
        "type"                                   = "PTE"
        "country"                                = "us"
        "artifact"                               = ""
        "companyName"                            = ""
        "repoVersion"                            = "1.0"
        "repoName"                               = $repoName
        "versioningStrategy"                     = 0
        "runNumberOffset"                        = 0
        "appBuild"                               = 0
        "appRevision"                            = 0
        "keyVaultName"                           = ""
        "licenseFileUrlSecretName"               = "LicenseFileUrl"
        "insiderSasTokenSecretName"              = "InsiderSasToken"
        "ghTokenWorkflowSecretName"              = "GhTokenWorkflow"
        "adminCenterApiCredentialsSecretName"    = "AdminCenterApiCredentials"
        "applicationInsightsConnectionStringSecretName" = "ApplicationInsightsConnectionString"
        "keyVaultCertificateUrlSecretName"       = ""
        "keyVaultCertificatePasswordSecretName"  = ""
        "keyVaultClientIdSecretName"             = ""
        "codeSignCertificateUrlSecretName"       = "CodeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"  = "CodeSignCertificatePassword"
        "storageContextSecretName"               = "StorageContext"
        "additionalCountries"                    = @()
        "appDependencies"                        = @()
        "appFolders"                             = @()
        "testDependencies"                       = @()
        "testFolders"                            = @()
        "bcptTestFolders"                        = @()
        "installApps"                            = @()
        "installTestApps"                        = @()
        "installOnlyReferencedApps"              = $true
        "generateDependencyArtifact"             = $false
        "skipUpgrade"                            = $false
        "applicationDependency"                  = "18.0.0.0"
        "updateDependencies"                     = $false
        "installTestRunner"                      = $false
        "installTestFramework"                   = $false
        "installTestLibraries"                   = $false
        "installPerformanceToolkit"              = $false
        "enableCodeCop"                          = $false
        "enableUICop"                            = $false
        "customCodeCops"                         = @()
        "failOn"                                 = "error"
        "rulesetFile"                            = ""
        "doNotBuildTests"                        = $false
        "doNotRunTests"                          = $false
        "doNotRunBcptTests"                      = $false
        "doNotPublishApps"                       = $false
        "doNotSignApps"                          = $false
        "appSourceCopMandatoryAffixes"           = @()
        "obsoleteTagMinAllowedMajorMinor"        = ""
        "memoryLimit"                            = ""
        "templateUrl"                            = ""
        "templateBranch"                         = ""
        "appDependencyProbingPaths"              = @()
        "runs-on"                                = "windows-latest"
        "githubRunner"                           = ""
        "cacheImageName"                         = "my"
        "cacheKeepDays"                          = 3
        "alwaysBuildAllProjects"                 = $false
        "MicrosoftTelemetryConnectionString"     = $MicrosoftTelemetryConnectionString
        "PartnerTelemetryConnectionString"       = ""
        "SendExtendedTelemetryToMicrosoft"       = $false
        "Environments"                           = @()
    }
    $gitHubFolder = ".github"
    $repoSettingsPath = $RepoSettingsFile
    if (-not (Test-Path (Join-Path $baseFolder $repoSettingsPath) -PathType Leaf)) {
        $RepoSettingsPath = "..\$RepoSettingsPath"
        $gitHubFolder = "..\$gitHubFolder"
        if (-not (Test-Path (Join-Path $baseFolder $RepoSettingsPath) -PathType Leaf)) {
            $RepoSettingsPath = "..\$RepoSettingsPath"
            $gitHubFolder = "..\$gitHubFolder"
        }
    }

    $workflowName = $workflowName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $RepoSettingsPath, $ALGoSettingsFile, (Join-Path $gitHubFolder "$workflowName.settings.json"), (Join-Path $ALGoFolder "$workflowName.settings.json"), (Join-Path $ALGoFolder "$userName.settings.json") | ForEach-Object {
        $settingsFile = $_
        $settingsPath = Join-Path $baseFolder $settingsFile
        if (Test-Path $settingsPath) {
            try {
                Write-Host "Reading $settingsFile"
                $settingsJson = Get-Content $settingsPath -Encoding UTF8 | ConvertFrom-Json
       
                # check settingsJson.version and do modifications if needed
         
                MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson

                if ($settingsJson.PSObject.Properties.Name -eq "ConditionalSettings") {
                    $settingsJson.ConditionalSettings | ForEach-Object {
                        $conditionalSetting = $_
                        if ($conditionalSetting.branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }) {
                            Write-Host "Applying conditional settings for $ENV:GITHUB_REF_NAME"
                            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $conditionalSetting.settings
                        }
                    }
                }
            }
            catch {
                throw "Settings file $settingsFile, is wrongly formatted. Error is $($_.Exception.Message)."
            }
        }
    }

    if ($settings.githubRunner -eq "") {
        $settings.githubRunner = $settings."runs-on"
    }
    $settings
}

function ExcludeUnneededApps {
    Param(
        [string[]] $folders,
        [string[]] $includeOnlyAppIds,
        [hashtable] $appIdFolders
    )

    $folders | ForEach-Object {
        $folder = $_
        if ($includeOnlyAppIds.Contains(($appIdFolders.GetEnumerator() | Where-Object { $_.Value -eq $folder }).Key)) {
            $folder
        }
    }
}

function AnalyzeRepo {
    Param(
        [hashTable] $settings,
        $token,
        [string] $baseFolder,
        [string] $project,
        [string] $insiderSasToken,
        [switch] $doNotCheckArtifactSetting,
        [switch] $doNotIssueWarnings,
        [string[]] $includeOnlyAppIds,
        [string] $server_url = $ENV:GITHUB_SERVER_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    if (!$runningLocal) {
        Write-Host "::group::Analyzing repository"
    }

    $projectPath = Join-Path $baseFolder $project -Resolve
    Set-Location $projectPath

    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null

    Write-Host "Checking type"
    if ($settings.type -eq "PTE") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $true)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $false)
        }
    }
    elseif ($settings.type -eq "AppSource App" ) {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $false)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $true)
        }
        if ($settings.enableAppSourceCop -and (-not ($settings.appSourceCopMandatoryAffixes))) {
            throw "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $ALGoSettingsFile"
        }
    }
    else {
        throw "The type, specified in $ALGoSettingsFile, must be either 'Per Tenant Extension' or 'AppSource App'. It is '$($settings.type)'."
    }

    if (-not (@($settings.appFolders)+@($settings.testFolders)+@($settings.bcptTestFolders))) {
        Get-ChildItem -Path $projectPath -Directory | Where-Object { Test-Path -Path (Join-Path $_.FullName "app.json") } | ForEach-Object {
            $folder = $_
            $appJson = Get-Content (Join-Path $folder.FullName "app.json") -Encoding UTF8 | ConvertFrom-Json
            $isTestApp = $false
            $isBcptTestApp = $false
            if ($appJson.PSObject.Properties.Name -eq "dependencies") {
                $appJson.dependencies | ForEach-Object {
                    if ($_.PSObject.Properties.Name -eq "AppId") {
                        $id = $_.AppId
                    }
                    else {
                        $id = $_.Id
                    }
                    if ($performanceToolkitApps.Contains($id)) { 
                        $isBcptTestApp = $true
                    }
                    elseif ($testRunnerApps.Contains($id)) { 
                        $isTestApp = $true
                    }
                }
            }
            if ($isBcptTestApp) {
                $settings.bcptTestFolders += @($_.Name)
            }
            elseif ($isTestApp) {
                $settings.testFolders += @($_.Name)
            }
            else {
                $settings.appFolders += @($_.Name)
            }
        }
    }

    Write-Host "Checking appFolders and testFolders"
    $dependencies = [ordered]@{}
    $appIdFolders = [ordered]@{}
    1..3 | ForEach-Object {
        $appFolder = $_ -eq 1
        $testFolder = $_ -eq 2
        $bcptTestFolder = $_ -eq 3
        if ($appFolder) {
            $folders = @($settings.appFolders)
            $descr = "App folder"
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
            $descr = "Test folder"
        }
        elseif ($bcptTestFolder) {
            $folders = @($settings.bcptTestFolders)
            $descr = "Bcpt Test folder"
        }
        else {
            throw "Internal error"
        }
        $folders | ForEach-Object {
            $folderName = $_
            $folder = Join-Path $projectPath $folderName
            $appJsonFile = Join-Path $folder "app.json"
            $bcptSuiteFile = Join-Path $folder "bcptSuite.json"
            $enumerate = $true
            if (-not (Test-Path $folder -PathType Container)) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $ALGoSettingsFile, does not exist" }
            }
            elseif (-not (Test-Path $appJsonFile -PathType Leaf)) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $ALGoSettingsFile, does not contain the source code for an app (no app.json file)" }
            }
            elseif ($bcptTestFolder -and (-not (Test-Path $bcptSuiteFile -PathType Leaf))) {
                if (!$doNotIssueWarnings) { OutputWarning -message "$descr $folderName, specified in $ALGoSettingsFile, does not contain a BCPT Suite (bcptSuite.json)" }
                $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName })
                $enumerate = $false
            }
            if ($enumerate) {
                $expandFolders = @(Get-Item $appJsonFile -ErrorAction SilentlyContinue | ForEach-Object { Resolve-Path -Relative $_.Directory })
                if ($appFolder) {
                    $settings.appFolders = @($settings.appFolders | Where-Object { $_ -ne $folderName }) + $expandFolders
                }
                elseif ($testFolder) {
                    $settings.testFolders = @($settings.testFolders | Where-Object { $_ -ne $folderName }) + $expandFolders
                }
                elseif ($bcptTestFolder) {
                    $settings.bcptTestFolders = @($settings.bcptTestFolders | Where-Object { $_ -ne $folderName }) + $expandFolders
                }
                $expandFolders | ForEach-Object {
                    $folderName = $_
                    $folder = Join-Path $projectPath $folderName
                    $appJsonFile = Join-Path $folder "app.json"
                    if ($dependencies.Contains($folderName)) {
                        throw "$descr $folderName, specified in $ALGoSettingsFile, is specified more than once."
                    }
                    $dependencies.Add($folderName, @())
                    try {
                        $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                        if ($appIdFolders.Contains($appJson.Id)) {
                            throw "$descr $folderName contains a duplicate AppId ($($appIdFolders."$appJson.Id"))"
                        }
                        $appIdFolders.Add($appJson.Id, $folderName)
                        if ($appJson.PSObject.Properties.Name -eq 'Dependencies') {
                            $appJson.dependencies | ForEach-Object {
                                if ($_.PSObject.Properties.Name -eq "AppId") {
                                    $id = $_.AppId
                                }
                                else {
                                    $id = $_.Id
                                }
                                if ($id -eq $applicationAppId) {
                                    if ([Version]$_.Version -gt [Version]$settings.applicationDependency) {
                                        $settings.applicationDependency = $appDep
                                    }
                                }
                                else {
                                    $dependencies."$folderName" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
                                }
                            }
                        }
                        if ($appJson.PSObject.Properties.Name -eq 'Application') {
                            $appDep = $appJson.application
                            if ([Version]$appDep -gt [Version]$settings.applicationDependency) {
                                $settings.applicationDependency = $appDep
                            }
                        }
                    }
                    catch {
                        throw "$descr $folderName, specified in $ALGoSettingsFile, contains a corrupt app.json file. Error is $($_.Exception.Message)."
                    }
                }
            }
        }
    }
    Write-Host "Application Dependency $($settings.applicationDependency)"

    if ($includeOnlyAppIds) {
        $i = 0
        while ($i -lt $includeOnlyAppIds.Count) {
            $id = $includeOnlyAppIds[$i]
            if ($appIdFolders.Contains($id)) {
                $dependencies."$($appIdFolders."$id")" | ForEach-Object {
                    $includeOnlyAppIds += @($_.Id)
                }
            }
            $i++
        }

        $settings.appFolders = @(ExcludeUnneededApps -folders $settings.appFolders -includeOnlyAppIds $includeOnlyAppIds -appIdFolders $appIdFolders)
        $settings.testFolders = @(ExcludeUnneededApps -folders $settings.testFolders -includeOnlyAppIds $includeOnlyAppIds -appIdFolders $appIdFolders)
        $settings.bcptTestFolders = @(ExcludeUnneededApps -folders $settings.bcptTestFolders -includeOnlyAppIds $includeOnlyAppIds -appIdFolders $appIdFolders)
    }

    if (!$doNotCheckArtifactSetting) {
        $artifact = $settings.artifact
        if ($artifact.Contains('{INSIDERSASTOKEN}')) {
            if ($insiderSasToken) {
                $artifact = $artifact.replace('{INSIDERSASTOKEN}', $insiderSasToken)
            }
            else {
                throw "Artifact definition $artifact requires you to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
            }
        }

        Write-Host "Checking artifact setting"
        if ($artifact -eq "" -and $settings.updateDependencies) {
            $artifact = Get-BCArtifactUrl -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
            if (-not $artifact) {
                if ($insiderSasToken) {
                    $artifact = Get-BCArtifactUrl -storageAccount bcinsider -country $settings.country -select all -sasToken $insiderSasToken | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
                    if (-not $artifact) {
                        throw "No artifacts found for application dependency $($settings.applicationDependency)."
                    }
                }
                else {
                    throw "No artifacts found for application dependency $($settings.applicationDependency). If you are targetting an insider version, you need to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
                }
            }
        }
        
        if ($artifact -like "https://*") {
            $artifactUrl = $artifact
            $storageAccount = ("$artifactUrl////".Split('/')[2]).Split('.')[0]
            $artifactType = ("$artifactUrl////".Split('/')[3])
            $version = ("$artifactUrl////".Split('/')[4])
            $country = ("$artifactUrl////".Split('/')[5])
            $sasToken = "$($artifactUrl)?".Split('?')[1]
        }
        else {
            $segments = "$artifact/////".Split('/')
            $storageAccount = $segments[0];
            $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
            $version = $segments[2]
            $country = $segments[3]; if ($country -eq "") { $country = $settings.country }
            $select = $segments[4]; if ($select -eq "") { $select = "latest" }
            $sasToken = $segments[5]
            $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -sasToken $sasToken | Select-Object -First 1
            if (-not $artifactUrl) {
                throw "No artifacts found for the artifact setting ($artifact) in $ALGoSettingsFile"
            }
            $version = $artifactUrl.Split('/')[4]
            $storageAccount = $artifactUrl.Split('/')[2]
        }
    
        if ($settings.additionalCountries -or $country -ne $settings.country) {
            if ($country -ne $settings.country -and !$doNotIssueWarnings) {
                OutputWarning -message "artifact definition in $ALGoSettingsFile uses a different country ($country) than the country definition ($($settings.country))"
            }
            Write-Host "Checking Country and additionalCountries"
            # AT is the latest published language - use this to determine available country codes (combined with mapping)
            $ver = [Version]$version
            Write-Host "https://$storageAccount/$artifactType/$version/$country"
            $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -sasToken $sasToken
            Write-Host "Latest AT artifacts $atArtifactUrl"
            $latestATversion = $atArtifactUrl.Split('/')[4]
            $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -sasToken $sasToken -select All | ForEach-Object { 
                $countryArtifactUrl = $_.Split('?')[0] # remove sas token
                $countryArtifactUrl.Split('/')[5] # get country
            }
            Write-Host "Countries with artifacts $($countries -join ',')"
            $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
            Write-Host "Allowed Country codes $($allowedCountries -join ',')"
            if ($allowedCountries -notcontains $settings.country) {
                throw "Country ($($settings.country)), specified in $ALGoSettingsFile is not a valid country code."
            }
            $illegalCountries = $settings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
            if ($illegalCountries) {
                throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $ALGoSettingsFile."
            }
            $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4],$atArtifactUrl.Split('/')[4])
        }
        else {
            Write-Host "Downloading artifacts from $($artifactUrl.Split('?')[0])"
            $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
            if (-not ($folders)) {
                throw "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $ALGoSettingsFile."
            }
        }
        $settings.artifact = $artifactUrl

        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            throw "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }

    # unpack all dependencies and update app- and test dependencies from dependency apps
    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        if ($dep -is [string]) {
            # TODO: handle pre-settings - documentation pending
        }
    }

    Write-Host "Updating app- and test Dependencies"
    $dependencies.Keys | ForEach-Object {
        $folderName = $_
        $appFolder = $settings.appFolders.Contains($folderName)
        if ($appFolder) { $prop = "appDependencies" } else { $prop = "testDependencies" }
        $dependencies."$_" | ForEach-Object {
            $id = $_.Id
            $version = $_.version
            $exists = $settings."$prop" | Where-Object { $_ -is [System.Collections.Specialized.OrderedDictionary] -and $_.id -eq $id }
            if ($exists) {
                if ([Version]$version -gt [Version]$exists.Version) {
                    $exists.Version = $version
                }
            }
            else {
                $settings."$prop" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
            }
        }
    }

    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        if ($dep.GetType().Name -eq "OrderedDictionary") {
            if ($testRunnerApps.Contains($dep.id)) { $settings.installTestRunner = $true }
            if ($testFrameworkApps.Contains($dep.id)) { $settings.installTestFramework = $true }
            if ($testLibrariesApps.Contains($dep.id)) { $settings.installTestLibraries = $true }
            if ($performanceToolkitApps.Contains($dep.id)) { $settings.installPerformanceToolkit = $true }
        }
    }

    if (!$runningLocal) {
        Write-Host "::endgroup::"
    }

    Write-Host "Checking appDependencyProbingPaths"
    if ($settings.appDependencyProbingPaths) {
        $settings.appDependencyProbingPaths = @($settings.appDependencyProbingPaths | ForEach-Object {
            if ($_.GetType().Name -eq "PSCustomObject") {
                $_
            } 
            else { 
                New-Object -Type PSObject -Property $_
            } 
        })
        $settings.appDependencyProbingPaths | ForEach-Object {
            $dependency = $_
            if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
                throw "AppDependencyProbingPaths needs to contain a repo property, pointing to the repository on which you have a dependency"
            }
            if ($dependency.Repo -eq ".") {
                $dependency.Repo = "$server_url/$repository"
            }
            elseif ($dependency.Repo -notlike "https://*") {
                $dependency.Repo = "$server_url/$($dependency.Repo)"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
                $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "Projects")) {
                $dependency | Add-Member -name "Projects" -MemberType NoteProperty -Value "*"
            }
            elseif ([String]::IsNullOrEmpty($dependency.Projects)) {
                $dependency.Projects = '*'
            }
            if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
                $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "release"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "branch")) {
                $dependency | Add-Member -name "branch" -MemberType NoteProperty -Value "main"
            }
            Write-Host "Dependency to projects '$($dependency.Projects)' in $($dependency.Repo)@$($dependency.branch), version $($dependency.version), release status $($dependency.release_status)"
            if (-not ($dependency.PsObject.Properties.name -eq "AuthTokenSecret")) {
                if ($token) {
                    Write-Host "Using token as AuthTokenSecret"
                }
                else {
                    Write-Host "No token available, will attempt to invoke gh auth status --show-token to get access to repository"
                }
                $dependency | Add-Member -name "AuthTokenSecret" -MemberType NoteProperty -Value $token
            }
            if (-not ($dependency.PsObject.Properties.name -eq "alwaysIncludeApps")) {
                $dependency | Add-Member -name "alwaysIncludeApps" -MemberType NoteProperty -Value @()
            }
            elseif ($dependency.alwaysIncludeApps -is [string]) {
                $dependency.alwaysIncludeApps = $dependency.alwaysIncludeApps.Split(' ')
            }
            if ($dependency.alwaysIncludeApps) {
                Write-Host "Always including apps: $($dependency.alwaysIncludeApps -join ", ")"
            }

            if ($dependency.release_status -eq "include") {
                if ($dependency.Repo -ne "$server_url/$repository") {
                    OutputWarning "Dependencies with release_status 'include' must be to other projects in the same repository."
                }
                else {
                    $dependency.Projects.Split(',') | ForEach-Object {
                        if ($_ -eq '*') {
                            OutputWarning "Dependencies to the same repository cannot specify all projects (*)"
                        }
                        else {
                            $depProject = $_
                            Write-Host "Identified dependency to project $depProject in the same repository"

                            $dependencyIds = @( @($settings.appDependencies + $settings.testDependencies) | ForEach-Object { $_.id })
                            $depProjectPath = Join-Path $baseFolder $depProject
                            $depSettings = ReadSettings -baseFolder $depProjectPath -workflowName "CI/CD"

                            $depSettings = AnalyzeRepo -settings $depSettings -token $token -baseFolder $baseFolder -project $depProject -includeOnlyAppIds @($dependencyIds + $includeOnlyAppIds + $dependency.alwaysIncludeApps) -doNotIssueWarnings -doNotCheckArtifactSetting -server_url $server_url -repository $repository

                            Set-Location $projectPath
                            "appFolders","testFolders" | ForEach-Object {
                                $propertyName = $_
                                Write-Host "Adding folders from $depProject to $_"
                                $found = $true
                                $depSettings."$propertyName" | ForEach-Object {
                                    $folder = (Resolve-Path -Path (Join-Path $depProjectPath $_) -Relative).ToLowerInvariant()
                                    if (!$settings."$propertyName".Contains($folder)) {
                                        $settings."$propertyName" += @($folder)
                                        $found = $true
                                        Write-Host "- $folder"
                                    }
                                }
                                if (!$found) { Write-Host "- No folders added" }
                            }
                        }
                    }
                }
            }
        }
    }

    if (!$settings.doNotRunBcptTests -and -not $settings.bcptTestFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No performance test apps found in bcptTestFolders in $ALGoSettingsFile" }
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and -not $settings.testFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No test apps found in testFolders in $ALGoSettingsFile" }
        $settings.doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No apps found in appFolders in $ALGoSettingsFile" }
    }

    $settings
}

function Get-ProjectFolders {
    Param(
        [string] $baseFolder,
        [string] $project,
        [switch] $includeALGoFolder,
        [string[]] $includeOnlyAppIds,
        [string] $server_url = $ENV:GITHUB_SERVER_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        $token
    )

    Write-Host "Analyzing project $project"
    if ($includeOnlyAppIds) {
        $systemAppId, $baseAppId, $applicationAppId | ForEach-Object {
            if (!$includeOnlyAppIds.Contains($_)) { $includeOnlyAppIds += @($_)}
        }
    }

    $projectFolders = @()
    $projectPath = Join-Path $baseFolder $project
    $settings = ReadSettings -baseFolder $projectPath -workflowName "CI/CD"
    $settings = AnalyzeRepo -settings $settings -token $token -baseFolder $baseFolder -project $project -includeOnlyAppIds $includeOnlyAppIds -doNotIssueWarnings -doNotCheckArtifactSetting -server_url $server_url -repository $repository
    $AlGoFolderArr = @()
    if ($includeALGoFolder) { $AlGoFolderArr = @(".AL-Go") }
    Set-Location $baseFolder
    @($settings.appFolders + $settings.testFolders + $settings.bcptTestFolders + $AlGoFolderArr) | ForEach-Object {
        $fullPath = Join-Path $projectPath $_ -Resolve
        $relativePath = Resolve-Path -Path $fullPath -Relative
        $folder = $relativePath.Substring(2).Replace('\','/').ToLowerInvariant()
        if ($includeOnlyAppIds) {
            $appJsonFile = Join-Path $fullPath 'app.json'
            if (Test-Path $appJsonFile) {
                $appJson = Get-Content -Path $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                if ($includeOnlyAppIds.Contains($appJson.Id) -and !$projectFolders.contains($folder)) {
                    $projectFolders += @($folder)
                }
            }
        }
        else {
            $projectFolders += @($folder)
        }
    }

    Write-Host "Project $project folders:"
    $projectFolders | ForEach-Object { Write-Host "- $_" }
    $projectFolders
}

function installModules {
    Param(
        [String[]] $modules
    )

    $modules | ForEach-Object {
        if (-not (get-installedmodule -Name $_ -ErrorAction SilentlyContinue)) {
            Write-Host "Installing module $_"
            Install-Module $_ -Force | Out-Null
        }
    }
    $modules | ForEach-Object { 
        Write-Host "Importing module $_"
        Import-Module $_ -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
    }
}

function CloneIntoNewFolder {
    Param(
        [string] $actor,
        [string] $token,
        [string] $branch
    )

    $baseFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item $baseFolder -ItemType Directory | Out-Null
    Set-Location $baseFolder
    $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
    $serverUrl = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

    # Environment variables for hub commands
    $env:GITHUB_USER = $actor
    $env:GITHUB_TOKEN = $token

    # Configure git username and email
    invoke-git config --global user.email "$actor@users.noreply.github.com"
    invoke-git config --global user.name "$actor"

    # Configure hub to use https
    invoke-git config --global hub.protocol https

    invoke-git clone $serverUrl

    Set-Location *

    if ($branch) {
        invoke-git checkout -b $branch
    }

    $serverUrl
}

function CommitFromNewFolder {
    Param(
        [string] $serverUrl,
        [string] $commitMessage,
        [string] $branch
    )

    invoke-git add *
    if ($commitMessage.Length -gt 250) {
        $commitMessage = "$($commitMessage.Substring(0,250))...)"
    }
    invoke-git commit --allow-empty -m "'$commitMessage'"
    if ($branch) {
        invoke-git push -u $serverUrl $branch
        invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY
    }
    else {
        invoke-git push $serverUrl
    }
}

function Select-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$true)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-"*$title.Length)
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $offset = 0
    $keys = @()
    $values = @()

    $options.GetEnumerator() | ForEach-Object {
        Write-Host -ForegroundColor Yellow "$([char]($offset+97)) " -NoNewline
        $keys += @($_.Key)
        $values += @($_.Value)
        if ($_.Key -eq $default) {
            Write-Host -ForegroundColor Yellow $_.Value
            $defaultAnswer = $offset
        }
        else {
            Write-Host $_.Value
        }
        $offset++     
    }
    Write-Host
    $answer = -1
    do {
        Write-Host "$question " -NoNewline
        if ($defaultAnswer -ge 0) {
            Write-Host "(default $([char]($defaultAnswer + 97))) " -NoNewline
        }
        $selection = (Read-Host).ToLowerInvariant()
        if ($selection -eq "") {
            if ($defaultAnswer -ge 0) {
                $answer = $defaultAnswer
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. " -NoNewline
            }
        }
        else {
            if (($selection.Length -ne 1) -or (([int][char]($selection)) -lt 97 -or ([int][char]($selection)) -ge (97+$offset))) {
                Write-Host -ForegroundColor Red "Illegal answer. " -NoNewline
            }
            else {
                $answer = ([int][char]($selection))-97
            }
        }
        if ($answer -eq -1) {
            if ($offset -eq 2) {
                Write-Host -ForegroundColor Red "Please answer one letter, a or b"
            }
            else {
                Write-Host -ForegroundColor Red "Please answer one letter, from a to $([char]($offset+97-1))"
            }
        }
    } while ($answer -eq -1)

    Write-Host -ForegroundColor Green "$($values[$answer]) selected"
    Write-Host
    $keys[$answer]
}

function Enter-Value {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $title,
        [Parameter(Mandatory=$false)]
        [string] $description,
        [Parameter(Mandatory=$false)]
        $options,
        [Parameter(Mandatory=$false)]
        [string] $default = "",
        [Parameter(Mandatory=$true)]
        [string] $question,
        [switch] $doNotConvertToLower,
        [switch] $previousStep
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-"*$title.Length)
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $answer = ""
    do {
        Write-Host "$question " -NoNewline
        if ($options) {
            Write-Host "($([string]::Join(', ', $options))) " -NoNewline
        }
        if ($default) {
            Write-Host "(default $default) " -NoNewline
        }
        if ($doNotConvertToLower) {
            $selection = Read-Host
        }
        else {
            $selection = (Read-Host).ToLowerInvariant()
        }
        if ($selection -eq "") {
            if ($default) {
                $answer = $default
            }
            else {
                Write-Host -ForegroundColor Red "No default value exists. "
            }
        }
        else {
            if ($options) {
                $answer = $options | Where-Object { $_ -like "$selection*" }
                if (-not ($answer)) {
                    Write-Host -ForegroundColor Red "Illegal answer. Please answer one of the options."
                }
                elseif ($answer -is [Array]) {
                    Write-Host -ForegroundColor Red "Multiple options match the answer. Please answer one of the options that matched the previous selection."
                    $options = $answer
                    $answer = $null
                }
            }
            else {
                $answer = $selection
            }
        }
    } while (-not ($answer))

    Write-Host -ForegroundColor Green "$answer selected"
    Write-Host
    $answer
}

function OptionallyConvertFromBase64 {
    Param(
        [string] $value
    )

    if ($value.StartsWith('::') -and $value.EndsWith('::')) {
        if ($value.Length -eq 4) {
            ""
        }
        else {
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($value.Substring(2, $value.Length-4)))
        }
    }
}

function GetContainerName([string] $project) {
    "bc$($project -replace "\W")$env:GITHUB_RUN_ID"
}

function CreateDevEnv {
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('local','cloud')]
        [string] $kind,
        [ValidateSet('local','GitHubActions')]
        [string] $caller = 'local',
        [Parameter(Mandatory=$true)]
        [string] $baseFolder,
        [string] $userName = $env:Username,
        [string] $bcContainerHelperPath = "",

        [Parameter(ParameterSetName='cloud')]
        [Hashtable] $bcAuthContext = $null,
        [Parameter(ParameterSetName='cloud')]
        [Hashtable] $adminCenterApiCredentials = @{},
        [Parameter(Mandatory=$true, ParameterSetName='cloud')]
        [string] $environmentName,
        [Parameter(ParameterSetName='cloud')]
        [switch] $reuseExistingEnvironment,

        [Parameter(Mandatory=$true, ParameterSetName='local')]
        [ValidateSet('Windows','UserPassword')]
        [string] $auth,
        [Parameter(Mandatory=$true, ParameterSetName='local')]
        [pscredential] $credential,
        [Parameter(ParameterSetName='local')]
        [string] $containerName = "",
        [string] $insiderSasToken = "",
        [string] $LicenseFileUrl = ""
    )

    if ($PSCmdlet.ParameterSetName -ne $kind) {
        throw "Specified parameters doesn't match kind=$kind"
    }

    $dependenciesFolder = Join-Path $baseFolder ".dependencies"
    $runAlPipelineParams = @{}
    $loadBcContainerHelper = ($bcContainerHelperPath -eq "")
    if ($loadBcContainerHelper) {
        $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder
    }
    try {
        if ($caller -eq "local") {
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Check-BcContainerHelperPermissions -silent -fix
            }
        }

        $workflowName = "$($kind)DevEnv"
        $params = @{
            "baseFolder" = $baseFolder
            "project" = "."
            "workflowName" = $workflowName
        }
        if ($caller -eq "local") { $params += @{ "userName" = $userName } }
        $settings = ReadSettings @params
    
        if ($caller -eq "GitHubActions") {
            if ($kind -ne "cloud") {
                OutputError -message "Unexpected. kind=$kind, caller=$caller"
                exit
            }
            if ($adminCenterApiCredentials.Keys.Count -eq 0) {
                OutputError -message "You need to add a secret called AdminCenterApiCredentials containing authentication for the admin Center API."
                exit
            }
        }
        else {
            if ($settings.Contains("appDependencyProbingPaths")) {
                $settings.appDependencyProbingPaths | ForEach-Object {
                    if ($_.Contains("AuthTokenSecret")) {
                        $secretName = $_.authTokenSecret
                        $_.Remove('authTokenSecret')
                        if ($settings.keyVaultName) {
                            $secret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $secretName
                            if ($secret) { $_.authTokenSecret = $secret.SecretValue | Get-PlainText }
                        }
                        else {
                            Write-Host "Not using Azure KeyVault, attempting to retrieve an auth token using gh auth status"
                            $retry = $true
                            while ($retry) {
                                try {
                                    $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
                                    $_.authTokenSecret = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim()
                                    $retry = $false
                                }
                                catch {
                                    Write-Host -ForegroundColor Red "Error trying to retrieve GitHub token."
                                    Write-Host -ForegroundColor Red $_.Exception.Message
                                    Read-Host "Press ENTER to retry operation (or Ctrl+C to cancel)"
                                }
                            }
                        }
                    } 
                }
            }

            if (($settings.keyVaultName) -and -not ($bcAuthContext)) {
                Write-Host "Reading Key Vault $($settings.keyVaultName)"
                installModules -modules @('Az.KeyVault')

                if ($kind -eq "local") {
                    $LicenseFileSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.LicenseFileUrlSecretName
                    if ($LicenseFileSecret) { $LicenseFileUrl = $LicenseFileSecret.SecretValue | Get-PlainText }

                    $insiderSasTokenSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.InsiderSasTokenSecretName
                    if ($insiderSasTokenSecret) { $insiderSasToken = $insiderSasTokenSecret.SecretValue | Get-PlainText }

                    # do not add codesign cert.

                    if ($settings.applicationInsightsConnectionStringSecretName) {
                        $applicationInsightsConnectionStringSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.applicationInsightsConnectionStringSecretName
                        if ($applicationInsightsConnectionStringSecret) {
                            $runAlPipelineParams += @{ 
                                "applicationInsightsConnectionString" = $applicationInsightsConnectionStringSecret.SecretValue | Get-PlainText
                            }
                        }
                    }
                    
                    if ($settings.KeyVaultCertificateUrlSecretName) {
                        $KeyVaultCertificateUrlSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.KeyVaultCertificateUrlSecretName
                        if ($KeyVaultCertificateUrlSecret) {
                            $keyVaultCertificatePasswordSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.keyVaultCertificatePasswordSecretName
                            $keyVaultClientIdSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.keyVaultClientIdSecretName
                            if (-not ($keyVaultCertificatePasswordSecret) -or -not ($keyVaultClientIdSecret)) {
                                OutputError -message "When specifying a KeyVaultCertificateUrl secret in settings, you also need to provide a KeyVaultCertificatePassword secret and a KeyVaultClientId secret"
                                exit
                            }
                            $runAlPipelineParams += @{ 
                                "KeyVaultCertPfxFile" = $KeyVaultCertificateUrlSecret.SecretValue | Get-PlainText
                                "keyVaultCertPfxPassword" = $keyVaultCertificatePasswordSecret.SecretValue
                                "keyVaultClientId" = $keyVaultClientIdSecret.SecretValue | Get-PlainText
                            }
                        }
                    }
                }
                elseif ($kind -eq "cloud") {
                    $adminCenterApiCredentialsSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.AdminCenterApiCredentialsSecretName
                    if ($adminCenterApiCredentialsSecret) { $AdminCenterApiCredentials = $adminCenterApiCredentialsSecret.SecretValue | Get-PlainText | ConvertFrom-Json | ConvertTo-HashTable }
                    $legalParameters = @("RefreshToken","CliendId","ClientSecret","deviceCode","tenantId")
                    $adminCenterApiCredentials.Keys | ForEach-Object {
                        if (-not ($legalParameters -contains $_)) {
                            throw "$_ is an illegal property in adminCenterApiCredentials setting"
                        }
                    }
                    if ($adminCenterApiCredentials.ContainsKey('ClientSecret')) {
                        $adminCenterApiCredentials.ClientSecret = ConvertTo-SecureString -String $AdminCenterApiCredentials.ClientSecret -AsPlainText -Force
                    }
                }
            }
        }

        $params = @{
            "settings" = $settings
            "baseFolder" = $baseFolder
        }
        if ($kind -eq "local") {
            $params += @{
                "insiderSasToken" = $insiderSasToken
            }
        }
        elseif ($kind -eq "cloud") {
            $params += @{
                "doNotCheckArtifactSetting" = $true
            }
        }
        $repo = AnalyzeRepo @params
        if ((-not $repo.appFolders) -and (-not $repo.testFolders)) {
            Write-Host "Repository is empty"
        }

        if ($kind -eq "local" -and $repo.type -eq "AppSource App" ) {
            if ($licenseFileUrl -eq "") {
                OutputError -message "When building an AppSource App, you need to create a secret called LicenseFileUrl, containing a secure URL to your license file with permission to the objects used in the app."
                exit
            }
        }

        $installApps = $repo.installApps
        $installTestApps = $repo.installTestApps

        if ($repo.appDependencyProbingPaths) {
            Write-Host "Downloading dependencies ..."

            if (Test-Path $dependenciesFolder) {
                Get-ChildItem -Path $dependenciesFolder -Include * -File | ForEach-Object { $_.Delete()}
            }
            else {
                New-Item $dependenciesFolder -ItemType Directory | Out-Null
            }

            $repo.appDependencyProbingPaths = @($repo.appDependencyProbingPaths | ForEach-Object {
                if ($_.GetType().Name -eq "PSCustomObject") {
                    $_
                } 
                else { 
                    New-Object -Type PSObject -Property $_
                } 
            })
            $installApps += Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths -mask "Apps" -saveToPath $dependenciesFolder -api_url 'https://api.github.com'
            Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths -mask "TestApps" -saveToPath $dependenciesFolder -api_url 'https://api.github.com' | ForEach-Object {
                $installTestApps += "($_)"
            }
        }
    
        if ($repo.versioningStrategy -eq -1) {
            if ($kind -eq "cloud") { throw "Versioningstrategy -1 cannot be used on cloud" }
            $artifactVersion = [Version]$repo.artifact.Split('/')[4]
            $runAlPipelineParams += @{
                "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
                "appBuild" = "$($artifactVersion.Build)"
                "appRevision" = "$($artifactVersion.Revision)"
            }
        }
        elseif (($repo.versioningStrategy -band 16) -eq 16) {
            $runAlPipelineParams += @{
                "appVersion" = $repo.repoVersion
            }
        }

        $allTestResults = "testresults*.xml"
        $testResultsFile = Join-Path $baseFolder "TestResults.xml"
        $testResultsFiles = Join-Path $baseFolder $allTestResults
        if (Test-Path $testResultsFiles) {
            Remove-Item $testResultsFiles -Force
        }
    
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

        if ($kind -eq "local") {
            $runAlPipelineParams += @{
                "artifact" = $repo.artifact.replace('{INSIDERSASTOKEN}',$insiderSasToken)
                "auth" = $auth
                "credential" = $credential
            }
            if ($containerName) {
                $runAlPipelineParams += @{
                    "updateLaunchJson" = "Local Sandbox ($containerName)"
                    "containerName" = $containerName
                }
            }
            else {
                $runAlPipelineParams += @{
                    "updateLaunchJson" = "Local Sandbox"
                }
            }
        }
        elseif ($kind -eq "cloud") {
            if ($runAlPipelineParams.ContainsKey('NewBcContainer')) {
                throw "Overriding NewBcContainer is not allowed when running cloud DevEnv"
            }
            
            if ($bcAuthContext) {
                 $authContext = Renew-BcAuthContext $bcAuthContext
            }
            else {
                $authContext = New-BcAuthContext @AdminCenterApiCredentials -includeDeviceLogin:($caller -eq "local")
            }

            $existingEnvironment = Get-BcEnvironments -bcAuthContext $authContext | Where-Object { $_.Name -eq $environmentName }
            if ($existingEnvironment) {
                if ($existingEnvironment.type -ne "Sandbox") {
                    throw "Environment $environmentName already exists and it is not a sandbox environment"
                }
                if (!$reuseExistingEnvironment) {
                    Remove-BcEnvironment -bcAuthContext $authContext -environment $environmentName
                    $existingEnvironment = $null
                }
            }
            if ($existingEnvironment) {
                $countryCode = $existingEnvironment.CountryCode.ToLowerInvariant()
                $baseApp = Get-BcPublishedApps -bcAuthContext $authContext -environment $environmentName | Where-Object { $_.Name -eq "Base Application" }
            }
            else {
                $countryCode = $repo.country
                New-BcEnvironment -bcAuthContext $authContext -environment $environmentName -countryCode $countryCode -environmentType "Sandbox" | Out-Null
                do {
                    Start-Sleep -Seconds 10
                    $baseApp = Get-BcPublishedApps -bcAuthContext $authContext -environment $environmentName | Where-Object { $_.Name -eq "Base Application" }
                } while (!($baseApp))
                $baseapp | Out-Host
            }
            
            $artifact = Get-BCArtifactUrl `
                -country $countryCode `
                -version $baseApp.Version `
                -select Closest
            
            if ($artifact) {
                Write-Host "Using Artifacts: $artifact"
            }
            else {
                throw "No artifacts available"
            }

            $runAlPipelineParams += @{
                "artifact" = $artifact
                "bcAuthContext" = $authContext
                "environment" = $environmentName
                "containerName" = "bcServerFilesOnly"
                "updateLaunchJson" = "Cloud Sandbox ($environmentName)"
            }
        }
        
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

        Run-AlPipeline @runAlPipelineParams `
            -pipelinename $workflowName `
            -imageName "" `
            -memoryLimit $repo.memoryLimit `
            -baseFolder $baseFolder `
            -licenseFile $LicenseFileUrl `
            -installApps $installApps `
            -installTestApps $installTestApps `
            -installOnlyReferencedApps:$repo.installOnlyReferencedApps `
            -appFolders $repo.appFolders `
            -testFolders $repo.testFolders `
            -testResultsFile $testResultsFile `
            -testResultsFormat 'JUnit' `
            -customCodeCops $repo.customCodeCops `
            -azureDevOps:($caller -eq 'AzureDevOps') `
            -gitLab:($caller -eq 'GitLab') `
            -gitHubActions:($caller -eq 'GitHubActions') `
            -failOn $repo.failOn `
            -rulesetFile $repo.rulesetFile `
            -AppSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
            -obsoleteTagMinAllowedMajorMinor $repo.obsoleteTagMinAllowedMajorMinor `
            -doNotRunTests `
            -doNotRunBcptTests `
            -useDevEndpoint `
            -keepContainer
    }
    finally {
        if ($loadBcContainerHelper) {
            CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
        }
        if (Test-Path $dependenciesFolder) {
            Get-ChildItem -Path $dependenciesFolder -Include * -File | ForEach-Object { $_.Delete()}
        }
    }
}

function ConvertTo-HashTable() {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    $ht
}

function CheckAndCreateProjectFolder {
    Param(
        [string] $project
    )

    if (-not $project) { $project -eq "." }
    if ($project -ne ".") {
        if (Test-Path $ALGoSettingsFile) {
            Write-Host "Reading $ALGoSettingsFile"
            $settingsJson = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json
            if ($settingsJson.appFolders.Count -eq 0 -and $settingsJson.testFolders.Count -eq 0) {
                OutputWarning "Converting the repository to a multi-project repository as no other apps have been added previously."
                New-Item $project -ItemType Directory | Out-Null
                Move-Item -path $ALGoFolder -Destination $project
                Set-Location $project
            }
            else {
                throw "Repository is setup for a single project, cannot add a project. Move all appFolders, testFolders and the .AL-Go folder to a subdirectory in order to convert to a multi-project repository."
            }
        }
        else {
            if (!(Test-Path $project)) {
                New-Item -Path (Join-Path $project $ALGoFolder) -ItemType Directory | Out-Null
                Set-Location $project
                OutputWarning "Project folder doesn't exist, creating a new project folder and a default settings file with country us. Please modify if needed."
                [ordered]@{
                    "country" = "us"
                    "appFolders" = @()
                    "testFolders" = @()
                } | ConvertTo-Json | Set-Content $ALGoSettingsFile -Encoding UTF8
            }
            else {
                Set-Location $project
            }
        }
    }
}
