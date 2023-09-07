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
#  - Release version 1.0, create releasebranch 1.0 and update version number to 2.0
#    - Check that release notes contains the correct link to the full changelog
#  - Run the CI/CD workflow main branch
#    - Check that v1.0 was used as previous release
#  - Release version 2.0, create releasebranch 2.0 and update version number to 2.1
#    - Check that release notes contains the correct link to the full changelog
#  - Run the CI/CD workflow main branch
#    - Check that v2.0 was used as previous release
#  - Run the CI/CD workflow in release branch 1.0
#    - Check that latest release from v1.0 was used as previous release
#  - Run the CI/CD workflow in release branch 2.0
#    - Check that latest release from v2.0 was used as previous release
#  - Release a hotfix from release branch 1.0
#    - Check that release notes contains the correct link to the full changelog
#  - Release a hotfix from release branch 2.0
#    - Check that release notes contains the correct link to the full changelog
#  - Run the CI/CD workflow in release branch 1.0
#    - Check that latest release from v1.0 was used as previous release
#
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
    -contentScript {
        Param([string] $path)
        CreateNewAppInFolder -folder $path -name "App" | Out-Null
    }
$repoPath = (Get-Location).Path
Start-Process $repoPath

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'

# Check that no previous release was found
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText 'No previous release found'

# Release version 1.0
$tag1 = '1.0.0'
$ver1 = 'v1.0'
$releaseBranch1 = "release/1.0"
$release1 = RunCreateRelease -repository $repository -branch $branch -appVersion 'latest' -name $ver1 -tag $tag1 -createReleaseBranch -updateVersionNumber '+1.0' -directCommit -wait

Test-LogContainsFromRun -runid $release1.id -jobName 'CreateRelease' -stepName 'Prepare release notes' -expectedText "releaseNotes=**Full Changelog**: https://github.com/$repository/commits/$tag1"

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch -wait

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '2.0' -appVersion '2.0'

# Check that $tag1 was used as previous release
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText "Using $ver1 (tag $tag1) as previous release"

# Release version 2.0
$tag2 = '2.0.0'
$ver2 = 'v2.0'
$releaseBranch2 = "release/2.0"
$release2 = RunCreateRelease -repository $repository -branch $branch -appVersion 'latest' -name $ver2 -tag $tag2 -createReleaseBranch -updateVersionNumber '+0.1' -directCommit -wait

Test-LogContainsFromRun -runid $release2.id -jobName 'CreateRelease' -stepName 'Prepare release notes' -expectedText "releaseNotes=**Full Changelog**: https://github.com/$repository/compare/$tag1...$tag2"

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch
# Run CI/CD workflow in release branch 1.0
$runRelease1 = RunCICD -repository $repository -branch $releaseBranch1
# Run CI/CD workflow in release branch 2.0
$runRelease2 = RunCICD -repository $repository -branch $releaseBranch2 -wait
WaitWorkflow -runid $runRelease1.id -repository $repository -noDelay
WaitWorkflow -runid $run.id -repository $repository -noDelay

# Test number of artifacts
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1} -repoVersion '2.1' -appVersion '2.1'

# Check that $tag2 was used as previous release
Test-LogContainsFromRun -runid $run.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText "Using $ver2 (tag $tag2) as previous release"

Test-ArtifactsFromRun -runid $runRelease1.id -folder 'artifacts1' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts1' -filter '*-release_1.0-Apps-1.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact1, but found $noOfReleaseArtifacts"
}

# Check that $tag1 was used as previous release for builds in release branch 1.0
Test-LogContainsFromRun -runid $runRelease1.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText "Using $ver1 (tag $tag1) as previous release"

Test-ArtifactsFromRun -runid $runRelease2.id -folder 'artifacts2' -expectedArtifacts @{"Apps"=1} -repoVersion '2.0' -appVersion '2.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts2' -filter '*-release_2.0-Apps-2.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact2, but found $noOfReleaseArtifacts"
}

# Check that $tag2 was used as previous release for builds in release branch 2.0
Test-LogContainsFromRun -runid $runRelease2.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText "Using $ver2 (tag $tag2) as previous release"

# Release hotfix from version 1.0
$hotTag1 = "1.0.$($runRelease1.run_number)"
$hotVer1 = "v$hotTag1"
$release1 = RunCreateRelease -repository $repository -branch $releaseBranch1 -appVersion "$hotTag1.0" -name $hotVer1 -tag $hotTag1 -directCommit -wait

Test-LogContainsFromRun -runid $release1.id -jobName 'CreateRelease' -stepName 'Prepare release notes' -expectedText "releaseNotes=**Full Changelog**: https://github.com/$repository/compare/$tag1...$hotTag1"

# Release hotfix from version 2.0
$hotTag2 = "2.0.$($runRelease2.run_number)"
$hotVer2 = "v$hotTag2"
$release2 = RunCreateRelease -repository $repository -branch $releaseBranch2 -appVersion "$hotTag2.0" -name $hotVer2 -tag $hotTag2 -directCommit -wait

Test-LogContainsFromRun -runid $release2.id -jobName 'CreateRelease' -stepName 'Prepare release notes' -expectedText "releaseNotes=**Full Changelog**: https://github.com/$repository/compare/$tag2...$hotTag2"

# Run CI/CD workflow in release branch 1.0
$runRelease1 = RunCICD -repository $repository -branch $releaseBranch1 -wait

Test-ArtifactsFromRun -runid $runRelease1.id -folder 'artifacts3' -expectedArtifacts @{"Apps"=1} -repoVersion '1.0' -appVersion '1.0'
$noOfReleaseArtifacts = @(get-childitem -path 'artifacts3' -filter '*-release_1.0-Apps-1.0.*').count
if ($noOfReleaseArtifacts -ne 1) {
    throw "Expected 1 artifact in release artifact3, but found $noOfReleaseArtifacts"
}

# Check that $hotTag1 was used as previous release for builds in release branch 1.0
Test-LogContainsFromRun -runid $runRelease1.id -jobName 'Build . - Default  . - Default' -stepName 'Run pipeline' -expectedText "Using $hotVer1 (tag $hotTag1) as previous release"

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
