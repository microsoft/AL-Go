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
#  ____        _ _     _ __  __           _
# |  _ \      (_) |   | |  \/  |         | |
# | |_) |_   _ _| | __| | \  / | ___   __| | ___  ___
# |  _ <| | | | | |/ _` | |\/| |/ _ \ / _` |/ _ \/ __|
# | |_) | |_| | | | (_| | |  | | (_) | (_| |  __/\__ \
# |____/ \__,_|_|_|\__,_|_|  |_|\___/ \__,_|\___||___/
#
#
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with a single project HelloWorld app
#    - add BuildModes and CleanModePreprocessorSymbols to the repo settings
#  - Run the "CI/CD" workflow
#  - Test artifacts generated, that there are 3 types of artifacts
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location
$repoPath = ""

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
CreateAlGoRepository `
    -github:$github `
    -linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -addRepoSettings @{"buildModes" = @("Clean", "Default", "Translated" ); "cleanModePreprocessorSymbols" = @( "CLEAN" )} `
    -contentScript {
        Param([string] $path)
        CreateNewAppInFolder -folder $path -name "App" | Out-Null
    }
$repoPath = (Get-Location).Path
Start-Process $repoPath

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"CleanApps"=1;"TranslatedApps"=1} -repoVersion '1.0' -appVersion '1.0'

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
