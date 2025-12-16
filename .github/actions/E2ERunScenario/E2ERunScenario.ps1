Param(
    [Parameter(HelpMessage = "Scenario name", Mandatory = $true)]
    [string] $scenario,
    [Parameter(HelpMessage = "Run on Linux", Mandatory = $false)]
    [bool] $linux = $false,
    [Parameter(HelpMessage = "GitHub owner", Mandatory = $true)]
    [string] $githubOwner,
    [Parameter(HelpMessage = "Repository name", Mandatory = $true)]
    [string] $repoName,
    [Parameter(HelpMessage = "E2E App ID", Mandatory = $true)]
    [string] $e2eAppId,
    [Parameter(HelpMessage = "E2E App Key", Mandatory = $true)]
    [string] $e2eAppKey, # [SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification='GitHub Actions secrets are already masked in logs')]
    [Parameter(HelpMessage = "ALGO Auth App", Mandatory = $true)]
    [string] $algoAuthApp, # [SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification='GitHub Actions secrets are already masked in logs')]
    [Parameter(HelpMessage = "PTE template", Mandatory = $true)]
    [string] $pteTemplate,
    [Parameter(HelpMessage = "AppSource template", Mandatory = $true)]
    [string] $appSourceTemplate,
    [Parameter(HelpMessage = "Admin center API credentials", Mandatory = $true)]
    [string] $adminCenterApiCredentials, # [SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification='GitHub Actions secrets are already masked in logs')]
    [Parameter(HelpMessage = "Azure credentials", Mandatory = $true)]
    [string] $azureCredentials, # [SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification='GitHub Actions secrets are already masked in logs')]
    [Parameter(HelpMessage = "GitHub packages token", Mandatory = $true)]
    [string] $githubPackagesToken # [SuppressMessage('PSAvoidUsingPlainTextForPassword', '', Justification='GitHub Actions secrets are already masked in logs')]
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

try {
    $params = @{
        'github' = $true
        'githubOwner' = $githubOwner
        'repoName' = $repoName
        'e2eAppId' = $e2eAppId
        'e2eAppKey' = $e2eAppKey
        'algoauthapp' = $algoAuthApp
        'pteTemplate' = $pteTemplate
        'appSourceTemplate' = $appSourceTemplate
        'adminCenterApiCredentials' = $adminCenterApiCredentials
        'azureCredentials' = $azureCredentials
        'githubPackagesToken' = $githubPackagesToken
    }

    if ($linux) {
        $params['linux'] = $true
    }

    . (Join-Path "." "e2eTests/scenarios/$scenario/runtest.ps1") @params
}
catch {
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    Write-Host "::Error::$($_.Exception.Message)"
    $host.SetShouldExit(1)
}
