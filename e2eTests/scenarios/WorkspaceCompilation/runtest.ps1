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
#  - Create a new repository based on the PTE template with two projects (P1 and P2)
#  - P1 has 2 apps: app1 (base) and app2 (depends on app1)
#  - P2 has 1 app: app3 (depends on P1/app1 — cross-project dependency)
#  - Enable useWorkspaceCompilation and useProjectDependencies in repo settings
#  - P1 has doNotPublishApps enabled (compile-only, no container)
#  - P2 publishes apps (full pipeline with testing)
#  - Run the "CI/CD" workflow
#  - Verify P1 compiles both apps successfully
#  - Verify P2 compiles app3 using P1's compiled app1 as a dependency
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

if ($linux) {
    Write-Host 'Workspace compilation currently doesn''t work on Linux runners, so this test is only run on Windows.'
    exit
}


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

# Create a multi-project repo with cross-project dependencies
# P1: app1 (base), app2 (depends on app1) — compile-only (doNotPublishApps)
# P2: app3 (depends on P1/app1) — full pipeline (publish + test)
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -projects @('P1', 'P2') `
    -addRepoSettings @{
        "useWorkspaceCompilation" = $true
        "useProjectDependencies" = $true
        "artifact" = "////nextmajor"
        "githubRunner" = $githubRunner
        "githubRunnerShell" = $githubRunnerShell
    } `
    -contentScript {
        Param([string] $path)
        # P1: compile-only, no container needed
        Add-PropertiesToJsonFile -path (Join-Path $path 'P1\.AL-Go\settings.json') -properties @{
            "country" = "w1"
            "doNotPublishApps" = $true
            "doNotRunTests" = $true
        }

        # P2: full pipeline
        Add-PropertiesToJsonFile -path (Join-Path $path 'P2\.AL-Go\settings.json') -properties @{
            "country" = "w1"
        }

        # P1/app1 (base app)
        $script:id1 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app1' -objID 50001

        # P1/app2 (depends on app1 within same project)
        $script:id2 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name 'app2' -objID 50002 -dependencies @(
            @{ "id" = $script:id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }
        )

        # P2/app3 (depends on P1/app1 — cross-project dependency)
        $script:id3 = CreateNewAppInFolder -folder (Join-Path $path 'P2') -name 'app3' -objID 50003 -dependencies @(
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

# Check P1 artifacts — 2 apps compiled (compile-only, no publishing)
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P1-main-Apps-*.app" = 2
    "P1-main-Apps-*_app1_1.0.2.0.app" = 1
    "P1-main-Apps-*_app2_1.0.2.0.app" = 1
}

# Check P2 artifacts — 1 app compiled (using P1/app1 as dependency)
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "P2-main-Apps-*.app" = 1
    "P2-main-Apps-*_app3_1.0.2.0.app" = 1
}

# Cleanup repositories
Set-Location $prevLocation
RemoveRepository -repository $repository -path $repoPath
