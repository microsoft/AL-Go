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

# Adding a blank line here for PoC