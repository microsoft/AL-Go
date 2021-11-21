Param(
    [switch] $github,
    [string] $githubOwner = "",
    [string] $token = "",
    [string] $path = "",
    [string] $template = "",
    [string] $licenseFileUrl = "",
    [switch] $appSourceApp
)

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

    if (!$github) {
        if (!$token) {  $token = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "OrgPAT").SecretValue | Get-PlainText }
        $githubOwner = "freddydk"
        if (!$licenseFileUrl -and $appSourceApp) { $licenseFileUrl = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "licenseFile").SecretValue | Get-PlainText }
        $path = "testpte-v0"
    }

    $reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
    $repository = "$githubOwner/$repoName"
    $branch = "main"

    if ($appSourceApp) {
        if (!$template) { $template = 'al-go-appSource' }
        if (!$licenseFileUrl) {
            throw "License file secret must be set"
        }
    }
    else {
        if (!$template) { $template = 'al-go-pte' }
        if ($licenseFileUrl) {
            throw "License file secret should not be set"
        }
    }
    $template = "https://github.com/$githubOwner/$template"
    $runs = 0

    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    # Create repo
    CreateRepository -templatePath (Join-Path $PSScriptRoot $path) -branch $branch
    $repoPath = (Get-Location).Path

    # Add Existing App
    if ($appSourceApp) {
        SetRepositorySecret -name 'LICENSEFILEURL' -value (ConvertTo-SecureString -String $licenseFileUrl -AsPlainText -Force)
    }

    # Run CI/CD and wait
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 1 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''

    # Update AL-Go System Files
    SetRepositorySecret -name 'GHTOKENWORKFLOW' -value (ConvertTo-SecureString -String $token -AsPlainText -Force)
    Run-UpdateAlGoSystemFiles -templateUrl $template -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs += 2

    # Run CI/CD and wait
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 1 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''
    
    Test-NumberOfRuns -expectedNumberOfRuns $runs
    
    RemoveRepository -repository $repository -path $repoPath
}
catch {
    Write-Host $_.Exception.Message
    Write-Host "::Error::$($_.Exception.Message)"
    if ($github) {
        $host.SetShouldExit(1)
    }
}
