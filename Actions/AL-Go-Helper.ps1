Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Github-Helper.psm1'
$readSettingsModule = Join-Path $PSScriptRoot '.Modules/ReadSettings.psm1'
$debugLoggingModule = Join-Path $PSScriptRoot '.Modules/DebugLogHelper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
    # If we are adding more dependencies here, then localDevEnv and cloudDevEnv needs to be updated
}

if (Test-Path $readSettingsModule) {
    Import-Module $readSettingsModule
}

if (Test-Path $debugLoggingModule) {
    Import-Module $debugLoggingModule
}

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

$ALGoFolderName = '.AL-Go'
$ALGoSettingsFile = Join-Path '.AL-Go' 'settings.json'
$RepoSettingsFile = Join-Path '.github' 'AL-Go-Settings.json'
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'defaultCICDPushBranches', Justification = 'False positive.')]
$defaultCICDPushBranches = @( 'main', 'release/*', 'feature/*' )
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'defaultCICDPullRequestBranches', Justification = 'False positive.')]
$defaultCICDPullRequestBranches = @( 'main' )
$defaultBcContainerHelperVersion = "preview" # Must be double quotes. Will be replaced by BcContainerHelperVersion if necessary in the deploy step - ex. "https://github.com/organization/navcontainerhelper/archive/refs/heads/branch.zip"
$notSecretProperties = @("Scopes","TenantId","BlobName","ContainerName","StorageAccountName","ServerUrl","ppUserName","GitHubAppClientId","EnvironmentName")

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
    "InstallMissingDependencies"
    "PreCompileApp"
    "PostCompileApp"
    "PipelineInitialize"
    "PipelineFinalize"
)

# Well known AppIds
$platformAppId = "8874ed3a-0643-4247-9ced-7a7002f7135d"
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

$isPsCore = $PSVersionTable.PSVersion -ge "6.0.0"
if ($isPsCore) {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'byteEncodingParam', Justification = 'False positive.')]
    $byteEncodingParam = @{ "asByteStream" = $true }
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'allowUnencryptedAuthenticationParam', Justification = 'False positive.')]
    $allowUnencryptedAuthenticationParam = @{ "allowUnencryptedAuthentication" = $true }
}
else {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'byteEncodingParam', Justification = 'False positive.')]
    $byteEncodingParam = @{ "Encoding" = "byte" }
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'allowUnencryptedAuthenticationParam', Justification = 'False positive.')]
    $allowUnencryptedAuthenticationParam = @{ }
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'isWindows', Justification = 'Will only run on PS5')]
    $isWindows = $true
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'isLinux', Justification = 'Will only run on PS5')]
    $isLinux = $false
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'isMacOS', Justification = 'Will only run on PS5')]
    $IsMacOS = $false
}

# Copy a HashTable to ensure non case sensitivity (Issue #385)
function Copy-HashTable() {
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    Param(
        [parameter(ValueFromPipeline)]
        [hashtable] $object
    )
    Process {
        $ht = @{}
        if ($object) {
            $object.Keys | ForEach-Object {
                $ht[$_] = $object[$_]
            }
        }
        $ht
    }
}

# Convert SecureString to plain text
function Get-PlainText {
    Param(
        [parameter(ValueFromPipeline, Mandatory = $true)]
        [System.Security.SecureString] $SecureString
    )
    Process {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString);
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr);
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeBSTR($bstr);
        }
    }
}

function IsPropertySecret {
    param (
        [string] $propertyName
    )
    return $notSecretProperties -notcontains $propertyName
}

function ConvertTo-HashTable() {
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    Param(
        [parameter(ValueFromPipeline)]
        $object,
        [switch] $recurse
    )

    Process {
        function AddValueToHashTable {
            Param(
                [hashtable] $ht,
                [string] $name,
                $value,
                [switch] $recurse
            )

            if ($ht.Contains($name)) {
                throw "Duplicate key $name"
            }
            if ($recurse -and ($value -is [System.Collections.Specialized.OrderedDictionary] -or $value -is [hashtable] -or $value -is [System.Management.Automation.PSCustomObject])) {
                $ht[$name] = ConvertTo-HashTable $value -recurse
            }
            elseif ($recurse -and $value -is [array]) {
                $ht[$name] = @($value | ForEach-Object {
                    if (($_ -is [System.Collections.Specialized.OrderedDictionary]) -or ($_ -is [hashtable]) -or ($_ -is [System.Management.Automation.PSCustomObject])) {
                        ConvertTo-HashTable $_ -recurse
                    }
                    else {
                        $_
                    }
                })
            }
            else {
                $ht[$name] = $value
            }
        }

        $ht = @{}
        if ($object -is [System.Collections.Specialized.OrderedDictionary] -or $object -is [hashtable]) {
            foreach($key in $object.Keys) {
                AddValueToHashTable -ht $ht -name $key -value $object."$key" -recurse:$recurse
            }
        }
        elseif ($object -is [System.Management.Automation.PSCustomObject]) {
            foreach($property in $object.PSObject.Properties) {
                AddValueToHashTable -ht $ht -name $property.Name -value $property.Value -recurse:$recurse
            }
        }
        $ht
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

#
# Get Path to BcContainerHelper module (download if necessary)
#
# If $env:BcContainerHelperPath is set, it will be reused (ignoring the ContainerHelperVersion)
#
# ContainerHelperVersion can be:
# - preview (or dev), which will use the preview version downloaded from bccontainerhelper blob storage
# - latest, which will use the latest version downloaded from bccontainerhelper blob storage
# - a specific version, which will use the specific version downloaded from bccontainerhelper blob storage
# - none, which will use the BcContainerHelper module installed on the build agent
# - https://... - direct download url to a zip file containing the BcContainerHelper module
#
# When using direct download url, the module will be downloaded to a temp folder and will not be cached
# When using none, the module will be located in modules and used from there
# When using preview, latest or a specific version number, the module will be downloaded to a cache folder and will be reused if the same version is requested again
# This is to avoid filling up the temp folder with multiple identical versions of BcContainerHelper
# The cache folder is C:\ProgramData\BcContainerHelper on Windows and /home/<username>/.BcContainerHelper on Linux
# A Mutex will be used to ensure multiple agents aren't fighting over the same cache folder
#
# This function will set $env:BcContainerHelperPath, which is the path to the BcContainerHelper.ps1 file for reuse in subsequent calls
#
function GetBcContainerHelperPath([string] $bcContainerHelperVersion) {
    if ("$env:BcContainerHelperPath" -and (Test-Path -Path $env:BcContainerHelperPath -PathType Leaf)) {
        return $env:BcContainerHelperPath
    }

    if ($bcContainerHelperVersion -eq 'None') {
        $module = Get-Module BcContainerHelper
        if (-not $module) {
            OutputError "When setting BcContainerHelperVersion to none, you need to ensure that BcContainerHelper is installed on the build agent"
        }
        $bcContainerHelperPath = Join-Path (Split-Path $module.Path -parent) "BcContainerHelper.ps1" -Resolve
    }
    else {
        if ($isWindows) {
            $bcContainerHelperRootFolder = 'C:\ProgramData\BcContainerHelper'
        }
        else {
            $myUsername = (whoami)
            $bcContainerHelperRootFolder = "/home/$myUsername/.BcContainerHelper"
        }
        if (!(Test-Path $bcContainerHelperRootFolder)) {
            New-Item -Path $bcContainerHelperRootFolder -ItemType Directory | Out-Null
        }

        $webclient = New-Object System.Net.WebClient
        if ($bcContainerHelperVersion -like "https://*") {
            # Use temp space for private versions
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            Write-Host "Downloading BcContainerHelper developer version from $bcContainerHelperVersion"
            try {
                $webclient.DownloadFile($bcContainerHelperVersion, "$tempName.zip")
            }
            catch {
                $tempName = Join-Path $bcContainerHelperRootFolder ([Guid]::NewGuid().ToString())
                $bcContainerHelperVersion = "preview"
                Write-Host "Download failed, downloading BcContainerHelper $bcContainerHelperVersion version from Blob Storage"
                $webclient.DownloadFile("https://bccontainerhelper-addgd5gzaxf9fneh.b02.azurefd.net/public/$($bcContainerHelperVersion).zip", "$tempName.zip")
            }
        }
        else {
            $tempName = Join-Path $bcContainerHelperRootFolder ([Guid]::NewGuid().ToString())
            if ($bcContainerHelperVersion -eq "dev") {
                # For backwards compatibility, use preview when dev is specified
                $bcContainerHelperVersion = 'preview'
            }
            Write-Host "Downloading BcContainerHelper $bcContainerHelperVersion version from Blob Storage"
            $webclient.DownloadFile("https://bccontainerhelper-addgd5gzaxf9fneh.b02.azurefd.net/public/$($bcContainerHelperVersion).zip", "$tempName.zip")
        }
        Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
        $bcContainerHelperPath = (Get-Item -Path (Join-Path $tempName "*\BcContainerHelper.ps1")).FullName
        Remove-Item -Path "$tempName.zip" -ErrorAction SilentlyContinue
        if ($bcContainerHelperVersion -notlike "https://*") {
            # Check whether the version is already available in the cache
            $version = ([System.IO.File]::ReadAllText((Join-Path $tempName 'BcContainerHelper/Version.txt'), [System.Text.Encoding]::UTF8)).Trim()
            $cacheFolder = Join-Path $bcContainerHelperRootFolder $version
            # To avoid two agents on the same machine downloading the same version at the same time, use a mutex
            $buildMutexName = "DownloadAndImportBcContainerHelper"
            $buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
            try {
                try {
                    if (!$buildMutex.WaitOne(1000)) {
                        Write-Host "Waiting for other process loading BcContainerHelper"
                        $buildMutex.WaitOne() | Out-Null
                        Write-Host "Other process completed loading BcContainerHelper"
                    }
                }
                catch [System.Threading.AbandonedMutexException] {
                    Write-Host "Other process terminated abnormally"
                }
                if (Test-Path $cacheFolder) {
                    Remove-Item $tempName -Recurse -Force
                }
                else {
                    Rename-Item -Path $tempName -NewName $version
                }
            }
            finally {
                $buildMutex.ReleaseMutex()
            }
            $bcContainerHelperPath = Join-Path $cacheFolder "BcContainerHelper/BcContainerHelper.ps1"
        }
    }
    $env:BcContainerHelperPath = $bcContainerHelperPath
    if ($ENV:GITHUB_ENV) {
        Add-Content -Encoding UTF8 -Path $ENV:GITHUB_ENV "BcContainerHelperPath=$bcContainerHelperPath"
    }
    return $bcContainerHelperPath
}

#
# Download and import the BcContainerHelper module based on repository settings
# baseFolder is the repository baseFolder
#
function DownloadAndImportBcContainerHelper([string] $baseFolder = $ENV:GITHUB_WORKSPACE) {
    $params = @{ "ExportTelemetryFunctions" = $true }

    # Default BcContainerHelper Version is hardcoded in AL-Go-Helper (replaced during AL-Go deploy)
    $bcContainerHelperVersion = $defaultBcContainerHelperVersion

    if ("$env:Settings" -ne "") {
        $repoSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid().ToString()).json"
        $env:Settings | Set-Content -Path $repoSettingsPath -Encoding UTF8
    }
    else {
        $repoSettingsPath = Join-Path $baseFolder $repoSettingsFile
    }
    if (Test-Path $repoSettingsPath) {
        # Override default BcContainerHelper version from AL-Go-Helper only if new version is specifically specified in settings
        $repoSettings = Get-Content $repoSettingsPath -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        if ($repoSettings.Keys -contains "BcContainerHelperVersion" -and $defaultBcContainerHelperVersion -notlike 'https://*') {
            $bcContainerHelperVersion = $repoSettings.BcContainerHelperVersion
            Write-Host "Using BcContainerHelper $bcContainerHelperVersion version"
            if ($bcContainerHelperVersion -like "https://*") {
                throw "Setting BcContainerHelperVersion to a URL in settings is not allowed. Fork the AL-Go repository and use direct AL-Go development instead."
            }
            if ($bcContainerHelperVersion -ne 'latest' -and $bcContainerHelperVersion -ne 'preview') {
                Write-Host "::Warning::Using a specific version of BcContainerHelper is not recommended and will lead to build failures in the future. Consider removing the setting."
            }
        }
        $params += @{ "bcContainerHelperConfigFile" = $repoSettingsPath }
    }

    if ($bcContainerHelperVersion -eq '') {
        $bcContainerHelperVersion = "latest"
    }

    if ($bcContainerHelperVersion -eq 'private') {
        throw "ContainerHelperVersion private is no longer supported. Use direct AL-Go development and a direct download url instead."
    }

    $bcContainerHelperPath = GetBcContainerHelperPath -bcContainerHelperVersion $bcContainerHelperVersion

    Write-Host "Import from $bcContainerHelperPath"
    . $bcContainerHelperPath @params
}

function ExcludeUnneededApps {
    Param(
        [string[]] $folders,
        [string[]] $includeOnlyAppIds,
        [hashtable] $appIdFolders
    )

    foreach($folder in $folders) {
        if ($includeOnlyAppIds.Contains(($appIdFolders.GetEnumerator() | Where-Object { $_.Value -eq $folder }).Key)) {
            $folder
        }
    }
}

function ResolveProjectFolders {
    Param(
        [string] $project,
        [string] $baseFolder,
        [ref] $projectSettings
    )
    $projectPath = Join-Path $baseFolder $project -Resolve

    Push-Location $projectPath

    try {
        $appFolders = $projectSettings.Value.appFolders
        $testFolders = $projectSettings.Value.testFolders
        $bcptTestFolders = $projectSettings.Value.bcptTestFolders

        # If no app folders are specified in AL-Go settings, check for AL apps in the project folder
        if (!$appFolders -and !$testFolders -and !$bcptTestFolders) {
            Get-ChildItem -Path $projectPath -Recurse | Where-Object { $_.PSIsContainer -and (Test-Path -Path (Join-Path $_.FullName "app.json")) } | ForEach-Object {
                $aLProjectFolder = $_
                $appJson = Get-Content (Join-Path $aLProjectFolder.FullName "app.json") -Encoding UTF8 | ConvertFrom-Json

                $isTestApp = $false
                $isBcptTestApp = $false

                # if an AL app has a dependency to a test app, it is a test app
                # if an AL app has a dependency to an app from the performance toolkit apps, it is a bcpt test app
                if ($appJson.PSObject.Properties.Name -eq "dependencies") {
                    foreach($dependency in $appJson.dependencies) {
                        if ($dependency.PSObject.Properties.Name -eq "AppId") {
                            $id = $dependency.AppId
                        }
                        else {
                            $id = $dependency.Id
                        }

                        # Check if the app is a test app or a bcpt app
                        if ($performanceToolkitApps.Contains($id)) {
                            $isBcptTestApp = $true
                        }
                        elseif ($testRunnerApps.Contains($id)) {
                            $isTestApp = $true
                        }
                    }
                }

                # Folders are relative to the project folder
                $appFolder = Resolve-Path -Path $aLProjectFolder.FullName -Relative
                switch ($true) {
                    $isBcptTestApp { $bcptTestFolders += @($appFolder); break }
                    $isTestApp { $testFolders += @($appFolder); break }
                    Default { $appFolders += @($appFolder) }
                }
            }
        }

        # Filter out app folders that doesn't contain an app.json file
        function FilterFolders($projectPath, $folders) {
            if (!$folders) {
                return @()
            }

            $resolvedPaths = @()

            foreach ($folder in $folders) {
                $aLProjectFolder = Join-Path $projectPath $folder
                $resolvedALProjectsPaths = Resolve-Path $aLProjectFolder -Relative -ErrorAction Ignore | Where-Object { Test-Path (Join-Path $_ 'app.json') }

                if ($resolvedALProjectsPaths) {
                    $resolvedPaths += @($resolvedALProjectsPaths)
                }
                else {
                    OutputWarning "The folder '$folder' for project '$project' cannot be resolved or does not contain an app.json file. Skipping."
                }
            }

            return $resolvedPaths
        }

        $projectSettings.Value.appFolders = @(FilterFolders $projectPath $appFolders)
        $projectSettings.Value.testFolders = @(FilterFolders $projectPath $testFolders)
        $projectSettings.Value.bcptTestFolders = @(FilterFolders $projectPath $bcptTestFolders)
    }
    finally {
        Pop-Location
    }
}

function AnalyzeRepo {
    Param(
        [hashTable] $settings,
        [string] $baseFolder = $ENV:GITHUB_WORKSPACE,
        [string] $project = '.',
        [switch] $doNotCheckArtifactSetting,
        [switch] $doNotIssueWarnings,
        [string[]] $includeOnlyAppIds
    )

    $settings = $settings | Copy-HashTable
    $projectPath = Join-Path $baseFolder $project -Resolve

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
    elseif ($settings.type -eq "AppSource App") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $false)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $true)
        }
        if ($settings.enableAppSourceCop -and (-not ($settings.appSourceCopMandatoryAffixes))) {
            # Do not throw an error if we only read the Repo Settings file
            if (Test-Path (Join-Path $baseFolder $ALGoSettingsFile)) {
                throw "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $ALGoSettingsFile"
            }
        }
    }
    else {
        throw "The type, specified in $RepoSettingsFile, must be either 'PTE' or 'AppSource App'. It is '$($settings.type)'."
    }

    ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $settings)

    Write-Host "Checking appFolders, testFolders and bcptTestFolders"
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

            # Check if there are any folders matching $folder
            if (!(Get-Item $folder | Where-Object { $_ -is [System.IO.DirectoryInfo] })) {
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
                if ($dependencies.Contains($folderName)) {
                    throw "$descr $folderName, specified in $ALGoSettingsFile, is specified more than once."
                }
                $dependencies.Add($folderName, @())
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    if ($appIdFolders.Contains($appJson.Id)) {
                        throw "$descr $folderName contains a duplicate AppId ($($appIdFolders."$($appJson.Id)"))"
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
        $artifactUrl = DetermineArtifactUrl -projectSettings $settings -doNotIssueWarnings:$doNotIssueWarnings
        $version = $artifactUrl.Split('/')[4]
        Write-Host "Downloading artifacts from $($artifactUrl.Split('?')[0])"
        $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
        if (-not ($folders)) {
            throw "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $ALGoSettingsFile."
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
    if (!$settings.doNotRunBcptTests -and -not $settings.bcptTestFolders) {
        if (!$settings.doNotBuildTests) { Write-Host "No performance test apps found in bcptTestFolders in $ALGoSettingsFile" }
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotRunTests -and -not $settings.testFolders) {
        if (-not ($doNotIssueWarnings -or $settings.doNotBuildTests)) { OutputWarning -message "No test apps found in testFolders in $ALGoSettingsFile" }
        $settings.doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
        if (!$doNotIssueWarnings) { OutputWarning -message "No apps found in appFolders in $ALGoSettingsFile" }
    }

    $settings
}

function CheckAppDependencyProbingPaths {
    Param(
        [hashTable] $settings,
        $token,
        [string] $baseFolder = $ENV:GITHUB_WORKSPACE,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $project = '.',
        [string[]] $includeOnlyAppIds
    )

    Write-Host "Checking appDependencyProbingPaths"
    $settings = $settings | Copy-HashTable
    if ($settings.appDependencyProbingPaths) {
        $settings.appDependencyProbingPaths = @($settings.appDependencyProbingPaths | ForEach-Object {
                if ($_.GetType().Name -eq "PSCustomObject") {
                    $_
                }
                else {
                    New-Object -Type PSObject -Property $_
                }
            })
        foreach($dependency in $settings.appDependencyProbingPaths) {
            if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
                throw "The Setting AppDependencyProbingPaths needs to contain a repo property, pointing to the repository on which your project have a dependency"
            }
            if ($dependency.Repo -eq ".") {
                $dependency.Repo = "https://github.com/$repository"
            }
            elseif ($dependency.Repo -notlike "https://*") {
                $dependency.Repo = "https://github.com/$($dependency.Repo)"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
                $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "projects")) {
                $dependency | Add-Member -name "projects" -MemberType NoteProperty -Value "*"
            }
            elseif ([String]::IsNullOrEmpty($dependency.projects)) {
                $dependency.projects = '*'
            }
            if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
                $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "release"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "branch")) {
                $dependency | Add-Member -name "branch" -MemberType NoteProperty -Value "main"
            }
            Write-Host "Dependency to projects '$($dependency.projects)' in $($dependency.Repo)@$($dependency.branch), version $($dependency.version), release status $($dependency.release_status)"
            if ($dependency.PsObject.Properties.name -eq "AuthTokenSecret") {
                Write-Host "Using secret $($dependency.AuthTokenSecret) for access to repository"
                if ("$env:Secrets" -eq "") {
                    throw "Internal error. Secrets are not available!"
                }
                $secrets = $env:Secrets | ConvertFrom-Json
                # AuthTokenSecret is specified, use the value of that secret
                $dependency.AuthTokenSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($dependency.AuthTokenSecret)"))
            }
            else {
                if ($token) {
                    Write-Host "Using GITHUB_TOKEN for access to repository"
                }
                else {
                    Write-Host "No token available, will attempt to invoke gh auth token for access to repository"
                    try {
                        $token = invoke-gh -silent -returnValue auth token
                    }
                    catch {
                        Write-Host "Unable to get token from gh, will attempt to access repository without token. Message: $($_.Exception.Message)"
                        $token = $null
                    }
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
                if ($dependency.Repo -ne "https://github.com/$repository") {
                    OutputWarning "Dependencies with release_status 'include' must be to other projects in the same repository."
                }
                else {
                    foreach($depProject in $dependency.projects.Split(',')) {
                        if ($depProject -eq '*') {
                            OutputWarning "Dependencies to the same repository cannot specify all projects (*)"
                        }
                        else {
                            Write-Host "Identified dependency to project $depProject in the same repository"

                            $dependencyIds = @( @($settings.appDependencies + $settings.testDependencies) | ForEach-Object { $_.id })
                            $thisIncludeOnlyAppIds = @($dependencyIds + $includeOnlyAppIds + $dependency.alwaysIncludeApps)
                            $depSettings = ReadSettings -baseFolder $baseFolder -project $depProject -workflowName "CI/CD"
                            $depSettings = AnalyzeRepo -settings $depSettings -baseFolder $baseFolder -project $depProject -includeOnlyAppIds $thisIncludeOnlyAppIds -doNotCheckArtifactSetting -doNotIssueWarnings
                            $depSettings = CheckAppDependencyProbingPaths -settings $depSettings -token $token -baseFolder $baseFolder -repository $repository -project $depProject -includeOnlyAppIds $thisIncludeOnlyAppIds

                            $projectPath = Join-Path $baseFolder $project -Resolve
                            Push-Location $projectPath
                            try {
                                foreach($propertyName in "appFolders", "testFolders", "bcptTestFolders") {
                                    Write-Host "Adding folders from $depProject to $propertyName in $project"
                                    $found = $false
                                    foreach($folder in $depSettings."$propertyName") {
                                        $relativeFolderPath = Resolve-Path -Path (Join-Path $baseFolder "$depProject/$folder") -Relative
                                        if (!$settings."$propertyName".Contains($relativeFolderPath)) {
                                            $settings."$propertyName" += @($relativeFolderPath)
                                            $found = $true
                                            Write-Host "- $relativeFolderPath"
                                        }
                                    }
                                    if (!$found) { Write-Host "- No folders added" }
                                }
                            }
                            finally {
                                Pop-Location
                            }
                        }
                    }
                }
            }
        }
    }
    $settings
}

function GetProjectFolders {
    Param(
        [string] $baseFolder,
        [string] $project,
        [switch] $includeALGoFolder,
        [string[]] $includeOnlyAppIds
    )

    Write-Host "Analyzing project $project"
    if ($includeOnlyAppIds) {
        $systemAppId, $baseAppId, $applicationAppId | ForEach-Object {
            if (!$includeOnlyAppIds.Contains($_)) { $includeOnlyAppIds += @($_) }
        }
    }

    $projectFolders = @()
    $settings = ReadSettings -baseFolder $baseFolder -project $project -workflowName "CI/CD"
    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -includeOnlyAppIds $includeOnlyAppIds -doNotIssueWarnings -doNotCheckArtifactSetting
    $AlGoFolderArr = @()
    if ($includeALGoFolder) { $AlGoFolderArr = @($ALGoFolderName) }
    Set-Location $baseFolder
    @($settings.appFolders + $settings.testFolders + $settings.bcptTestFolders + $AlGoFolderArr) | ForEach-Object {
        $fullPath = Join-Path $baseFolder "$project/$_" -Resolve
        $relativePath = Resolve-Path -Path $fullPath -Relative
        $folder = $relativePath.Substring(2).Replace('\', '/').ToLowerInvariant()
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

    $projectFolders
}

function InstallModule {
    Param(
        [String] $name,
        [System.Version] $minimumVersion = $null
    )

    if ($null -eq $minimumVersion) {
        $minimumVersion = [System.Version](GetPackageVersion -packageName $name)
    }
    $module = Get-Module -name $name -ListAvailable | Select-Object -First 1
    if ($module -and $module.Version -ge $minimumVersion) {
        Write-Host "Module $name is available in version $($module.Version)"
    }
    else {
        Write-Host "Installing module $name (minimum version $minimumVersion)"
        Install-Module -Name $name -MinimumVersion "$minimumVersion" -Force | Out-Null
    }
    Write-Host "Importing module $name (minimum version $minimumVersion)"
    Import-Module -Name $name -MinimumVersion $minimumVersion -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
}

function CloneIntoNewFolder {
    Param(
        [string] $actor,
        [string] $token,
        [string] $updateBranch = $ENV:GITHUB_REF_NAME,
        [string] $newBranchPrefix = '',
        [bool] $directCommit
    )

    $baseFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item $baseFolder -ItemType Directory | Out-Null
    Set-Location $baseFolder

    # Environment variables for hub commands
    $env:GITHUB_USER = $actor
    $env:GITHUB_TOKEN = GetAccessToken -token $token -permissions @{"actions"="read";"metadata"="read";"contents"="write";"pull_requests"="write"}

    $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
    $serverUrl = "$($serverUri.Scheme)://$($env:GITHUB_USER):$($env:GITHUB_TOKEN)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

    # Configure git
    invoke-git config --global user.email "$actor@users.noreply.github.com"
    invoke-git config --global user.name "$actor"
    invoke-git config --global hub.protocol https
    invoke-git config --global core.autocrlf false

    invoke-git clone $serverUrl

    Set-Location *
    invoke-git checkout $updateBranch

    $branch = "$newBranchPrefix/$updateBranch/$((Get-Date).ToUniversalTime().ToString(`"yyMMddHHmmss`"))" # e.g. create-development-environment/main/210101120000
    if (!$directCommit) {
        invoke-git checkout -b $branch
    }

    $serverUrl
    $branch
}

function CommitFromNewFolder {
    Param(
        [string] $serverUrl,
        [string] $commitMessage,
        [string] $body = $commitMessage,
        [string] $branch,
        [string] $headBranch = $ENV:GITHUB_REF_NAME
    )

    invoke-git add *
    $status = invoke-git -returnValue status --porcelain=v1
    if ($status) {
        $title = $commitMessage

        # Add commit message suffix if specified in settings
        $settings = ReadSettings
        if ($settings.commitOptions.messageSuffix) {
            $commitMessage = "$commitMessage / $($settings.commitOptions.messageSuffix)"
            $body = "$body`n$($settings.commitOptions.messageSuffix)"
        }

        if ($commitMessage.Length -gt 250) {
            $commitMessage = "$($commitMessage.Substring(0,250))...)"
        }

        if ($title.Length -gt 250) {
            $title = "$($title.Substring(0,250))...)"
        }

        invoke-git commit --allow-empty -m "$commitMessage"
        $activeBranch = invoke-git -returnValue -silent name-rev --name-only HEAD
        # $branch is the name of the branch to be used when creating a Pull Request
        # $activeBranch is the name of the branch that is currently checked out
        # If activeBranch and branch are the same - we are creating a PR
        if ($activeBranch -ne $branch) {
            try {
                invoke-git push $serverUrl
                return $true
            }
            catch {
                OutputWarning("Direct Commit wasn't allowed, trying to create a Pull Request instead")
                invoke-git reset --soft HEAD~
                invoke-git checkout -b $branch
                invoke-git commit --allow-empty -m "$commitMessage"
            }
        }
        invoke-git push -u $serverUrl $branch
        try {
            if ($settings.commitOptions.pullRequestLabels) {
                $labels = "$($settings.commitOptions.pullRequestLabels -join ",")"
                Write-Host "Adding labels: $labels"
                invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY --base $headBranch --body "$body" --label $labels
            } else {
                invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY --base $headBranch --body "$body"
            }
        }
        catch {
            OutputError("GitHub actions are not allowed to create Pull Requests (see GitHub Organization or Repository Actions Settings). You can create the PR manually by navigating to $($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/tree/$branch")
        }

        # Set up auto-merge for the Pull Request if specified in settings
        if ($settings.commitOptions.pullRequestAutoMerge) {
            try {
                if (($settings.commitOptions.pullRequestMergeMethod).ToLowerInvariant() -eq "merge") {
                    invoke-gh pr merge --auto --merge --delete-branch
                } else {
                    invoke-gh pr merge --auto --squash --delete-branch
                }
            } catch {
                OutputError("Could not set up auto-merge for the Pull Request with merge method $($settings.commitOptions.pullRequestMergeMethod)")
            }
        }
        return $true
    }
    else {
        Write-Host "No changes detected in files"
        return $false
    }
}

function Select-Value {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $title,
        [Parameter(Mandatory = $false)]
        [string] $description,
        [Parameter(Mandatory = $true)]
        $options,
        [Parameter(Mandatory = $false)]
        [string] $default = "",
        [Parameter(Mandatory = $true)]
        [string] $question
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-" * $title.Length)
    }
    if ($description) {
        Write-Host $description
        Write-Host
    }
    $offset = 0
    $keys = @()
    $values = @()
    $defaultAnswer = 0
    foreach($option in $options.GetEnumerator()) {
        Write-Host -ForegroundColor Yellow "$([char]($offset+97)) " -NoNewline
        $keys += @($option.Key)
        $values += @($option.Value)
        if ($option.Key -eq $default) {
            Write-Host -ForegroundColor Yellow $option.Value
            $defaultAnswer = $offset
        }
        else {
            Write-Host $option.Value
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
            if (($selection.Length -ne 1) -or (([int][char]($selection)) -lt 97 -or ([int][char]($selection)) -ge (97 + $offset))) {
                Write-Host -ForegroundColor Red "Illegal answer. " -NoNewline
            }
            else {
                $answer = ([int][char]($selection)) - 97
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
        [Parameter(Mandatory = $false)]
        [string] $title,
        [Parameter(Mandatory = $false)]
        [string] $description,
        [Parameter(Mandatory = $false)]
        $options,
        [Parameter(Mandatory = $false)]
        [string] $default = "",
        [Parameter(Mandatory = $true)]
        [string] $question,
        [switch] $doNotConvertToLower,
        [char[]] $trimCharacters = @()
    )

    if ($title) {
        Write-Host -ForegroundColor Yellow $title
        Write-Host -ForegroundColor Yellow ("-" * $title.Length)
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

    if ($trimCharacters) {
        $answer = $answer.trim($trimCharacters)
    }
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
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($value.Substring(2, $value.Length - 4)))
        }
    }
}

function GetContainerName([string] $project) {
    "bc$($project -replace "[^a-z0-9\-]")$env:GITHUB_RUN_ID"
}

function CreateDevEnv {
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('local', 'cloud')]
        [string] $kind,
        [ValidateSet('local', 'GitHubActions')]
        [string] $caller = 'local',
        [Parameter(Mandatory = $true)]
        [string] $baseFolder,
        [string] $repository = "$ENV:GITHUB_REPOSITORY",
        [string] $project,
        [string] $userName = $env:Username,

        [Parameter(ParameterSetName = 'cloud')]
        [Hashtable] $bcAuthContext = $null,
        [Parameter(ParameterSetName = 'cloud')]
        [Hashtable] $adminCenterApiCredentials = @{},
        [Parameter(Mandatory = $true, ParameterSetName = 'cloud')]
        [string] $environmentName,
        [Parameter(ParameterSetName = 'cloud')]
        [switch] $reuseExistingEnvironment,

        [Parameter(Mandatory = $true, ParameterSetName = 'local')]
        [ValidateSet('Windows', 'UserPassword')]
        [string] $auth,
        [Parameter(Mandatory = $true, ParameterSetName = 'local')]
        [pscredential] $credential,
        [Parameter(ParameterSetName = 'local')]
        [string] $containerName = "",
        [string] $licenseFileUrl = "",
        [switch] $accept_insiderEula,
        [switch] $clean
    )

    if ($PSCmdlet.ParameterSetName -ne $kind) {
        throw "Specified parameters doesn't match kind=$kind"
    }

    if ("$repository" -eq "") {
        Push-Location $baseFolder
        try {
            $repoInfo = invoke-gh -silent -returnValue repo view --json "owner,name" | ConvertFrom-Json
            $repository = "$($repoInfo.owner.login)/$($repoInfo.name)"
        }
        finally {
            Pop-Location
        }
    }
    $projectFolder = Join-Path $baseFolder $project -Resolve
    $dependenciesFolder = Join-Path $projectFolder ".dependencies"
    $runAlPipelineParams = @{}
    DownloadAndImportBcContainerHelper -baseFolder $baseFolder
    $removeEnvSecrets = $false
    try {
        if ($env:Secrets) {
            $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
        }
        else {
            $secrets = @{}
            $removeEnvSecrets = $true
        }
        if ($caller -eq "local") {
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Check-BcContainerHelperPermissions -silent -fix
            }
        }

        $workflowName = "$($kind)DevEnv"
        $params = @{
            "baseFolder"   = $baseFolder
            "project"      = $project
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
                        if (!$secrets.ContainsKey($secretName)) {
                            $secrets."$secretName" = ''
                        }
                        if ($settings.keyVaultName) {
                            $secret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $secretName
                            if ($secret) {
                                $secrets."$secretName" = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($secret.SecretValue | Get-PlainText)))
                            }
                        }
                        else {
                            Write-Host "Not using Azure KeyVault, attempting to retrieve an auth token using gh auth token"
                            $retry = $true
                            while ($retry) {
                                try {
                                    $secrets."$secretName" = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((invoke-gh -silent -returnValue auth token)))
                                    $retry = $false
                                }
                                catch {
                                    Write-Host -ForegroundColor Red "Error trying to retrieve GitHub token (are you authenticated in GitHub CLI?)"
                                    Write-Host -ForegroundColor Red $_.Exception.Message
                                    Read-Host "Press ENTER to retry operation (or Ctrl+C to cancel)"
                                }
                            }
                        }
                    }
                }
                $env:Secrets = $secrets | ConvertTo-Json
            }

            if (($settings.keyVaultName) -and -not ($bcAuthContext)) {
                Write-Host "Reading Key Vault $($settings.keyVaultName)"
                InstallAzModuleIfNeeded -name 'Az.KeyVault'

                if ($kind -eq "local") {
                    $LicenseFileSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.licenseFileUrlSecretName
                    if ($LicenseFileSecret) { $licenseFileUrl = $LicenseFileSecret.SecretValue | Get-PlainText }

                    # do not add codesign cert.

                    if ($settings.applicationInsightsConnectionStringSecretName) {
                        $applicationInsightsConnectionStringSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.applicationInsightsConnectionStringSecretName
                        if ($applicationInsightsConnectionStringSecret) {
                            $runAlPipelineParams += @{
                                "applicationInsightsConnectionString" = $applicationInsightsConnectionStringSecret.SecretValue | Get-PlainText
                            }
                        }
                    }

                    if ($settings.keyVaultCertificateUrlSecretName) {
                        $KeyVaultCertificateUrlSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.keyVaultCertificateUrlSecretName
                        if ($KeyVaultCertificateUrlSecret) {
                            $keyVaultCertificatePasswordSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.keyVaultCertificatePasswordSecretName
                            $keyVaultClientIdSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.keyVaultClientIdSecretName
                            if (-not ($keyVaultCertificatePasswordSecret) -or -not ($keyVaultClientIdSecret)) {
                                OutputError -message "When specifying a KeyVaultCertificateUrl secret in settings, you also need to provide a KeyVaultCertificatePassword secret and a KeyVaultClientId secret"
                                exit
                            }
                            $runAlPipelineParams += @{
                                "KeyVaultCertPfxFile"     = $KeyVaultCertificateUrlSecret.SecretValue | Get-PlainText
                                "keyVaultCertPfxPassword" = $keyVaultCertificatePasswordSecret.SecretValue
                                "keyVaultClientId"        = $keyVaultClientIdSecret.SecretValue | Get-PlainText
                            }
                        }
                    }
                }
                elseif ($kind -eq "cloud") {
                    $adminCenterApiCredentialsSecret = Get-AzKeyVaultSecret -VaultName $settings.keyVaultName -Name $settings.adminCenterApiCredentialsSecretName
                    if ($adminCenterApiCredentialsSecret) { $adminCenterApiCredentials = $adminCenterApiCredentialsSecret.SecretValue | Get-PlainText | ConvertFrom-Json | ConvertTo-HashTable }
                    $legalParameters = @("RefreshToken", "CliendId", "ClientSecret", "deviceCode", "tenantId")
                    $adminCenterApiCredentials.Keys | ForEach-Object {
                        if (-not ($legalParameters -contains $_)) {
                            throw "$_ is an illegal property in adminCenterApiCredentials setting"
                        }
                    }
                }
            }
        }

        $params = @{}
        if ($kind -eq "cloud") {
            $accept_insiderEula = $true
            $params += @{
                "doNotCheckArtifactSetting" = $true
            }
        }
        $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project @params
        $settings = CheckAppDependencyProbingPaths -settings $settings -baseFolder $baseFolder -repository $repository -project $project

        if (!$accept_insiderEula -and ($settings.artifact -like 'https://bcinsider*.net/*')) {
            Read-Host 'Press ENTER to accept the Business Central insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) or break the script to cancel'
            $accept_insiderEula = $true
        }

        if ((-not $settings.appFolders) -and (-not $settings.testFolders)) {
            Write-Host "Repository is empty"
        }

        if ($clean) {
            $appFolders = @()
            $testFolders = @()
        }
        else {
            $appFolders = $settings.appFolders
            $testFolders = $settings.testFolders
        }

        $installApps = $settings.installApps
        $installTestApps = $settings.installTestApps

        if ($settings.appDependencyProbingPaths) {
            Write-Host "Downloading dependencies ..."

            if (Test-Path $dependenciesFolder) {
                Get-ChildItem -Path $dependenciesFolder -Include * -File | ForEach-Object { $_.Delete() }
            }
            else {
                New-Item $dependenciesFolder -ItemType Directory | Out-Null
            }

            $settings.appDependencyProbingPaths = @($settings.appDependencyProbingPaths | ForEach-Object {
                    if ($_.GetType().Name -eq "PSCustomObject") {
                        $_
                    }
                    else {
                        New-Object -Type PSObject -Property $_
                    }
                })
            GetDependencies -probingPathsJson $settings.appDependencyProbingPaths -saveToPath $dependenciesFolder -api_url 'https://api.github.com' | ForEach-Object {
                if ($_.startswith('(')) {
                    $installTestApps += $_
                }
                else {
                    $installApps += $_
                }
            }
        }

        if ($settings.versioningStrategy -eq -1) {
            if ($kind -eq "cloud") { throw "Versioningstrategy -1 cannot be used on cloud" }
            $artifactVersion = [Version]$settings.artifact.Split('/')[4]
            $runAlPipelineParams += @{
                "appVersion"  = "$($artifactVersion.Major).$($artifactVersion.Minor)"
                "appBuild"    = $artifactVersion.Build
                "appRevision" = $artifactVersion.Revision
            }
        }
        else {
            if (($settings.versioningStrategy -band 16) -eq 16) {
                $runAlPipelineParams += @{
                    "appVersion" = $settings.repoVersion
                }
            }
            $appBuild = 0
            $appRevision = 0
            switch ($settings.versioningStrategy -band 15) {
                2 {
                    # USE DATETIME
                    $appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
                    $appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
                }
                15 {
                    # Use maxValue
                    $appBuild = [Int32]::MaxValue
                    $appRevision = 0
                }
            }
            $runAlPipelineParams += @{
                "appBuild"    = $appBuild
                "appRevision" = $appRevision
            }
        }

        $allTestResults = "testresults*.xml"
        $testResultsFile = Join-Path $projectFolder "TestResults.xml"
        $testResultsFiles = Join-Path $projectFolder $allTestResults
        if (Test-Path $testResultsFiles) {
            Remove-Item $testResultsFiles -Force
        }

        Push-Location $projectFolder
        try {
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

            if ($kind -eq "local") {
                $runAlPipelineParams += @{
                    "artifact"      = $settings.artifact.replace('{INSIDERSASTOKEN}', '')
                    "auth"          = $auth
                    "credential"    = $credential
                    "keepContainer" = $true
                }
                if ($containerName) {
                    $runAlPipelineParams += @{
                        "updateLaunchJson" = "Local Sandbox ($containerName)"
                        "containerName"    = $containerName
                    }
                }
                else {
                    $runAlPipelineParams += @{
                        "updateLaunchJson" = "Local Sandbox"
                    }
                }
            }
            elseif ($kind -eq "cloud") {
                if ($runAlPipelineParams.Keys -contains 'NewBcContainer') {
                    throw "Overriding NewBcContainer is not allowed when running cloud DevEnv"
                }

                if ($bcAuthContext) {
                    $authContext = Renew-BcAuthContext $bcAuthContext
                }
                else {
                    $authContext = New-BcAuthContext @adminCenterApiCredentials -includeDeviceLogin:($caller -eq "local")
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
                    $countryCode = $settings.country
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
                    "artifact"         = $artifact
                    "bcAuthContext"    = $authContext
                    "environment"      = $environmentName
                    "containerName"    = "bcServerFilesOnly"
                    "updateLaunchJson" = "Cloud Sandbox ($environmentName)"
                }
            }

            "enableTaskScheduler",
            "assignPremiumPlan",
            "installTestRunner",
            "installTestFramework",
            "installTestLibraries",
            "installPerformanceToolkit",
            "enableCodeCop",
            "enableAppSourceCop",
            "enablePerTenantExtensionCop",
            "enableUICop",
            "enableCodeAnalyzersOnTestApps",
            "useCompilerFolder" | ForEach-Object {
                if ($settings."$_") { $runAlPipelineParams += @{ "$_" = $true } }
            }

            $sharedFolder = ""
            if ($project) {
                $sharedFolder = $baseFolder
            }

            Run-AlPipeline @runAlPipelineParams `
                -accept_insiderEula:$accept_insiderEula `
                -vsixFile $settings.vsixFile `
                -pipelinename $workflowName `
                -imageName "" `
                -memoryLimit $settings.memoryLimit `
                -baseFolder $projectFolder `
                -sharedFolder $sharedFolder `
                -licenseFile $licenseFileUrl `
                -installApps $installApps `
                -installTestApps $installTestApps `
                -installOnlyReferencedApps:$settings.installOnlyReferencedApps `
                -appFolders $appFolders `
                -testFolders $testFolders `
                -testResultsFile $testResultsFile `
                -testResultsFormat 'JUnit' `
                -customCodeCops $settings.customCodeCops `
                -azureDevOps:($caller -eq 'AzureDevOps') `
                -gitLab:($caller -eq 'GitLab') `
                -gitHubActions:($caller -eq 'GitHubActions') `
                -failOn $settings.failOn `
                -treatTestFailuresAsWarnings:$settings.treatTestFailuresAsWarnings `
                -rulesetFile $settings.rulesetFile `
                -enableExternalRulesets:$settings.enableExternalRulesets `
                -AppSourceCopMandatoryAffixes $settings.appSourceCopMandatoryAffixes `
                -obsoleteTagMinAllowedMajorMinor $settings.obsoleteTagMinAllowedMajorMinor `
                -doNotRunTests `
                -doNotRunBcptTests `
                -useDevEndpoint
        }
        finally {
            Pop-Location
        }
    }
    finally {
        if ($removeEnvSecrets -and $env:Secrets) {
            Remove-Item Env:\Secrets
        }
        if (Test-Path $dependenciesFolder) {
            Get-ChildItem -Path $dependenciesFolder -Include * -File | ForEach-Object { $_.Delete() }
        }
    }
}

# This function will check and create the project folder if needed
# If project is not specified (or '.'), the root folder is used and the repository is single project
# If project is specified, check whether project folder exists and create it if it doesn't
# If no apps has been added to the repository, move the .AL-Go folder to the project folder (Convert to multi-project repository)
function CheckAndCreateProjectFolder {
    Param(
        [string] $project
    )

    if (-not $project) { $project = "." }
    if ($project -eq ".") {
        if (!(Test-Path $ALGoSettingsFile)) {
            throw "Repository is setup as a multi-project repository, but no project has been specified."
        }
    }
    else {
        $createCodeWorkspace = $false
        if (Test-Path $ALGoSettingsFile) {
            $appCount = @(Get-ChildItem -Path '.' -Filter 'app.json' -Recurse -File).Count
            if ($appCount -eq 0) {
                OutputWarning "Converting the repository to a multi-project repository as no other apps have been added previously."
                New-Item $project -ItemType Directory | Out-Null
                Move-Item -path $ALGoFolderName -Destination $project
                Set-Location $project
                $createCodeWorkspace = $true
            }
            else {
                throw "Repository is setup for a single project, cannot add a project. Move all appFolders, testFolders and the .AL-Go folder to a subdirectory in order to convert to a multi-project repository."
            }
        }
        else {
            if (!(Test-Path $project)) {
                New-Item -Path (Join-Path $project $ALGoFolderName) -ItemType Directory | Out-Null
                Set-Location $project
                OutputWarning "Project folder doesn't exist, creating a new project folder and a default settings file with country us. Please modify if needed."
                [ordered]@{
                    "country"     = "us"
                    "appFolders"  = @()
                    "testFolders" = @()
                } | Set-JsonContentLF -path $ALGoSettingsFile
                $createCodeWorkspace = $true
            }
            else {
                Set-Location $project
            }
        }
        if ($createCodeWorkspace) {
            [ordered]@{
                "folders"  = @( @{ "path" = ".AL-Go" } )
                "settings" = @{}
            } | Set-JsonContentLF -path "$project.code-workspace"
        }
    }
}

Function AnalyzeProjectDependencies {
    Param(
        [string] $baseFolder,
        [string[]] $projects
    )

    $additionalProjectsToBuild = @{}
    $projectDependencies = @{}
    $appDependencies = @{}
    Write-Host "Analyzing projects in $baseFolder"

    # Loop through all projects
    # Get all apps in the project
    # Get all dependencies for the apps
    foreach($project in $projects) {
        Write-Host "- Analyzing project: $project"

        $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
        ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $projectSettings)

        # App folders are relative to the AL-Go project folder. Convert them to relative to the base folder
        Push-Location $baseFolder
        try {
            $folders = @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders) | ForEach-Object {
                return (Resolve-Path (Join-Path $baseFolder "$project/$_") -Relative)
            }
        }
        finally {
            Pop-Location
        }

        OutputMessageAndArray -Message "Folders containing apps" -arrayOfStrings $folders

        $unknownDependencies = @()
        $apps = @()
        Sort-AppFoldersByDependencies -appFolders $folders -baseFolder $baseFolder -WarningAction SilentlyContinue -unknownDependencies ([ref]$unknownDependencies) -knownApps ([ref]$apps) | Out-Null

        # If the project is using project dependencies, add the unknown dependencies to the list of dependencies
        # If not, the unknown dependencies are ignored
        $dependenciesForProject = @()
        if ($projectSettings.useProjectDependencies -eq $true) {
            $dependenciesForProject = @($unknownDependencies | ForEach-Object { $_.Split(':')[0] })
        }

        $appDependencies."$project" = @{
            "apps"         = $apps
            "dependencies" = $dependenciesForProject
        }
    }
    # AppDependencies is a hashtable with the following structure
    # $appDependencies = @{
    #     "project1" = @{
    #         "apps" = @("appid1", "appid2")
    #         "dependencies" = @("appid3", "appid4")
    #     }
    #     "project2" = @{
    #         "apps" = @("appid5", "appid6")
    #         "dependencies" = @("appid7", "appid8")
    #     }
    # }
    $no = 1
    $projectsOrder = @()
    Write-Host "Analyzing dependencies"
    while ($projects.Count -gt 0) {
        $thisJob = @()
        # Loop through all projects and find projects that do not have dependencies on other projects in the list
        # These projects can be built in parallel and are added to the build order
        # The projects that are added to the build order are removed from the list of projects
        # The loop continues until all projects have been added to the build order
        foreach($project in $projects) {
            Write-Host "- $project"
            # Find all project dependencies for the current project
            $dependencies = $appDependencies."$project".dependencies
            # Loop through all dependencies and locate the projects, containing the apps for which the current project has a dependency
            $foundDependencies = @()
            foreach($dependency in $dependencies) {
                # Find the project that contains the app for which the current project has a dependency
                $depProjects = @($projects | Where-Object { $_ -ne $project -and $appDependencies."$_".apps -contains $dependency })
                # Add this project and all projects on which that project has a dependency to the list of dependencies for the current project
                foreach($depProject in $depProjects) {
                    $foundDependencies += $depProject
                    if ($projectDependencies.Keys -contains $depProject) {
                        $foundDependencies += $projectDependencies."$depProject"
                    }
                }
            }
            $foundDependencies = @($foundDependencies | Select-Object -Unique)
            # foundDependencies now contains all projects that the current project has a dependency on
            # Update ref variable projectDependencies for this project
            if ($projectDependencies.Keys -notcontains $project) {
                # Loop through the list of projects for which we already built a dependency list
                # Update the dependency list for that project if it contains the current project, which might lead to a changed dependency list
                # This is needed because we are looping through the projects in a any order
                $keys = @($projectDependencies.Keys)
                foreach($key in $keys) {
                    if ($projectDependencies."$key" -contains $project) {
                        $projectDeps = @( $projectDependencies."$key" )
                        $projectDependencies."$key" = @( @($projectDeps + $foundDependencies) | Select-Object -Unique )
                        if (Compare-Object -ReferenceObject $projectDependencies."$key" -differenceObject $projectDeps) {
                            Write-Host "Add ProjectDependencies $($foundDependencies -join ',') to $key"
                        }
                    }
                }
                Write-Host "Set ProjectDependencies for $project to $($foundDependencies -join ',')"
                $projectDependencies."$project" = $foundDependencies
            }
            if ($foundDependencies) {
                Write-Host "Found dependencies to projects: $($foundDependencies -join ", ")"
                # Add project to additionalProjectsToBuild for this dependency to ensure that this project also gets build when the dependency is built
                foreach($dependency in $foundDependencies) {
                    if ($additionalProjectsToBuild.Keys -contains $dependency) {
                        if ($additionalProjectsToBuild."$dependency" -notcontains $project) {
                            $additionalProjectsToBuild."$dependency" += @( $project )
                        }
                    }
                    else {
                        $additionalProjectsToBuild."$dependency" = @( $project )
                    }
                }
            }
            else {
                Write-Host "No additional dependencies found, add project to build order"
                $thisJob += $project
            }
        }
        if ($thisJob.Count -eq 0) {
            throw "Circular project reference encountered, cannot determine build order"
        }
        Write-Host "#$no - build projects: $($thisJob -join ", ")"

        $projectsOrder += @{'projects' = $thisJob; 'projectsCount' = $thisJob.Count }

        $projects = @($projects | Where-Object { $thisJob -notcontains $_ })
        $no++
    }

    return [PSCustomObject]@{
        FullProjectsOrder = $projectsOrder
        AdditionalProjectsToBuild = $additionalProjectsToBuild
        ProjectDependencies = $projectDependencies
    }
}

function GetBaseFolder {
    Param(
        [string] $folder
    )

    Push-Location $folder
    try {
        $baseFolder = invoke-git -silent rev-parse --show-toplevel -returnValue
    }
    finally {
        Pop-Location
    }

    if (!$baseFolder -or !(Test-Path (Join-Path $baseFolder '.github') -PathType Container)) {
        throw "Cannot determine base folder from folder $folder."
    }

    return $baseFolder
}

function GetProject {
    Param(
        [string] $baseFolder,
        [string] $projectALGoFolder
    )

    $projectFolder = Join-Path $projectALGoFolder '..' -Resolve
    $baseFolder = Join-Path $baseFolder '.' -Resolve
    if ($projectFolder -eq $baseFolder) {
        $project = '.'
    }
    else {
        Push-Location
        Set-Location $baseFolder
        $project = (Resolve-Path -Path $projectFolder -Relative).Substring(2)
        Pop-Location
    }
    $project
}

function DetermineArtifactUrl {
    Param(
        [hashtable] $projectSettings,
        [switch] $doNotIssueWarnings
    )

    $artifact = $projectSettings.artifact
    if ($artifact.Contains('{INSIDERSASTOKEN}')) {
        $artifact = $artifact.replace('{INSIDERSASTOKEN}', '')
        Write-Host "::Warning::Please update your artifact setting and remove {INSIDERSASTOKEN} from the setting. This is no longer needed."
    }

    Write-Host "Checking artifact setting for project"
    if ($artifact -eq "" -and $projectSettings.updateDependencies) {
        $artifact = Get-BCArtifactUrl -country $projectSettings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$projectSettings.applicationDependency } | Select-Object -First 1
        if (-not $artifact) {
            # Check Insider Artifacts
            $artifact = Get-BCArtifactUrl -storageAccount bcinsider -accept_insiderEula -country $projectSettings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$projectSettings.applicationDependency } | Select-Object -First 1
            if (-not $artifact) {
                throw "No artifacts found for application dependency $($projectSettings.applicationDependency)."
            }
        }
    }

    if ($artifact -like "https://*") {
        $artifactUrl = $artifact
        $storageAccount = ("$artifactUrl////".Split('/')[2])
        $artifactType = ("$artifactUrl////".Split('/')[3])
        $version = ("$artifactUrl////".Split('/')[4])
        $country = ("$artifactUrl////".Split('?')[0].Split('/')[5])
    }
    else {
        $segments = "$artifact/////".Split('/')
        $storageAccount = $segments[0];
        $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
        $version = $segments[2]
        $country = $segments[3]; if ($country -eq "") { $country = $projectSettings.country }
        $select = $segments[4]; if ($select -eq "") { $select = "latest" }
        if ($version -eq '*') {
            $version = "$(([Version]$projectSettings.applicationDependency).Major).$(([Version]$projectSettings.applicationDependency).Minor)"
            $allArtifactUrls = @(Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select all -accept_insiderEula | Where-Object { [Version]$_.Split('/')[4] -ge [Version]$projectSettings.applicationDependency })
            if ($select -eq 'latest') {
                $artifactUrl = $allArtifactUrls | Select-Object -Last 1
            }
            elseif ($select -eq 'first') {
                $artifactUrl = $allArtifactUrls | Select-Object -First 1
            }
            else {
                throw "Invalid artifact setting ($artifact) in $ALGoSettingsFile. Version can only be '*' if select is first or latest."
            }
            Write-Host "Found $($allArtifactUrls.Count) artifacts for version $version matching application dependency $($projectSettings.applicationDependency), selecting $select."
            if (-not $artifactUrl) {
                throw "No artifacts found for the artifact setting ($artifact) in $ALGoSettingsFile, when application dependency is $($projectSettings.applicationDependency)"
            }
        }
        else {
            $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -accept_insiderEula | Select-Object -First 1
            if (-not $artifactUrl) {
                throw "No artifacts found for the artifact setting ($artifact) in $ALGoSettingsFile"
            }
        }
        $version = $artifactUrl.Split('/')[4]
        $storageAccount = $artifactUrl.Split('/')[2]
    }

    if ($projectSettings.additionalCountries -or $country -ne $projectSettings.country) {
        if ($country -ne $projectSettings.country -and !$doNotIssueWarnings) {
            OutputWarning -message "artifact definition in $ALGoSettingsFile uses a different country ($country) than the country definition ($($projectSettings.country))"
        }
        Write-Host "Checking Country and additionalCountries"
        # AT is the latest published language - use this to determine available country codes (combined with mapping)
        $ver = [Version]$version
        Write-Host "https://$storageAccount/$artifactType/$version/$country"
        $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -accept_insiderEula
        Write-Host "Latest AT artifacts $atArtifactUrl"
        $latestATversion = $atArtifactUrl.Split('/')[4]
        $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -accept_insiderEula -select All | ForEach-Object {
            $countryArtifactUrl = $_.Split('?')[0] # remove sas token
            $countryArtifactUrl.Split('/')[5] # get country
        }
        Write-Host "Countries with artifacts $($countries -join ',')"
        $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
        Write-Host "Allowed Country codes $($allowedCountries -join ',')"
        if ($allowedCountries -notcontains $projectSettings.country) {
            throw "Country ($($projectSettings.country)), specified in $ALGoSettingsFile is not a valid country code."
        }
        $illegalCountries = $projectSettings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
        if ($illegalCountries) {
            throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $ALGoSettingsFile."
        }
        $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4], $atArtifactUrl.Split('/')[4])
    }
    return $artifactUrl
}

function RetryCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Command,
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5,
        [Object[]] $argumentList
    )

    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Invoke-Command $Command -ArgumentList $argumentList
            if ($LASTEXITCODE -ne 0) {
                $host.SetShouldExit(0);
                throw "Command failed with exit code $LASTEXITCODE"
            }
            break
        }
        catch {
            $retryCount++
            if ($retryCount -eq $MaxRetries) {
                throw
            }
            else {
                Write-Host "Retrying after $RetryDelaySeconds seconds..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
}

function GetMatchingProjects {
    Param(
        [string[]] $projects,
        [string] $selectProjects = ''
    )

    if ($selectProjects) {
        # Filter the project list based on the projects parameter
        if ($selectProjects.StartsWith('[')) {
            $selectProjects = ($selectProjects | ConvertFrom-Json) -join ","
        }
        $projectArr = $selectProjects.Split(',').Trim()
        $projects = @($projects | Where-Object { $project = $_; if ($projectArr | Where-Object { $project -like $_ }) { $project } })
    }
    return $projects
}

function GetProjectsFromRepository {
    Param(
        [string] $baseFolder,
        [string[]] $projectsFromSettings,
        [string] $selectProjects = ''
    )

    if ($projectsFromSettings) {
        $projects = $projectsFromSettings
    }
    else {
        # For multiple projects, get all folders in two levels below the base folder containing an .AL-Go folder with a settings.json file
        $projects = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 -Force | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })
        # To support single project repositories, we check for the .AL-Go folder in the root
        if (Test-Path (Join-Path $baseFolder ".AL-Go/settings.json") -PathType Leaf) {
            $projects += @(".")
        }
    }
    return @(GetMatchingProjects -projects $projects -selectProjects $selectProjects)
}

function GetFoldersFromAllProjects {
    Param(
        [string] $baseFolder
    )

    Push-Location $baseFolder
    try {
        $settings = ReadSettings -baseFolder $baseFolder
        $projects = GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $settings.projects
        $folders = @()
        foreach($project in $projects) {
            $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
            ResolveProjectFolders -baseFolder $baseFolder -project $project -projectSettings ([ref] $projectSettings)
            $folders += @( @($projectSettings.appFolders) + @($projectSettings.testFolders) + @($projectSettings.bcptTestFolders) | ForEach-Object {
                $fullPath = Join-Path $baseFolder "$project/$_" -Resolve
                $relativePath = Resolve-Path -Path $fullPath -Relative
                # Remove the leading .\ from the relative path
                return $relativePath.Substring(2)
            } )
        }
    }
    finally {
        Pop-Location
    }
    return $folders | Select-Object -Unique

}

function GetPackageVersion($packageName) {
    $projFilePath = "$PSScriptRoot\Environment.Packages.proj"

    # Check if the proj file exists
    if (-not (Test-Path $projFilePath)) {
        throw "Environment.Packages.proj file not found at $projFilePath"
    }

    # Load the XML content
    [xml]$projXml = Get-Content -Path $projFilePath

    # Find the PackageReference with the specified Include (package name)
    $packageReference = $projXml.Project.ItemGroup.PackageReference | Where-Object { $_.Include -eq $packageName }

    if ($packageReference) {
        return $packageReference.Version
    }
    else {
        throw "Package $packageName is not in the list of packages"
    }
}

function InstallAzModuleIfNeeded {
    Param(
        [string] $name,
        [System.version] $minimumVersion = $null
    )

    if ($null -eq $minimumVersion) {
        $minimumVersion = [System.Version](GetPackageVersion -packageName $name)
    }
    $azModule = Get-Module -Name $name
    if ($azModule -and $azModule.Version -ge $minimumVersion) {
        # Already installed
        return
    }
    # GitHub hosted Linux runners have AZ PowerShell module saved in /usr/share/powershell/Modules/Az.*
    if ($isWindows) {
        # GitHub hosted Windows Runners have AzureRm PowerShell modules installed (deprecated)
        # GitHub hosted Windows Runners have AZ PowerShell module saved in C:\Modules\az_*
        # Remove AzureRm modules from PSModulePath and add AZ modules
        if (Test-Path 'C:\Modules\az_*') {
            $azModulesPath = Get-ChildItem 'C:\Modules\az_*' | Where-Object { $_.PSIsContainer }
            if ($azModulesPath) {
              Write-Host "Adding AZ module path: $($azModulesPath.FullName)"
              $ENV:PSModulePath = "$($azModulesPath.FullName);$(("$ENV:PSModulePath".Split(';') | Where-Object { $_ -notlike 'C:\\Modules\Azure*' }) -join ';')"
            }
        }
    }
    InstallModule -name $name -minimumVersion $minimumVersion
}

$script:AzConnected = $false

function ConnectAz {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'GitHub Secrets come in as plain text')]
    param(
        [PsCustomObject] $azureCredentials
    )
    if ($script:AzConnected) {
        return
    }
    InstallAzModuleIfNeeded -name 'Az.KeyVault'
    try {
        Clear-AzContext -Scope Process
        Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        if ($azureCredentials.PSObject.Properties.Name -eq 'ClientSecret' -and $azureCredentials.ClientSecret) {
            Write-Host "Connecting to Azure using clientId and clientSecret."
            $credential = New-Object pscredential -ArgumentList $azureCredentials.ClientId, (ConvertTo-SecureString -string $azureCredentials.ClientSecret -AsPlainText -Force)
            Connect-AzAccount -ServicePrincipal -Tenant $azureCredentials.TenantId -Credential $credential -WarningAction SilentlyContinue | Out-Null
        }
        else {
            try {
                Write-Host "Query federated token"
                $result = Invoke-RestMethod -Method GET -UseBasicParsing -Headers @{ "Authorization" = "bearer $ENV:ACTIONS_ID_TOKEN_REQUEST_TOKEN"; "Accept" = "application/vnd.github+json" } -Uri "$ENV:ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
            }
            catch {
                throw "Unable to get federated token, maybe id_token: write permissions are missing. Error was $($_.Exception.Message)"
            }
            Write-Host "Connecting to Azure using clientId and federated token."
            Connect-AzAccount -ApplicationId $azureCredentials.ClientId -Tenant $azureCredentials.TenantId -FederatedToken $result.value -WarningAction SilentlyContinue | Out-Null
        }
        if ($azureCredentials.PSObject.Properties.Name -eq 'SubscriptionId' -and $azureCredentials.SubscriptionId) {
            Write-Host "Selecting subscription $($azureCredentials.SubscriptionId)"
            Set-AzContext -SubscriptionId $azureCredentials.SubscriptionId -Tenant $azureCredentials.TenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
        }
        $script:AzConnected = $true
        Write-Host "Successfully connected to Azure"
    }
    catch {
        throw "Error trying to authenticate to Azure. Error was $($_.Exception.Message)"
    }
}

function OutputMessageAndArray {
    Param(
        [string] $message,
        [string[]] $arrayOfStrings
    )
    Write-Host "$($message):"
    if (!$arrayOfStrings) {
        Write-Host "- None"
    }
    else {
        $arrayOfStrings | ForEach-Object {
            Write-Host "- $_"
        }
    }
}

<#
.SYNOPSIS
Run an executable and check the exit code
.EXAMPLE
RunAndCheck git checkout -b xxx
#>
function RunAndCheck {
    $ErrorActionPreference = 'SilentlyContinue'
    $rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { $null }
    & $args[0] $rest
    $ErrorActionPreference = 'STOP'
    if ($LASTEXITCODE -ne 0) {
        $host.SetShouldExit(0)
        throw "$($args[0]) $($rest | ForEach-Object { $_ }) failed with exit code $LASTEXITCODE"
    }
}
