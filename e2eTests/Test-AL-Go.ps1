[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $template = $global:pteTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText),
    [string] $licenseFileUrl = ($global:SecureLicenseFileUrl | Get-PlainText),
    [string] $insiderSasToken = ($global:SecureInsiderSasToken | Get-PlainText),
    [switch] $multiProject,
    [switch] $appSourceApp,
    [switch] $private,
    [switch] $linux,
    [switch] $useCompilerFolder
)

Write-Host -ForegroundColor Yellow @'
#  ______           _ ___                _    _           _                                    _
# |  ____|         | |__ \              | |  | |         | |                                  (_)
# | |__   _ __   __| |  ) |___ _ __   __| |  | |_ ___ ___| |_    ___  ___ ___ _ __   __ _ _ __ _  ___
# |  __| | '_ \ / _` | / // _ \ '_ \ / _` |  | __/ _ \ __| __|  / __|/ __/ _ \ '_ \ / _` | '__| |/ _ \
# | |____| | | | (_| |/ /_  __/ | | | (_| |  | |_  __\__ \ |_   \__ \ (__  __/ | | | (_| | |  | | (_) |
# |______|_| |_|\__,_|____\___|_| |_|\__,_|   \__\___|___/\__|  |___/\___\___|_| |_|\__,_|_|  |_|\___/
#
# This scenario runs for both PTE template and AppSource App template and as single project and multi project repositories
#
# - Login to GitHub
# - Create a new repository based on the selected template
# - If (AppSource App) Create a licensefileurl secret
# - Run the "Add an existing app" workflow and add an app as a Pull Request
# -  Test that a Pull Request was created and merge the Pull Request
# - Run the "CI/CD" workflow
# -  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# - Run the "Create Release" workflow to create a version 1.0 release
# - Run the "Create a new App" workflow to add a new app (adjust necessary properties if multiproject or appsource app)
# -  Test that app.json exists and properties in app.json are as expected
# - Run the "Create a new Test App" workflow to add a new test app
# -  Test that app.json exists and properties in app.json are as expected
# - Run the "Create Online Development Environment" if requested
# - Run the "Increment version number" workflow for one project (not changing apps) as a Pull Request
# -  Test that a Pull Request was created and merge the Pull Request
# - Run the CI/CD workflow
# -  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# - Modify repository versioning strategy and remove some scripts + a .yaml file
# - Run the CI/CD workflow
# -  Test that artifacts created from CI/CD are correct and of the right version (also apps version numbers should be updated)
# - Create the GHTOKENWORKFLOW secret
# - Run the "Update AL-Go System Files" workflow as a Pull Request
# -  Test that a Pull Request was created and merge the Pull Request
# -  Test that the previously deleted files are now updated
# - Run the "Create Release" workflow
# - Run the Test Current Workflow
# - Run the Test Next Minor Workflow
# - Run the Test Next Major Workflow
#
# TODO: some more tests to do here
#
# - Test that the number of workflows ran is correct.
# - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

if ($appSourceApp) {
    $sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/apps.zip"
    $sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/testapps.zip"
    $idRange = @{ "from" = 75055000; "to" = 75056000 }
}
else {
    $sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/apps.zip"
    $sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/testapps.zip"
    $idRange = @{ "from" = 55000; "to" = 56000 }
}
if ($multiProject) {
    $project1Param = @{ "project" = "P1" }
    $project1Folder = 'P1\'
    $project2Param = @{ "project" = "P2" }
    $project2Folder = 'P2\'
    $allProjectsParam = @{ "project" = "*" }
    $projectSettingsFiles = @("P1\.AL-Go\settings.json", "P2\.AL-Go\settings.json")
}
else {
    $project1Param = @{}
    $project1Folder = ""
    $project2Param = @{}
    $project2Folder = ""
    $allProjectsParam = @{}
    $projectSettingsFiles = @(".AL-Go\settings.json")
}

$template = "https://github.com/$template"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
# Set DoNotPublishApps to true until we have test apps and set useCompilerFolder
# This causes the CI/CD workflow to use FilesOnly containers or CompilerFolder (if UseCompilerFolder is true)
CreateAlGoRepository -github:$github -template $template -branch $branch -private:$private -linux:$linux -addRepoSettings @{ "useCompilerFolder" = $useCompilerFolder.IsPresent; "doNotPublishApps" = $useCompilerFolder.IsPresent }
$repoPath = (Get-Location).Path

# Wait for GitHub to create the repository
Start-Sleep -Seconds 60

# Get initial number of runs (due to bug in GitHub, this might be 0, 1 or 2)
$runs = GetNumberOfRuns -repository $repository

# Add Existing App
if ($appSourceApp) {
    SetRepositorySecret -repository $repository -name 'LICENSEFILEURL' -value $licenseFileUrl
}
RunAddExistingAppOrTestApp @project1Param -url $sampleApp1 -wait -directCommit -branch $branch | Out-Null
$runs++
if ($appSourceApp) {
    Pull -branch $branch
    Add-PropertiesToJsonFile -commit -path "$($project1Folder).AL-Go\settings.json" -properties @{ "AppSourceCopMandatoryAffixes" = @( "hw_", "cus" ) }
    $runs++
}

# Add Existing Test App
RunAddExistingAppOrTestApp @project1Param -url $sampleTestApp1 -wait -branch $branch | Out-Null
$runs++

# Merge and run CI/CD + Tests
MergePRandPull -branch $branch | Out-Null
$runs++

# Wait for CI/CD to finish
$run = RunCICD -wait -branch $branch
$runs++

if ($useCompilerFolder) {
    # If using compiler folder duing tests, doNotPublishApps is also set to true (for now), which means that apps are not published and tests are not run
    # Later we will fix this to include test runs as well, but for now, expected number of tests is 0
    $expectedNumberOfTests = 0
}
else {
    $expectedNumberOfTests = 1
}
TestNumberOfRuns -expectedNumberOfRuns $runs -repository $repository
Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=2;"TestApps"=1} -expectedNumberOfTests $expectedNumberOfTests -folder 'artifacts' -repoVersion '1.0' -appVersion ''

# Create Release
RunCreateRelease -appVersion "1.0.$($runs-2).0" -name 'v1.0' -tag '1.0.0' -wait -branch $branch | Out-Null
$runs++

# Create New App
RunCreateApp @project2Param -name "My App" -publisher "My Publisher" -idrange "$($idRange.from)..$($idRange.to)" -directCommit -wait -branch $branch | Out-Null
$runs++
Pull -branch $branch
if ($appSourceApp) {
    if ($multiProject) {
        Add-PropertiesToJsonFile -commit -path "$($project2Folder).AL-Go\settings.json" -properties @{ "AppSourceCopMandatoryAffixes" = @( "cus" ) }
        $runs++
    }
    Copy-Item -path "$($project1Folder)Default App Name\logo\helloworld256x240.png" -Destination "$($project2Folder)My App\helloworld256x240.png"
    Add-PropertiesToJsonFile -commit -path "$($project2Folder)My App\app.json" -properties @{
        "brief" = "Hello World for AppSource"
        "description" = "Hello World sample app for AppSource"
        "logo" = "helloworld256x240.png"
        "url" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
        "EULA" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
        "privacyStatement" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
        "help" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
        "contextSensitiveHelpUrl" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
        "features" = @( "TranslationFile" )
    }
    $runs++
}
Test-PropertiesInJsonFile -jsonFile "$($project2folder)My App\app.json" -properties @{ "name" = "My App"; "publisher" = "My Publisher"; 'idRanges[0].from' = $idRange.from; "idRanges[0].to" = $idRange.to; 'idRanges.Count' = 1 }

# Create New Test App
RunCreateTestApp @project2Param -name "My TestApp" -publisher "My Publisher" -idrange "58000..59000" -directCommit -wait -branch $branch | Out-Null
$runs++
if ($expectedNumberOfTests) { $expectedNumberOfTests++ }

Pull -branch $branch
Test-PropertiesInJsonFile -jsonFile "$($project2folder)My TestApp\app.json" -properties @{ "name" = "My TestApp"; "publisher" = "My Publisher"; 'idRanges[0].from' = 58000; "idRanges[0].to" = 59000; 'idRanges.Count' = 1 }

# Create Online Development Environment
if ($adminCenterApiToken -and -not $multiProject) {
    SetRepositorySecret -repository $repository -name 'ADMINCENTERAPICREDENTIALS' -value $adminCenterApiToken
    RunCreateOnlineDevelopmentEnvironment -environmentName $repoName -directCommit -branch $branch | Out-Null
    $runs++
}

# Increment version number on one project
RunIncrementVersionNumber @project2Param -versionNumber 2.0 -wait -branch $branch | Out-Null
$runs++
$run = MergePRandPull -branch $branch -wait
$runs++
if ($multiProject) {
    Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=1;"TestApps"=1} -expectedNumberOfTests $expectedNumberOfTests -folder 'artifacts2' -repoVersion '2.0' -appVersion ''
}
else {
    Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=3;"TestApps"=2} -expectedNumberOfTests $expectedNumberOfTests -folder 'artifacts2' -repoVersion '2.0' -appVersion ''
}
TestNumberOfRuns -expectedNumberOfRuns $runs -repository $repository

# Modify versioning strategy
$projectSettingsFiles | Select-Object -Last 1 | ForEach-Object {
    $projectSettings = Get-Content $_ -Encoding UTF8 | ConvertFrom-Json
    $projectsettings | Add-Member -NotePropertyName 'versioningStrategy' -NotePropertyValue 16
    $projectSettings | Set-JsonContentLF -path $_
}
Remove-Item -Path "$($project1Folder).AL-Go\*.ps1" -Force
Remove-Item -Path ".github\workflows\AddExistingAppOrTestApp.yaml" -Force
CommitAndPush -commitMessage "Version strategy change"
$runs++

# Increment version number on all project (and on all apps)
RunIncrementVersionNumber @allProjectsParam -versionNumber 3.0 -directCommit -wait -branch $branch | Out-Null
$runs++
Pull -branch $branch
if (Test-Path "$($project1Folder).AL-Go\*.ps1") { throw "Local PowerShell scripts in the .AL-Go folder should have been removed" }
if (Test-Path ".github\workflows\AddExistingAppOrTestApp.yaml") { throw "AddExistingAppOrTestApp.yaml should have been removed" }
$run = RunCICD -wait -branch $branch
$runs++
Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=3;"TestApps"=2} -expectedNumberOfTests $expectedNumberOfTests -folder 'artifacts3' -repoVersion '3.0' -appVersion '3.0'

# Update AL-Go System Files
$repoSettings = Get-Content ".github\AL-Go-Settings.json" -Encoding UTF8 | ConvertFrom-Json
SetRepositorySecret -repository $repository -name 'GHTOKENWORKFLOW' -value $token
RunUpdateAlGoSystemFiles -templateUrl $repoSettings.templateUrl -wait -branch $branch | Out-Null
$runs++
MergePRandPull -branch $branch | Out-Null
$runs += 2
if (!(Test-Path "$($project1Folder).AL-Go\*.ps1")) { throw "Local PowerShell scripts in the .AL-Go folder was not updated by Update AL-Go System Files" }
if (!(Test-Path ".github\workflows\AddExistingAppOrTestApp.yaml")) { throw "AddExistingAppOrTestApp.yaml was not updated by Update AL-Go System Files" }

# Create Release
RunCreateRelease -appVersion latest -name "v3.0" -tag "3.0.0" -wait -branch $branch | Out-Null
$runs++

# Launch Current, NextMinor and NextMajor builds
$runTestCurrent = RunTestCurrent -branch $branch
$runTestNextMinor = RunTestNextMinor -branch $branch -insiderSasToken $insiderSasToken
$runTestNextMajor = RunTestNextMajor -branch $branch -insiderSasToken $insiderSasToken

# TODO: Test workspace

# TODO: Test Release

# TODO: Test Release notes

# TODO: Check that environment was created and that launch.json was updated

# Test localdevenv

WaitWorkflow -runid $runTestNextMajor.id
$runs++

WaitWorkflow -runid $runTestNextMinor.id -noDelay
$runs++

WaitWorkflow -runid $runTestCurrent.id -noDelay
$runs++

TestNumberOfRuns -expectedNumberOfRuns $runs -repository $repository

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath

if ($adminCenterApiToken) {
    try {
        $params = $adminCenterApiToken | ConvertFrom-Json | ConvertTo-HashTable
        $authContext = New-BcAuthContext @params
        Remove-BcEnvironment -bcAuthContext $authContext -environment $repoName -doNotWait
    }
    catch {
        Write-Host "::WARNING::Failed to remove environment $repoName"
    }
}
