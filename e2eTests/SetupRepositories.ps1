Param(
    [switch] $github,
    [string] $githubOwner,
    [string] $token
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
}

$settingsFile = Join-Path $settings.baseFolder "$repoBaseName.json"
$settings | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -configName $settingsFile -githubOwner $githubOwner -token $token -github:$github

Write-Host "::set-output name=actionsRepo::$actionsRepo"
Write-Host "::set-output name=perTenantExtensionRepo::$perTenantExtensionRepo"
Write-Host "::set-output name=appSourceAppRepo::$appSourceAppRepo"
Write-Host "set-output name=actionsRepo::$actionsRepo"
Write-Host "set-output name=perTenantExtensionRepo::$perTenantExtensionRepo"
Write-Host "set-output name=appSourceAppRepo::$appSourceAppRepo"
