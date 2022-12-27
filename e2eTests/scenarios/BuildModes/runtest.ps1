Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = "$(invoke-git config user.name -silent -returnValue)/AL-Go-PTE@main",
    [string] $appSourceTemplate = "$(invoke-git config user.name -silent -returnValue)/AL-Go-AppSource@main",
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
#  - Create a new repository based on the PTE template with the content from the content folder (single project HelloWorld app)
#  - Run Update AL-Go System Files to apply settings from the app
#  - Run the "CI/CD" workflow
#  - Test that runs were successful and artifacts were created
#  - Cleanup repositories
#
'@
  
$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0
$prevLocation = Get-Location
$repoPath = ""

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$($pteTemplate)@main"
$runs = 0

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
CreateRepository -template $template -repository $repository -branch $branch -contentPath (Join-Path $PSScriptRoot 'content')
$repoPath = (Get-Location).Path
$runs++

# Update AL-Go System Files
Run-UpdateAlGoSystemFiles -templateUrl $template -repository $repository -branch $branch -ghTokenWorkflow $token -directCommit -wait | Out-Null
$runs++

# Run CI/CD workflow
$run = Run-CICD -repository $repository -branch $branch -wait
$runs++

Test-NumberOfRuns -expectedNumberOfRuns $runs
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"CleanApps"=1;"TranslatedApps"=1} -repoVersion '1.0' -appVersion '1.0'

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
