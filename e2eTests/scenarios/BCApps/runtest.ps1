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
#  - Limit the projects to build, excluding the test projects
#  - Cancel all workflows
#  - Run the "CI/CD" workflow and verify that it completes successfully
#  - Modify an AL file in the repository and create a Pull Request
#  - Wait for the Pull Request Build to complete and verify that it is successful
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
Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "projects" = $projects } -commit -wait | Out-Null

# Run the CI/CD workflow and verify that it completes successfully (RunCICD -wait throws if the run does not succeed)
RunCICD -repository $repository -branch $branch -wait | Out-Null

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
$run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'pull_request' } | Where-Object { $_.name -eq 'Pull Request Build' }
if (-not $run) {
    throw "No Pull Request Build workflow run was found"
}

# Wait for the Pull Request Build to complete and verify that it is successful (WaitWorkflow throws if the run does not succeed)
WaitWorkflow -repository $repository -runid $run.id

Pop-Location
RemoveRepository -repository $repository -path $repoPath
