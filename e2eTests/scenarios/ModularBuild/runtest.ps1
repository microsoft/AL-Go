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
#  __  __           _       _            ____        _ _     _
# |  \/  | ___   __| |_   _| | __ _ _ __| __ ) _   _(_) | __| |
# | |\/| |/ _ \ / _` | | | | |/ _` | '__|  _ \| | | | | |/ _` |
# | |  | | (_) | (_| | |_| | | (_| | |  | |_) | |_| | | | (_| |
# |_|  |_|\___/ \__,_|\__,_|_|\__,_|_|  |____/ \__,_|_|_|\__,_|
#
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with one app
#  - Enable useModularBuild in repo settings (which enforces useCompilerFolder)
#  - Run the "CI/CD" workflow
#  - Verify the app is compiled, a dev environment is created and the app is published
#    by the modular build actions (CreateDevEnvironment -> CompileApps -> PublishApps ->
#    RunTests -> RemoveDevEnvironment, orchestrated by the BuildAndTest action)
#  - Verify the app artifact is produced
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

if ($linux) {
    Write-Host 'The modular build creates a Business Central container for publishing and testing, which currently requires a Windows runner, so this test is only run on Windows.'
    exit
}

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

$githubRunner = "windows-latest"
$githubRunnerShell = "powershell"

# Create a single-project repo with one app, using the modular build
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -addRepoSettings @{
        "useModularBuild" = $true
        "artifact" = "////nextmajor"
        "githubRunner" = $githubRunner
        "githubRunnerShell" = $githubRunnerShell
    } `
    -contentScript {
        Param([string] $path)
        Add-PropertiesToJsonFile -path (Join-Path $path '.AL-Go\settings.json') -properties @{
            "country" = "w1"
        }

        # app1 (base app)
        $script:id1 = CreateNewAppInFolder -folder $path -name 'app1' -objID 50001
    }

$repoPath = (Get-Location).Path

# Run Update AL-Go System Files with direct commit (to pull in the modular build actions/workflow)
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Wait for CI/CD to complete
Start-Sleep -Seconds 60
$runs = invoke-gh api /repos/$repository/actions/runs -silent -returnValue | ConvertFrom-Json
$run = $runs.workflow_runs | Select-Object -First 1
WaitWorkflow -repository $repository -runid $run.id

# Verify the modular build compiled and published the app
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -expectedArtifacts @{
    "*-main-Apps-*.app" = 1
    "*-main-Apps-*_app1_1.0.2.0.app" = 1
}

# Cleanup repositories
Set-Location $prevLocation
RemoveRepository -repository $repository -path $repoPath
