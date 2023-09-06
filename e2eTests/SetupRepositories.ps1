Param(
    [string] $githubOwner,
    [string] $token,
    [string] $bcContainerHelperVersion = ''
)

Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

$repoBaseName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Write-Host $repoBaseName

$actionsRepo = "$repoBaseName-Actions"
$perTenantExtensionRepo = "$repoBaseName-PTE"
$appSourceAppRepo = "$repoBaseName-AppSource"

$config = [ordered]@{
    "githubOwner" = $githubOwner
    "actionsRepo" = $actionsRepo
    "perTenantExtensionRepo" = $perTenantExtensionRepo
    "appSourceAppRepo" = $appSourceAppRepo
    "branch" = "main"
    "localFolder" = ""
    "baseFolder" = [System.IO.Path]::GetTempPath()
    "defaultBcContainerHelperVersion" = $bcContainerHelperVersion
}

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -config $config -token $token -DirectCommit $true

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "actionsRepo=$actionsRepo"
Write-Host "actionsRepo=$actionsRepo"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "perTenantExtensionRepo=$perTenantExtensionRepo"
Write-Host "perTenantExtensionRepo=$perTenantExtensionRepo"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "appSourceAppRepo=$appSourceAppRepo"
Write-Host "appSourceAppRepo=$appSourceAppRepo"
