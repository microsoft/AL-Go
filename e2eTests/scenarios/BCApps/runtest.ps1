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
#  - Run the "CI/CD" workflow
#  - Wait for a full build to complete
#  - Test that app and testapp artifacts are generated
#  - Modify a file in the repository and create a Pull Request
#  - Wait for the Pull Request Build to complete
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

$run = RunCICD -repository $repository -branch $branch -wait

# Test that app artifacts are generated
Test-ArtifactsFromRun -runid $run.id -folder '.artifacts' -repoVersion '*.*' -appVersion '*.*'
$appCount = @(Get-ChildItem -Path '.artifacts/*-Apps-*/*.app'  -Recurse).Count
$testAppCount = @(Get-ChildItem -Path '.artifacts/*-TestApps-*/*.app'  -Recurse).Count
$appCount | Should -BeGreaterThan 0
$testAppCount | Should -BeGreaterThan 0

# Modify a file in the repository and create a Pull Request
$branch = "e2etest"
$title = "End 2 end test"
invoke-git checkout -b $branch

$fileToChange = Join-Path $repoPath "src/Tools/Performance Toolkit/App/src/BCPTTestSuite.Codeunit.al"
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
$run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'pull_request' } | Where-Object { $_.name -eq 'Pull Request Build' }
if (-not $run) {
    throw "No Pull Request Build workflow run was found"
}
WaitWorkflow -repository $repository -runid $run.id

# There should be only 1 app rebuilt
Test-ArtifactsFromRun -runid $run.id -folder '.prartifacts' -repoVersion '*.*' -appVersion '*.*'
$appCount = @(Get-ChildItem -Path '.prartifacts/*-Apps-*/*.app'  -Recurse).Count
$appCount | Should -Be 1

Pop-Location
RemoveRepository -repository $repository -path $repoPath
