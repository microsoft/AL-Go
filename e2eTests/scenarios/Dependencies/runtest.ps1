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
#   _____ _ _   _    _       _       _____           _                         
#  / ____(_) | | |  | |     | |     |  __ \         | |                        
# | |  __ _| |_| |__| |_   _| |__   | |__) |_ _  ___| | ____ _  __ _  ___  ___ 
# | | |_ | | __|  __  | | | | '_ \  |  ___/ _` |/ __| |/ / _` |/ _` |/ _ \/ __|
# | |__| | | |_| |  | | |_| | |_) | | |  | (_| | (__|   < (_| | (_| |  __/\__ \
#  \_____|_|\__|_|  |_|\__,_|_.__/  |_|   \__,_|\___|_|\_\__,_|\__, |\___||___/
#                                                               __/ |          
#                                                              |___/           
# This test tests the following scenario:
#                                                                                                      
#  - Create a new repository based on the PTE template with the content from the common folder
#  - Set GitHubPackagesContext secret in common repo
#  - Run the "CI/CD" workflow in common repo
#  - Create a new repository based on the PTE template with the content from the w1 folder
#  - Set GitHubPackagesContext secret in w1 repo
#  - Create a new repository based on the PTE template with the content from the dk folder
#  - Set GitHubPackagesContext secret in dk repo
#  - Wait for "CI/CD" workflow from common repo to complete
#  - Check artifacts generated in common repo
#  - Run the "CI/CD" workflow from w1 repo and wait for completion
#  - Check artifacts generated in w1 repo
#  - Run the "CI/CD" workflow from dk repo and wait for completion
#  - Check artifacts generated in dk repo
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

$commonRepository = "$repository.Common"
$w1Repository = "$repository.W1"
$githubPackagesContext = @{
    "serverUrl"="https://nuget.pkg.github.com/$githubOwner/index.json"
    "token"=$token
}
$githubPackagesContextJson = ($githubPackagesContext | ConvertTo-Json -Compress)

# Create common repo
CreateRepository -linux -template $template -repository $commonRepository -branch $branch -contentPath (Join-Path $PSScriptRoot 'Common') -applyAlGoSettings @{ "country" = "w1" }
SetRepositorySecret -repository $commonRepository -name 'GitHubPackagesContext' -value $githubPackagesContextJson
$commonRepoPath = (Get-Location).Path
$commonRun = Run-CICD -repository $commonRepository -branch $branch

# Create W1 repo
CreateRepository -linux -template $template -repository $w1Repository -branch $branch -contentPath (Join-Path $PSScriptRoot 'W1') -applyAlGoSettings @{ "country" = "w1" }
SetRepositorySecret -repository $w1Repository -name 'GitHubPackagesContext' -value $githubPackagesContextJson
$w1RepoPath = (Get-Location).Path

# Create DK repo
CreateRepository -linux -template $template -repository $repository -branch $branch -contentPath (Join-Path $PSScriptRoot 'DK') -applyRepoSettings @{ "generateDependencyArtifact" = $true } -applyAlGoSettings @{ "country" = "dk" }
SetRepositorySecret -repository $repository -name 'GitHubPackagesContext' -value $githubPackagesContextJson
$repoPath = (Get-Location).Path

Set-Location $commonRepoPath
# Wait for CI/CD workflow of Common to finish
WaitWorkflow -repository $commonRepository -runid $commonRun.id
$runs++
Test-ArtifactsFromRun -runid $commonRun.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=0} -repoVersion '1.0' -appVersion '1.0'

Set-Location $w1RepoPath
$w1Run = Run-CICD -repository $w1Repository -branch $branch -wait
Test-ArtifactsFromRun -runid $w1Run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=0} -repoVersion '1.0' -appVersion '1.0'

Set-Location $repoPath
$run = Run-CICD -repository $repository -branch $branch -wait
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=3} -repoVersion '1.0' -appVersion '1.0'

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
RemoveRepository -repository $w1repository -path $w1RepoPath
RemoveRepository -repository $commonRepository -path $commonRepoPath
