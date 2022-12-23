Param(
    [string] $githubOwner,
    [string] $token,
    [string] $bcContainerHelperVersion = ''
)

$repoBaseName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Write-Host $repoBaseName

$actionsRepo = "$repoBaseName-Actions"
$perTenantExtensionRepo = "$repoBaseName-PTE"
$appSourceAppRepo = "$repoBaseName-AppSource"

[System.IO.Path]::GetTempPath()

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
$settings | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -configName $settingsFile -githubOwner $githubOwner -token $token -github

Add-Content -Path $env:GITHUB_OUTPUT -Value "actionsRepo=$actionsRepo"
Write-Host "actionsRepo=$actionsRepo"
Add-Content -Path $env:GITHUB_OUTPUT -Value "perTenantExtensionRepo=$perTenantExtensionRepo"
Write-Host "perTenantExtensionRepo=$perTenantExtensionRepo"
Add-Content -Path $env:GITHUB_OUTPUT -Value "appSourceAppRepo=$appSourceAppRepo"
Write-Host "appSourceAppRepo=$appSourceAppRepo"
