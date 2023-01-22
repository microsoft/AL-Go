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
# _____      _                     ____                       _               
#|  __ \    | |                   |  _ \                     | |              
#| |__) |___| | ___  __ _ ___  ___| |_) |_ __ __ _ _ __   ___| |__   ___  ___ 
#|  _  // _ \ |/ _ \/ _` / __|/ _ \  _ <| '__/ _` | '_ \ / __| '_ \ / _ \/ __|
#| | \ \  __/ |  __/ (_| \__ \  __/ |_) | | | (_| | | | | (__| | | |  __/\__ \
#|_|  \_\___|_|\___|\__,_|___/\___|____/|_|  \__,_|_| |_|\___|_| |_|\___||___/
#                                                                             
#
# This test tests the following scenario:
#                                                                                                      
#  - Create a new repository based on the PTE template with a single project HelloWorld app
#  - Run the "CI/CD" workflow
#    - Check that no previous release was found
#  - Release version 1.0 and update version number to 2.0
#  - Run the CI/CD workflow main branch
#    - Check that v1.0 was used as previous release
#  - Release version 2.0 and update version number to 2.1
#  - Run the CI/CD workflow main branch
#    - Check that v2.0 was used as previous release
#  - Run the CI/CD workflow in release branch 1.0.0
#    - Check that v1.0 was used as previous release
#  - Run the CI/CD workflow in release branch 2.0.0
#    - Check that v2.0 was used as previous release
#  - CreateRelease hotfix 1.0.1
#
#
#
#
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
CreateAlGoRepository `
    -github:$github `
    -linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -contentScript {
        Param([string] $path)
        CreateNewAppInFolder -folder $path -name "App" | Out-Null
    }
$repoPath = (Get-Location).Path
Start-Process $repoPath

# Run CI/CD workflow
$run = Run-CICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'

# Check that no previous release was found
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText '[Warning]No previous release found'

# Release version 1.0
$tag1 = '1.0.0'
$ver1 = 'v1.0'
$releaseBranch1 = "release/1.0"
Run-CreateRelease -repository $repository -branch $branch -appVersion 'latest' -name $ver1 -tag $tag1 -createReleaseBranch -updateVersionNumber '+1.0' -directCommit -wait

# Run CI/CD workflow
$run = Run-CICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '2.0' -appVersion '2.0'

# Check that $tag1 was used as previous release
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText "Using $ver1 (tag $tag1) as previous release"

# Release version 2.0
$tag2 = '2.0.0'
$ver2 = 'v2.0'
$releaseBranch2 = "release/2.0"
Run-CreateRelease -repository $repository -branch $branch -appVersion 'latest' -name $ver2 -tag $tag2 -createReleaseBranch -updateVersionNumber '+0.1' -directCommit -wait

# Run CI/CD workflow
$run = Run-CICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '2.1' -appVersion '2.1'

# Check that $tag2 was used as previous release
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText "Using $ver2 (tag $tag2) as previous release"

# Run CI/CD workflow in release branch 1.0.0
$runRelease1 = Run-CICD -repository $repository -branch $releaseBranch1 -wait

Test-ArtifactsFromRun -runid $runRelease1.id -folder 'artifacts1' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts1' -filter '*-release_1.0.0-Apps-1.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact1, but found $noOfReleaseArtifacts"
}

# Check that $tag1 was used as previous release for builds in release branch 1.0.0
Test-LogContainsFromRun -runid $runRelease1.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText "Using $ver1 (tag $tag1) as previous release"

# Run CI/CD workflow in release branch 2.0.0
$runRelease2 = Run-CICD -repository $repository -branch $releaseBranch2 -wait

Test-ArtifactsFromRun -runid $runRelease2.id -folder 'artifacts2' -expectedArtifacts @{"Apps"=1} -repoVersion '2.0' -appVersion '2.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts2' -filter '*-release_2.0.0-Apps-2.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact2, but found $noOfReleaseArtifacts"
}

# Check that $tag2 was used as previous release for builds in release branch 2.0.0
Test-LogContainsFromRun -runid $runRelease2.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText "Using $ver2 (tag $tag2) as previous release"

# Release hotfix from version 1.0
$tag1 = "1.0.$($runRelease1.run_number)"
$ver1 = "v$tag1"
Run-CreateRelease -repository $repository -branch $releaseBranch1 -appVersion "$tag1.0" -name $ver1 -tag $tag1 -directCommit -wait

# Release hotfix from version 2.0
$tag2 = "2.0.$($runRelease2.run_number)"
$ver2 = "v$tag2"
Run-CreateRelease -repository $repository -branch $releaseBranch2 -appVersion "$tag2.0" -name $ver2 -tag $tag2 -directCommit -wait

# Run CI/CD workflow in release branch 1.0.0
$runRelease1 = Run-CICD -repository $repository -branch $releaseBranch1 -wait

Test-ArtifactsFromRun -runid $runRelease1.id -folder 'artifacts1' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts1' -filter '*-release_1.0.0-Apps-1.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact1, but found $noOfReleaseArtifacts"
}

# Check that $tag1 was used as previous release for builds in release branch 1.0.0
Test-LogContainsFromRun -runid $runRelease1.id -jobName 'Build . - Default' -stepName 'Run pipeline' -expectedText "Using $ver1 (tag $tag1) as previous release"

#Set-Location $prevLocation

#RemoveRepository -repository $repository -path $repoPath
