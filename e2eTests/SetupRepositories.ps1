Param(
    [string] $actor,
    [string] $token
)

$repoBaseName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Write-Host $repoBaseName

$githubOwner = "freddydk"
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

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -configName $settingsFile -confirm -actor $actor -token $token

Write-Host "::set-output name=actionsRepo::$githubOwner/$actionsRepo"
Write-Host "::set-output name=perTenantExtensionRepo::$githubOwner/$perTenantExtensionRepo"
Write-Host "::set-output name=appSourceAppRepo::$githubOwner/$appSourceAppRepo"
Write-Host "set-output name=actionsRepo::$githubOwner/$actionsRepo"
Write-Host "set-output name=perTenantExtensionRepo::$githubOwner/$perTenantExtensionRepo"
Write-Host "set-output name=appSourceAppRepo::$githubOwner/$appSourceAppRepo"

