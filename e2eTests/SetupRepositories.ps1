Param(
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

. (Join-Path $PSScriptRoot "..\Internal\Deploy.ps1") -configName $settingsFile -confirm -githubOwner $githubOwner -token $token

Write-Host "::set-output name=actionsRepo::https://github.com/$githubOwner/$actionsRepo"
Write-Host "::set-output name=perTenantExtensionRepo::https://github.com/$githubOwner/$perTenantExtensionRepo"
Write-Host "::set-output name=appSourceAppRepo::https://github.com/$githubOwner/$appSourceAppRepo"
Write-Host "set-output name=actionsRepo::https://github.com/$githubOwner/$actionsRepo"
Write-Host "set-output name=perTenantExtensionRepo::https://github.com/$githubOwner/$perTenantExtensionRepo"
Write-Host "set-output name=appSourceAppRepo::https://github.com/$githubOwner/$appSourceAppRepo"
