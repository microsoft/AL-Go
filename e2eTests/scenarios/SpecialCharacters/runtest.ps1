[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText),
    [string] $licenseFileUrl = ($global:SecureLicenseFileUrl | Get-PlainText),
    [string] $insiderSasToken = ($global:SecureInsiderSasToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#   _____                 _       _    _____ _                          _
#  / ____|               (_)     | |  / ____| |                        | |
# | (___  _ __   ___  ___ _  __ _| | | |    | |__   __ _ _ __ __ _  ___| |_ ___ _ __ ___
#  \___ \| '_ \ / _ \/ __| |/ _` | | | |    | '_ \ / _` | '__/ _` |/ __| __/ _ \ '__/ __|
#  ____) | |_) |  __/ (__| | (_| | | | |____| | | | (_| | | | (_| | (__| ||  __/ |  \__ \
# |_____/| .__/ \___|\___|_|\__,_|_|  \_____|_| |_|\__,_|_|  \__,_|\___|\__\___|_|  |___/
#        | |
#        |_|
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with 1 app
#    - Æøå-app with publisher Süß
#    - Set RepoName to Privé
#  - Run the "CI/CD" workflow
#  - Check artifacts generated
#  - Set runs-on to ubuntu-latest (and use CompilerFolder)
#  - Run the "CI/CD" workflow again
#  - Check artifacts generated
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

$appName = 'Æøå-app'
$publisherName = 'Süß'
$RepoName = 'Privé'

# Create repository1
CreateAlGoRepository `
    -github:$github `
    -template $template `
    -repository $repository `
    -branch $branch `
    -contentScript {
        Param([string] $path)
        $null = CreateNewAppInFolder -folder $path -name $appName -publisher $publisherName
        Add-PropertiesToJsonFile -path (Join-Path $path '.github/AL-Go-Settings.json') -properties @{ "RepoName" = $repoName }
    }

$repoPath = (Get-Location).Path
$run = RunCICD -repository $repository -branch $branch

# Wait for CI/CD workflow of repository1 to finish
WaitWorkflow -repository $repository -runid $run.id

# test artifacts generated in repository1
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=0} -repoVersion '1.0' -appVersion '1.0'
Push-Location "artifacts/$repoName-main-Apps-1.0*"
Get-Item -Path "$($publisherName)_$($appName)_1.0*" | Should -Not -BeNullOrEmpty
Pop-Location

# Remove downloaded artifacts
Remove-Item -Path 'artifacts' -Recurse -Force

Pull

# Set GitHubRunner and runs-on to ubuntu-latest (and use CompilerFolder)
Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "runs-on" = "ubuntu-latest"; "gitHubRunner" = "ubuntu-latest"; "UseCompilerFolder" = $true; "doNotPublishApps" = $true }

# Push
CommitAndPush -commitMessage 'Shift to Linux'

# Upgrade AL-Go System Files
RunUpdateAlGoSystemFiles -directCommit -commitMessage 'Update system files' -wait -templateUrl $template

$run = RunCICD -repository $repository -branch $branch -wait

# test artifacts generated in repository1
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=0} -repoVersion '1.0' -appVersion '1.0'
Push-Location "artifacts/$repoName-main-Apps-1.0*"
Get-Item -Path "$($publisherName)_$($appName)_1.0*" | Should -Not -BeNullOrEmpty
Pop-Location

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
