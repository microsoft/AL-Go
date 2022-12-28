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
#  _    _          _____           _           _   _____                            _                 _           
# | |  | |        |  __ \         (_)         | | |  __ \                          | |               (_)          
# | |  | |___  ___| |__) | __ ___  _  ___  ___| |_| |  | | ___ _ __   ___ _ __   __| | ___ _ __   ___ _  ___  ___ 
# | |  | / __|/ _ \  ___/ '__/ _ \| |/ _ \/ __| __| |  | |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| |/ _ \/ __|
# | |__| \__ \  __/ |   | | | (_) | |  __/ (__| |_| |__| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |  __/\__ \
#  \____/|___/\___|_|   |_|  \___/| |\___|\___|\__|_____/ \___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|_|\___||___/
#                                _/ |                         | |                                                 
#                               |__/                          |_|                                                 #
# This test tests the following scenario:
#                                                                                                      
#  - Create a new repository based on the PTE template with the content from the content folder
#  - Run Update AL-Go System Files to apply settings from the repo
#  - Run the "CI/CD" workflow
#  - Run the Test Current Workflow
#  - Run the Test Next Minor Workflow
#  - Run the Test Next Major Workflow
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

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
CreateRepository -template $template -branch $branch -contentPath (Join-Path $PSScriptRoot 'content')
$repoPath = (Get-Location).Path

# Update AL-Go System Files to uptake UseProjectDependencies setting
Run-UpdateAlGoSystemFiles -templateUrl $template -wait -branch $branch -directCommit -ghTokenWorkflow $token | Out-Null

# Run CI/CD workflow
$run = Run-CICD -branch $branch

# Launch Current, NextMinor and NextMajor builds
$runTestCurrent = Run-TestCurrent -branch $branch
$runTestNextMinor = Run-TestNextMinor -branch $branch -insiderSasToken $insiderSasToken
$runTestNextMajor = Run-TestNextMajor -branch $branch -insiderSasToken $insiderSasToken

# Wait for all workflows to finish
WaitWorkflow -runid $run.id
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=6;"thisbuild"=6} -repoVersion '1.0' -appVersion '1.0'

WaitWorkflow -runid $runTestCurrent.id
Test-ArtifactsFromRun -runid $runTestCurrent.id -folder 'currentartifacts' -expectedArtifacts @{"Apps"=0;"thisbuild"=6} -repoVersion '1.0' -appVersion '1.0'

WaitWorkflow -runid $runTestNextMinor.id
Test-ArtifactsFromRun -runid $runTestNextMinor.id -folder 'nextminorartifacts' -expectedArtifacts @{"Apps"=0;"thisbuild"=6} -repoVersion '1.0' -appVersion '1.0'

WaitWorkflow -runid $runTestNextMajor.id
Test-ArtifactsFromRun -runid $runTestNextMajor.id -folder 'nextmajorartifacts' -expectedArtifacts @{"Apps"=0;"thisbuild"=6} -repoVersion '1.0' -appVersion '1.0'

Set-Location $prevLocation

#RemoveRepository -repository $repository -path $repoPath
