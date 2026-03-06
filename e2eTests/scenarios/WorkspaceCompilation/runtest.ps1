[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Secrets are transferred as plain text.')]
Param(
    [switch] $github,
    [switch] $linux,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $e2eAppId,
    [string] $e2eAppKey,
    [string] $algoauthapp = ($global:SecureALGOAUTHAPP | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiCredentials = ($global:SecureadminCenterApiCredentials | Get-PlainText),
    [string] $azureCredentials = ($global:SecureAzureCredentials | Get-PlainText),
    [string] $githubPackagesToken = ($global:SecureGitHubPackagesToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
# __        __         _                                ____                      _ _       _   _
# \ \      / /__  _ __| | _____ _ __   __ _  ___ ___   / ___|___  _ __ ___  _ __ (_) | __ _| |_(_) ___  _ __
#  \ \ /\ / / _ \| '__| |/ / __| '_ \ / _` |/ __/ _ \ | |   / _ \| '_ ` _ \| '_ \| | |/ _` | __| |/ _ \| '_ \
#   \ V  V / (_) | |  |   <\__ \ |_) | (_| | (_|  __/ | |__| (_) | | | | | | |_) | | | (_| | |_| | (_) | | | |
#    \_/\_/ \___/|_|  |_|\_\___/ .__/ \__,_|\___\___|  \____\___/|_| |_| |_| .__/|_|_|\__,_|\__|_|\___/|_| |_|
#                              |_|                                        |_|
#
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with one project and 4 apps with dependencies
#  - Enable useWorkspaceCompilation, useCompilerFolder and doNotPublishApps in settings
#  - Run the "CI/CD" workflow
#  - Check artifacts generated - all 4 apps should be compiled successfully
#  - Verify that apps are compiled using workspace compilation (faster parallel build)
#  - Modify one app and verify dependent apps are also rebuilt correctly
#  - Modify a leaf app and verify only that app gets a new version
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
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

if ($linux) {
    $githubRunner = "ubuntu-latest"
    $githubRunnerShell = "pwsh"
}
else {
    $githubRunner = "windows-latest"
    $githubRunnerShell = "powershell"
}

# Create a new repository with useWorkspaceCompilation enabled
# 4 apps: app1 (base), app2 (depends on app1), app3 (depends on app2), app4 (depends on app1)
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -projects @('P1') `
    -addRepoSettings @{
        "useWorkspaceCompilation" = $true
        "useCompilerFolder" = $true
        "doNotPublishApps" = $true
        "artifact" = "////nextmajor"
        "githubRunner" = $githubRunner
        "githubRunnerShell" = $githubRunnerShell
    } `
    -contentScript {
        Param([string] $path)
        Add-PropertiesToJsonFile -path (Join-Path $path 'P1\.AL-Go\settings.json') -properties @{ "country" = "w1" }

        # Create app1 (base app)
        $script:id1 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app1' -objID 50001

        # Create app2 (depends on app1)
        $script:id2 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app2' -objID 50002 -dependencies @(
            @{ "id" = $script:id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }
        )

        # Create app3 (depends on app2)
        $script:id3 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app3' -objID 50003 -dependencies @(
            @{ "id" = $script:id2; "name" = "app2"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }
        )

        # Create app4 (depends on app1, used to verify additional dependent apps compile correctly)
        $script:id4 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app4' -objID 50004 -dependencies @(
            @{ "id" = $script:id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }
        )
    }

$repoPath = (Get-Location).Path

# Run Update AL-Go System Files with direct commit
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Wait for CI/CD to complete
Start-Sleep -Seconds 60
$runs = invoke-gh api /repos/$repository/actions/runs -silent -returnValue | ConvertFrom-Json
$run = $runs.workflow_runs | Select-Object -First 1
WaitWorkflow -repository $repository -runid $run.id

# Check artifacts generated - all apps should be compiled with version 1.0.2.0
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-Apps-*.app" = 4
    "P1-main-Apps-*_app1_1.0.2.0.app" = 1
    "P1-main-Apps-*_app2_1.0.2.0.app" = 1
    "P1-main-Apps-*_app3_1.0.2.0.app" = 1
    "P1-main-Apps-*_app4_1.0.2.0.app" = 1
}

# Modify app1 and verify dependent apps are rebuilt
Pull
$run = ModifyAppInFolder -folder 'P1/app1' -name 'app1' -commit -wait

# Check that all apps got a new version (app1 was modified, app2/app3/app4 depend on it directly or transitively)
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-Apps-*.app" = 4
    "P1-main-Apps-*_app1_1.0.3.0.app" = 1
    "P1-main-Apps-*_app2_1.0.3.0.app" = 1
    "P1-main-Apps-*_app3_1.0.3.0.app" = 1
    "P1-main-Apps-*_app4_1.0.3.0.app" = 1
}

# Modify only app3 (leaf node) - only app3 should be rebuilt
Pull
$run = ModifyAppInFolder -folder 'P1/app3' -name 'app3' -commit -wait

# Check that only app3 got a new version
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-Apps-*.app" = 4
    "P1-main-Apps-*_app1_1.0.3.0.app" = 1
    "P1-main-Apps-*_app2_1.0.3.0.app" = 1
    "P1-main-Apps-*_app3_1.0.4.0.app" = 1
    "P1-main-Apps-*_app4_1.0.3.0.app" = 1
}

# Modify only app4 (leaf node depending on app1) - only app4 should get a new version
Pull
$run = ModifyAppInFolder -folder 'P1/app4' -name 'app4' -commit -wait

# Check that only app4 got a new version
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-Apps-*.app" = 4
    "P1-main-Apps-*_app1_1.0.3.0.app" = 1
    "P1-main-Apps-*_app2_1.0.3.0.app" = 1
    "P1-main-Apps-*_app3_1.0.4.0.app" = 1
    "P1-main-Apps-*_app4_1.0.5.0.app" = 1
}

# Cleanup repositories
Set-Location $prevLocation
RemoveRepository -repository $repository -path $repoPath
