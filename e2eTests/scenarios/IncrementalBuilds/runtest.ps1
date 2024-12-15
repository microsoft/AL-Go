[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [switch] $linux,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#  _____                                          _        _   _           _ _     _     
# |_   _|                                        | |      | | | |         (_) |   | |    
#   | |  _ __   ___ _ __ ___ _ __ ___   ___ _ __ | |_ __ _| | | |__  _   _ _| | __| |___ 
#   | | | '_ \ / __| '__/ _ \ '_ ` _ \ / _ \ '_ \| __/ _` | | | '_ \| | | | | |/ _` / __|
#  _| |_| | | | (__| | |  __/ | | | | |  __/ | | | || (_| | | | |_) | |_| | | | (_| \__ \
# |_____|_| |_|\___|_|  \___|_| |_| |_|\___|_| |_|\__\__,_|_| |_.__/ \__,_|_|_|\__,_|___/
#                                                                                        
# This test tests the following scenario:
#
#  - Set x to 5
#  - Create a new repository based on the PTE template with one project and 3 apps app3 being dependent on app2 and app2 being dependent on app1
#  - Enable incremental builds, useCompilerFolder and doNotPublishApps in settings
#  - Enable concurrency check in CI/CD
#  - Run the "CI/CD" workflow
#  - Check artifacts generated all have the same version number
#  - Modify app1 in a commit and wait for CI/CD workflow to finish
#  - Check artifacts generated - app2 and app3 should come from previous build, app1 should have a new version number
#  - Modify app2 in a commit, wait 30 seconds for CI/CD workflow to start
#  - Modify app3 in a commit and wait for CI/CD workflow to finish
#  - Check that CI/CD started when modifying app2 was cancelled
#  - Check that app2 and app3 were rebuilt in the latest CI/CD run and app1 was taken from the previous run
#  - Check artifacts generated - app3 should come from first build, app1 and app2 should have a new version number
#  - Create another project with x*3 apps, x with dependency on app1, x with dependency on app2 and x with dependencies on app3
#  - Wait for CI/CD to complete
#  - Check artifacts generated - all apps in the new project should have a new version number
#  - Modify app3 in a commit and wait for CI/CD workflow to finish
#  - Check artifacts generated - app3 should have a new version number, all other apps should come from previous build
#  - Change incremental builds mode to modifiedAppsAndDependingApps
#  - Modify app2 in a commit and wait for CI/CD workflow to finish
#  - Check artifacts generated - app2, app3 and all apps in project 2  should have a new version number 
#  - Modify x*2 apps in project 2 in a commit and wait for CI/CD workflow to finish
#  - Check artifacts generated - the x*2 modified apps in project 2 should have a new version number - the rest should be from previous build
#  - Turn off incremental builds
#  - Modify app3 in a commit and wait for CI/CD workflow to finish
#  - Check artifacts generated - all apps should have a new version number
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$linux = $true

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Number of apps to create in the second project will be x*3 (tested this with 450 apps - i.e. x=150)
$x = 5

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

if ($linux) {
    $githubRunner = "ubuntu-latest"
    $githubRunnerShell = "bash"
}
else {
    $githubRunner = "windows-latest"
    $githubRunnerShell = "powershell"
}

# Create repository1
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -projects @('P1') `
    -addRepoSettings @{ "useCompilerFolder" = $true; "doNotPublishApps" = $true; "UseProjectDependencies" = $true; "useApproximateVersion" = $true; "incrementalBuilds" = @{ "enable" = $true }; "githubRunner": $githubRunner; "githubRunnerShell" = $githubRunnerShell } `
    -contentScript {
        Param([string] $path)
        Add-PropertiesToJsonFile -path (Join-Path $path 'P1\.AL-Go\settings.json') -properties @{ "country" = "w1" }
        $script:id1 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app1' -objID 50001
        $script:id2 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app2' -objID 50002 -dependencies @( @{ "id" = $script:id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        $script:id3 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app3' -objID 50003 -dependencies @( @{ "id" = $script:id2; "name" = "app2"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
    }

$repoPath = (Get-Location).Path
$run = RunCICD -repository $repository -branch $branch

# Wait for CI/CD workflow of repository1 to finish
WaitWorkflow -repository $repository -runid $run.id

# Check artifacts generated all have the same version number
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P1-main-Apps-*_app1_1.0.2.0.app" = 1
    "P1-main-Apps-*_app2_1.0.2.0.app" = 1
    "P1-main-Apps-*_app3_1.0.2.0.app" = 1
}

# Modify app1 in a commit and wait for CI/CD workflow to finish
$run = ModifyAppInFolder -folder 'P1/app1' -name 'app1' -commit -wait

# Check artifacts generated - app2 and app3 should come from previous build, app1 should have a new version number
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P1-main-Apps-*_app1_1.0.3.0.app" = 1
    "P1-main-Apps-*_app2_1.0.2.0.app" = 1
    "P1-main-Apps-*_app3_1.0.2.0.app" = 1
}

# Modify app2 in a commit, wait 30 seconds for CI/CD workflow to start
ModifyAppInFolder -folder 'P1/app2' -name 'app2' -commit
Start-Sleep -Seconds 30

# Modify app3 in a commit and wait for CI/CD workflow to finish
$run = ModifyAppInFolder -folder 'P1/app3' -name 'app3' -commit -wait

$runs = gh api /repos/$repository/actions/runs | ConvertFrom-Json
$workflowRuns = $runs.workflow_runs | Select-Object -First 2

# Check that the latest CI/CD is the first in the list
if ($run.id -ne $workflowRuns[0].id) {
    throw "Expected run id $($run.id) to be the first in the list"
}

# Check that CI/CD started when modifying app2 was cancelled
if ($workflowRuns[1].status -ne 'completed' -and $workflowRuns[1].conclusion -ne 'cancelled') {
    throw "Expected second run to be cancelled"
}

# Check that app2 and app3 were rebuilt in the latest CI/CD run and app1 was taken from the previous run
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P1-main-Apps-*_app1_1.0.3.0.app" = 1
    "P1-main-Apps-*_app2_1.0.5.0.app" = 1
    "P1-main-Apps-*_app3_1.0.5.0.app" = 1
}

# Create another project with x*3 apps, x with dependency on app1, x with dependency on app2 and x with dependencies on app3
Pull
New-Item -Path (Join-Path $repoPath 'P2') -ItemType Directory | Out-Null
Copy-Item -Path (Join-Path $repoPath 'P1/.AL-Go') -Destination (Join-Path $repoPath 'P2') -Recurse -Force
1..$x | ForEach-Object {
    CreateNewAppInFolder -folder (Join-Path $repoPath 'P2') -name ("appx{0:D3}-1" -f $_) -objID (51000+$_*10) -dependencies @( @{ "id" = $script:id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
    CreateNewAppInFolder -folder (Join-Path $repoPath 'P2') -name ("appx{0:D3}-2" -f $_) -objID (51000+$_*10) -dependencies @( @{ "id" = $script:id2; "name" = "app2"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
    CreateNewAppInFolder -folder (Join-Path $repoPath 'P2') -name ("appx{0:D3}-3" -f $_) -objID (51000+$_*10) -dependencies @( @{ "id" = $script:id3; "name" = "app3"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
}
CommitAndPush -commitMessage "Add $($x*3) apps"

# Run Update AL-Go System Files with direct commit
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $token -repository $repository -branch $branch | Out-Null

# Wait for CI/CD to complete
Start-Sleep -Seconds 60
$runs = gh api /repos/$repository/actions/runs | ConvertFrom-Json
$run = $runs.workflow_runs | Select-Object -First 1
WaitWorkflow -repository $repository -runid $run.id

# Check artifacts generated - all apps in the all projects should have a new version number (due to changes to .github/*.json)
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P2-main-*.app" = ($x*3)
    "P1-main-Apps-*_1.0.7.0.app" = 3
    "P2-main-Apps-*_1.0.7.0.app" = ($x*3)
}

# Modify app3 in a commit and wait for CI/CD workflow to finish
Pull
$run = ModifyAppInFolder -folder 'P1/app3' -name 'app3' -commit -wait

# Check artifacts generated - app3 should have a new version number, all other apps should come from previous build
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P2-main-*.app" = ($x*3)
    "P1-main-Apps-*_app3_1.0.8.0.app" = 1
    "P1-main-Apps-*_1.0.7.0.app" = 2
    "P2-main-Apps-*_1.0.7.0.app" = ($x*3)
}

# Change incremental builds mode to modifiedAppsAndDependingApps
$null = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "incrementalBuilds" = @{ "enable" = $true; "mode" = "modifiedAppsAndDependingApps" } } -commit -wait

# Modify app2 in a commit and wait for CI/CD workflow to finish
Pull
$run = ModifyAppInFolder -folder 'P1/app2' -name 'app2' -commit -wait

# Check artifacts generated - app2, app3 and x*2 apps in project 2 should have a new version number 
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P2-main-*.app" = ($x*3)
    "P1-main-Apps-*_app1_1.0.9.0.app" = 1
    "P1-main-Apps-*_1.0.10.0.app" = 2
    "P2-main-Apps-*_1.0.9.0.app" = $x
    "P2-main-Apps-*_1.0.10.0.app" = ($x*2)
}

# Modify x*2 apps in project 2 in a commit and wait for CI/CD workflow to finish
Pull
1..$x | ForEach-Object {
    ModifyAppInFolder -folder ("P2/appx{0:D3}-1" -f $_) -name ("appx{0:D3}-1" -f $_)
    ModifyAppInFolder -folder ("P2/appx{0:D3}-2" -f $_) -name ("appx{0:D3}-2" -f $_)
}
$run = CommitAndPush -commitMessage "Modify $($x*2) apps in project 2" -wait

# Check artifacts generated - the $x*2 modified apps in project 2 should have a new version number - the rest should be from previous build
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P2-main-*.app" = ($x*3)
    "P1-main-Apps-*_app1_1.0.9.0.app" = 1
    "P1-main-Apps-*_1.0.10.0.app" = 2
    "P2-main-Apps-*_appx???-1_1.0.11.0.app" = $x
    "P2-main-Apps-*_appx???-2_1.0.11.0.app" = $x
    "P2-main-Apps-*_appx???-3_1.0.10.0.app" = $x
}

# Turn off incremental builds
Pull
$null = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "incrementalBuilds" = @{ "enable" = $false; "mode" = "modifiedApps" } }

# Modify app3 in a commit and wait for CI/CD workflow to finish
$run = ModifyAppInFolder -folder 'P1/app2' -name 'app2' -commit -wait

# Check artifacts generated - all apps should have a new version number
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-*.app" = 3
    "P2-main-*.app" = ($x*3)
    "P1-main-Apps-*_1.0.12.0.app" = 3
    "P2-main-Apps-*_1.0.12.0.app" = ($x*3)
}

# Cleanup repositories

Set-Location $prevLocation
RemoveRepository -repository $repository -path $repoPath
