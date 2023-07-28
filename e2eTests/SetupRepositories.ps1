Param(
    [switch] $github,
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

$settings = [ordered]@{
    "githubOwner" = $githubOwner
    "actionsRepo" = $actionsRepo
    "perTenantExtensionRepo" = $perTenantExtensionRepo
    "appSourceAppRepo" = $appSourceAppRepo
    "branch" = "main"
    "localFolder" = ""
    "baseFolder" = [System.IO.Path]::GetTempPath()
    "defaultBcContainerHelperVersion" = $bcContainerHelperVersion
}

$settingsFile = Join-Path $settings.baseFolder "$repoBaseName.json"
$settings | Set-JsonContentLF -path $settingsFile

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -configName $settingsFile -githubOwner $githubOwner -token $token -github:$github

Write-Host "OUTPUTS:"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "actionsRepo=$actionsRepo"
Write-Host "- actionsRepo=$actionsRepo"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "perTenantExtensionRepo=$perTenantExtensionRepo"
Write-Host "- perTenantExtensionRepo=$perTenantExtensionRepo"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "appSourceAppRepo=$appSourceAppRepo"
Write-Host "- appSourceAppRepo=$appSourceAppRepo"
