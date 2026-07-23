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
#  ____   _____
# |  _ \ / ____|   /\
# | |_) | |       /  \   _ __  _ __  ___
# |  _ <| |      / /\ \ | '_ \| '_ \/ __|
# | |_) | |____ / ____ \| |_) | |_) \__ \
# |____/ \_____/_/    \_\ .__/| .__/|___/
#                       | |   | |
#                       |_|   |_|
#
# This test tests the following scenario:
#
#  - Create a new repository with the same content as microsoft/BCApps
#  - Run the Update AL-Go System Files with the test version
#  - Cancel all workflows
#  - Limit the projects to build, excluding the test projects, and push the change to trigger CI/CD
#  - Wait for the push-triggered "CI/CD" workflow and verify that it completes successfully
#  - Test that app and testapp artifacts are generated
#  - Modify an AL file in the repository and create a Pull Request
#  - Wait for the Pull Request Build to complete and verify that it is successful
#  - Test the artifacts generated
#  - Remove the repository
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

if ($linux) {
    Write-Host 'This test is forking BCApps and should only run once, using the settings in BCApps.'
    exit
}

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$branch = "main"
$template = "https://github.com/$pteTemplate"

$sourceRepo = "microsoft/BCApps"

$repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Push-Location
$repository = "$githubOwner/$repoName"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

# Create repository1
CreateAlGoRepository `
    -github:$github `
    -template "https://github.com/$sourceRepo" `
    -repository $repository `
    -branch $branch

$repoPath = (Get-Location).Path
Write-Host "Repo Path: $repoPath"

RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $algoauthapp -repository $repository | Out-Null

SetRepositorySecret -repository $repository -name 'GHTOKENWORKFLOW' -value $algoauthapp

CancelAllWorkflows -repository $repository

# Pull and test workflows
Pull

# Limit the build to only the app projects (excluding the test projects)
# in order to keep the end to end test manageable
$projects = @(
    "build/projects/Apps W1",
    "build/projects/Apps AT",
    "build/projects/Apps AU",
    "build/projects/Apps BE",
    "build/projects/Apps CA",
    "build/projects/Apps CH",
    "build/projects/Apps CZ",
    "build/projects/Apps DE",
    "build/projects/Apps DK",
    "build/projects/Apps ES",
    "build/projects/Apps FI",
    "build/projects/Apps FR",
    "build/projects/Apps GB",
    "build/projects/Apps IN",
    "build/projects/Apps IS",
    "build/projects/Apps IT",
    "build/projects/Apps MX",
    "build/projects/Apps NL",
    "build/projects/Apps NO",
    "build/projects/Apps NZ",
    "build/projects/Apps RU",
    "build/projects/Apps SE",
    "build/projects/Apps US"
)
# Pushing the settings change to main triggers a full CI/CD build (BCApps runs CI/CD on pushes
# to main). Add-PropertiesToJsonFile -commit -wait waits for that push-triggered run and returns
# it, so use it as the CI verification instead of dispatching a second, redundant CI/CD run.
$run = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "projects" = $projects } -commit -wait

# WaitWorkflow (called inside CommitAndPush) can run for a long time and refreshes the token as it
# goes, so refresh the token again and rebuild the headers before re-fetching the run. WaitWorkflow
# also tolerates a 'cancelled' conclusion, so assert an explicit 'success' conclusion.
RefreshToken -repository $repository
$headers = GetHeaders -token $ENV:GH_TOKEN -repository $repository
$url = "https://api.github.com/repos/$repository/actions/runs/$($run.id)"
$run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json)
if ($run.conclusion -ne 'success') {
    throw "CI/CD workflow run $($run.id) concluded with '$($run.conclusion)' (expected 'success')"
}

# The selected 'Apps *' projects define testFolders, so a full build produces both app and test app
# artifacts. Verify that the CI/CD run actually generated them.
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -repoVersion '*.*' -appVersion '*.*'
$appCount = @(Get-ChildItem -Path '.artifacts/*-Apps-*/*.app' -Recurse).Count
$testAppCount = @(Get-ChildItem -Path '.artifacts/*-TestApps-*/*.app' -Recurse).Count
$appCount | Should -BeGreaterThan 0
$testAppCount | Should -BeGreaterThan 0

# Modify a file in the repository and create a Pull Request
$branch = "e2etest"
$title = "End 2 end test"
invoke-git checkout -b $branch

$fileToChange = Join-Path $repoPath "src/Apps/W1/DataArchive/App/src/DataArchive.Table.al"
$fileContent = Get-Content -Path $fileToChange -Encoding UTF8
$fileContent[0] = $fileContent[0] + "// $title"
Set-Content -Path $fileToChange -Value $fileContent -Encoding UTF8

invoke-git add $fileToChange
invoke-git commit -m $title
invoke-git push --set-upstream origin $branch

invoke-gh pr create --fill --head $branch --repo $repository --base main --body $title

Start-Sleep -Seconds 60

$prs = @(invoke-gh -returnValue pr list --repo $repository | Where-Object { $_.Contains($title) })
if ($prs.Count -eq 0) {
    throw "No Pull Request was created"
}
elseif ($prs.Count -gt 1) {
    throw "More than one Pull Request exists"
}

$headers = GetHeaders -token $ENV:GH_TOKEN -repository $repository
$url = "https://api.github.com/repos/$repository/actions/runs"
# Scope the lookup to the Pull Request Build run for the e2etest branch. Other pull_request runs
# (for example a Dependabot PR) can also be named 'Pull Request Build', so filtering only by name
# can return multiple runs, and passing an array of ids to WaitWorkflow builds an invalid URL.
# The runs are returned newest-first, so take the most recent matching run.
$run = @(((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'pull_request' -and $_.name -eq 'Pull Request Build' -and $_.head_branch -eq $branch }) | Select-Object -First 1
if (-not $run) {
    throw "No Pull Request Build workflow run was found"
}

# Wait for the Pull Request Build to complete
WaitWorkflow -repository $repository -runid $run.id

# WaitWorkflow can run for a long time and refreshes the token as it goes, so refresh the token
# again and rebuild the headers before re-fetching the run. WaitWorkflow also tolerates a
# 'cancelled' conclusion, so assert an explicit 'success' conclusion.
RefreshToken -repository $repository
$headers = GetHeaders -token $ENV:GH_TOKEN -repository $repository
$url = "https://api.github.com/repos/$repository/actions/runs/$($run.id)"
$run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json)
if ($run.conclusion -ne 'success') {
    throw "Pull Request Build workflow run $($run.id) concluded with '$($run.conclusion)' (expected 'success')"
}

# There should be at least 1 app and 1 test app rebuilt
Test-ArtifactsFromRun -runid $run.id -folder '.prartifacts' -repoVersion '*.*' -appVersion '*.*'
$appCount = @(Get-ChildItem -Path '.prartifacts/*-Apps-*/*.app' -Recurse).Count
$testAppCount = @(Get-ChildItem -Path '.prartifacts/*-TestApps-*/*.app' -Recurse).Count
$appCount | Should -BeGreaterThan 0
$testAppCount | Should -BeGreaterThan 0

Pop-Location
RemoveRepository -repository $repository -path $repoPath
