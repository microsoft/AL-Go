﻿[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#  ______       _                _           _    _____              _            _   _       _
# |  ____|     | |              | |         | |  / ____|            | |          | | (_)     | |
# | |__ ___  __| | ___ _ __ __ _| |_ ___  __| | | |     _ __ ___  __| | ___ _ __ | |_ _  __ _| |___
# |  __/ _ \/ _` |/ _ \ '__/ _` | __/ _ \/ _` | | |    | '__/ _ \/ _` |/ _ \ '_ \| __| |/ _` | / __|
# | | |  __/ (_| |  __/ | | (_| | ||  __/ (_| | | |____| | |  __/ (_| |  __/ | | | |_| | (_| | \__ \
# |_|  \___|\__,_|\___|_|  \__,_|\__\___|\__,_|  \_____|_|  \___|\__,_|\___|_| |_|\__|_|\__,_|_|___/
#
#
#
# This test uses the bcsamples-bingmaps.appsource repository and will deliver a new build of the app to AppSource.
# The bcsamples-bingmaps.appsource repository is setup to use an Azure KeyVault for secrets and app signing.
# The bcSamples-bingmaps.appsource repository is setup for continuous delivery to AppSource
# This test will deliver another build of the latest app version already delivered to AppSource (without go-live)
#
# This test tests the following scenario:
#
# bcsamples-bingmaps.appsource is setup to use an Azure KeyVault for secrets and app signing
# Access to the Azure KeyVault is using federated credentials (branches main and e2e)
# bcsamples-bingmaps.appsource is using a Entra ID app registration for delivering to AppSource
# The Entra ID app registration is using federated credentials (branches main and e2e)
#
#  - Remove branch e2e in repository microsoft/bcsamples-bingmaps.appsource (if it exists)
#  - Create a new branch called e2e in repository microsoft/bcsamples-bingmaps.appsource (based on main)
#  - Update AL-Go System Files in branch e2e in repository microsoft/bcsamples-bingmaps.appsource
#  - Invoke CI/CD in branch e2e in repository microsoft/bcsamples-bingmaps.appsource
#  - Check that artifacts are created and signed
#  - Check that the app is delivered to AppSource
#  - Remove the branch e2e in repository microsoft/bcsamples-bingmaps.appsource
#
'@

function GetNavSipFromArtifacts([string] $NavSipDestination) {
    Write-Host "Download core artifacts"
    $artifactUrl = Get-BCArtifactUrl -country core
    $artifactTempFolder = Download-Artifacts -artifactUrl $artifactUrl
    Write-Host "Downloaded artifacts to $artifactTempFolder"
    $navsip = Get-ChildItem -Path $artifactTempFolder -Filter "navsip.dll" -Recurse
    Write-Host "Found navsip at $($navsip.FullName)"
    Copy-Item -Path $navsip.FullName -Destination $NavSipDestination -Force | Out-Null
    Write-Host "Copied navsip to $NavSipDestination"
}

function Register-NavSip() {
    $navSipDestination = "C:\Windows\System32"
    $navSipDllPath = Join-Path $navSipDestination "navsip.dll"
    try {
        if (-not (Test-Path $navSipDllPath)) {
            GetNavSipFromArtifacts -NavSipDestination $navSipDllPath
            $vcredist_x64_140url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
            $vcredist_x64_exe = Join-Path $ENV:GITHUB_WORKSPACE 'vcredist_x64_140.exe'
            try {
                Write-Host "Downloading $vcredist_x64_exe"
                Invoke-RestMethod -Method Get -UseBasicParsing -Uri $vcredist_x64_140url -OutFile $vcredist_x64_exe
                Write-Host "Installing $vcredist_x64_exe"
                $process = start-process -Wait -FilePath $vcredist_x64_exe -ArgumentList /q, /norestart
                if (($null -ne $process.ExitCode) -and ($process.ExitCode -ne 0)) {
                    Write-Host "Failed to install $vcredist_x64_exe. Exit code was $($process.ExitCode)"
                }
            }
            finally {
                if (Test-Path $vcredist_x64_exe) {
                    Remove-Item $vcredist_x64_exe
                }
            }
        }
        Write-Host "Unregistering dll $navSipDllPath"
        RegSvr32 /u /s $navSipDllPath
        Write-Host "Registering dll $navSipDllPath"
        RegSvr32 /s $navSipDllPath
    }
    catch {
        Write-Host "Failed to copy navsip to $navSipDestination. Error was $($_.Exception.Message)"
    }
}

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking
. (Join-Path $PSScriptRoot "..\..\..\Actions\AL-Go-Helper.ps1" -Resolve)

Write-Host "Download and install BcContainerHelper"
DownloadAndImportBcContainerHelper

Get-BCArtifactUrl -country core | Out-Host

# Check app signature
Write-Host "Register NavSip.dll"
Register-NavSip


$branch = "e2e"
$template = "https://github.com/$appSourceTemplate"
$repository = 'microsoft/bcsamples-bingmaps.appsource'

SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository
$headers = @{
    "Authorization" = "token $token"
    "X-GitHub-Api-Version" = "2022-11-28"
    "Accept" = "application/vnd.github+json"
}
$existingBranch = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$repository/branches/$branch 2> $null | ConvertFrom-Json
if ($existingBranch.PSObject.Properties.Name -eq 'Name' -and $existingBranch.Name -eq $branch) {
    Write-Host "Removing existing branch $branch"
    Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repository/git/refs/heads/$branch" -Headers $headers
    Start-Sleep -Seconds 10
}
$latestSha = (gh api /repos/$repository/commits/main | ConvertFrom-Json).sha
gh api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$repository/git/refs -f ref=refs/heads/$branch -f sha=$latestSha

# Upgrade AL-Go System Files to test version
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -repository $repository -branch $branch | Out-Null

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch -wait

# Check that workflow run uses federated credentials and signing was successful
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)  Main App (Default)' -stepName 'Sign' -expectedText 'Connecting to Azure using clientId and federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)  Main App (Default)' -stepName 'Sign' -expectedText 'Signing succeeded'

# Check that Deliver to AppSource uses federated credentials and that a new submission was created
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Read secrets' -expectedText 'Query federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Deliver' -expectedText 'New AppSource submission created'

# Test artifacts generated
$artifacts = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$repository/actions/runs/$($run.id)/artifacts | ConvertFrom-Json
@($artifacts.artifacts.Name) -like "Library Apps-$branch-Apps-*.*.*.0" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-$branch-Apps-*.*.*.0" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-$branch-Dependencies-*.*.*.0" | Should -Be $true

Write-Host "Download build artifacts"
invoke-gh run download $run.id --repo $repository --dir 'signedApps'
$appFile = (Get-Item "signedApps/Main App-$branch-Apps-*.*.*.0/*.app").FullName

Write-Host "Check App Signature $appFile"
$signResult = Get-AuthenticodeSignature -FilePath $appFile
$signResult | Out-Host
$signResult.Status | Should -Be 'Valid'

Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repository/git/refs/heads/$branch" -Headers $headers
