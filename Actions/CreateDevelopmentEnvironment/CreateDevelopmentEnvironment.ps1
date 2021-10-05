Param(
    [string] $actor,
    [string] $token,
    [string] $environmentName,
    [string] $adminCenterApiCredentials,
    [bool] $reUseExistingEnvironment,
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $baseFolder = Get-Location

    Write-Host "Reading $ALGoSettingsFile"
    $settingsJson = Get-Content $ALGoSettingsFile | ConvertFrom-Json

    CreateDevEnv `
        -kind cloud `
        -caller GitHubActions `
        -environmentName $environmentName `
        -reUseExistingEnvironment:$reUseExistingEnvironment `
        -baseFolder $baseFolder `
        -adminCenterApiCredentials ($adminCenterApiCredentials | ConvertFrom-Json | ConvertTo-HashTable)

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Create Development Environment $environmentName" -branch $branch
}
catch {
    OutputError -message "Couldn't create development environment. Error was $($_.Exception.Message)"
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
