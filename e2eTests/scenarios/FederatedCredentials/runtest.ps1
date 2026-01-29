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
#  ______       _                _           _    _____              _            _   _       _
# |  ____|     | |              | |         | |  / ____|            | |          | | (_)     | |
# | |__ ___  __| | ___ _ __ __ _| |_ ___  __| | | |     _ __ ___  __| | ___ _ __ | |_ _  __ _| |___
# |  __/ _ \/ _` |/ _ \ '__/ _` | __/ _ \/ _` | | |    | '__/ _ \/ _` |/ _ \ '_ \| __| |/ _` | / __|
# | | |  __/ (_| |  __/ | | (_| | ||  __/ (_| | | |____| | |  __/ (_| |  __/ | | | |_| | (_| | \__ \
# |_|  \___|\__,_|\___|_|  \__,_|\__\___|\__,_|  \_____|_|  \___|\__,_|\___|_| |_|\__|_|\__,_|_|___/
#
#
#
# This test uses the bcsamples-bingmaps.appsource repository and will deliver a new build of the app to AppSource.
# The bcsamples-bingmaps.appsource repository is setup to use an Azure KeyVault for secrets and app signing.
#
# The test requires a stable temporary repository called tmp-bingmaps.appsource that must be manually created
# with federated credentials configured before running this test.
# This is required because federated credentials no longer work with repository name-based matching,
# so the repository must remain stable to maintain the federated credential configuration.
# tmp-bingmaps.appsource has access to the same Azure KeyVault as bcsamples-bingmaps.appsource using federated credentials.
# The bcSamples-bingmaps.appsource repository is setup for continuous delivery to AppSource
# tmp-bingmaps.appsource also has access to the Entra ID app registration for delivering to AppSource using federated credentials.
# This test will deliver another build of the latest app version already delivered to AppSource (without go-live)
#
# This test tests the following scenario:
#
#  - Verify that the repository tmp-bingmaps.appsource exists (error out if not)
#  - Reset the repository to match bcsamples-bingmaps.appsource for deterministic state
#  - Clean up old workflow runs to ensure proper workflow tracking
#  - Update AL-Go System Files in branch main in tmp-bingmaps.appsource
#  - Update version numbers in app.json in tmp-bingmaps.appsource in order to not be lower than the version number in AppSource (and not be higher than the next version from bcsamples-bingmaps.appsource)
#  - Wait for CI/CD in branch main in repository tmp-bingmaps.appsource
#  - Check that artifacts are created and signed
#  - Check that the app is delivered to AppSource
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

if ($linux) {
    Write-Host 'This test is using bcsamples-bingmaps.appsource and should only run once (either Windows or Linux)'
    exit
}

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/tmp-bingmaps.appsource"
$template = "https://github.com/$appSourceTemplate"
$sourceRepository = 'microsoft/bcsamples-bingmaps.appsource' # E2E test will create a copy of this repository

# Setup authentication and repository
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

# Check if the repository already exists
# This repository must exist with federated credentials already configured
gh api repos/$repository --method HEAD
if ($LASTEXITCODE -ne 0) {
    throw "Repository $repository does not exist. The repository must be created manually with federated credentials configured before running this test."
}

# Repository exists - reuse it and reset to source state
# This is required because federated credentials no longer work with repository name-based matching,
# so the repository must remain stable across test runs
Write-Host "Repository $repository exists. Reusing and resetting to match source."

# Reset the repository to match the source repository
ResetRepositoryToSource -repository $repository -sourceRepository $sourceRepository -branch 'main'

# Clean up old workflow runs to prevent the list from growing and ensure we wait for the correct run
CleanupOldWorkflowRuns -repository $repository -keepCount 5

# Always set/update secrets (they may have changed or repo may have been reset)
SetRepositorySecret -repository $repository -name 'Azure_Credentials' -value $azureCredentials

# Re-apply the custom repository settings that were lost during reset
$tempPath = [System.IO.Path]::GetTempPath()
$repoPath = Join-Path $tempPath ([System.Guid]::NewGuid().ToString())
New-Item $repoPath -ItemType Directory | Out-Null
Push-Location $repoPath
try {
    Write-Host "Re-applying repository settings..."
    invoke-gh repo clone $repository . -- --quiet
    $repoSettingsFile = ".github\AL-Go-Settings.json"
    if (Test-Path $repoSettingsFile) {
        Add-PropertiesToJsonFile -path $repoSettingsFile -properties @{"ghTokenWorkflowSecretName" = "e2eghTokenWorkflow"}
        invoke-git add $repoSettingsFile
        invoke-git commit -m "Update repository settings for test" --quiet
        invoke-git push --quiet
    }
    else {
        Write-Host "Warning: .github\AL-Go-Settings.json not found after cloning. Settings may not be applied correctly."
    }
}
finally {
    Pop-Location
    Remove-Item -Path $repoPath -Force -Recurse -ErrorAction SilentlyContinue
}

# Upgrade AL-Go System Files to test version
# Capture the run object to ensure we wait for the correct workflow run
$updateRun = RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -repository $repository

# Wait for CI/CD to complete
# The Update AL-Go System Files workflow triggers a CI/CD workflow via push event
# We need to wait for the CI/CD workflow that was triggered AFTER the update workflow completed
Write-Host "Waiting for CI/CD workflow to start (triggered by Update AL-Go System Files)..."
Start-Sleep -Seconds 60

# Get workflow runs that started after the update workflow
# Use created_at for consistent timestamp comparison, and add a small buffer for timing precision
$updateCreatedAt = [DateTime]$updateRun.created_at
$runs = invoke-gh api /repos/$repository/actions/runs -silent -returnValue | ConvertFrom-Json

# Find the CI/CD workflow run that started after the update workflow was created
$run = $runs.workflow_runs | Where-Object { 
    $_.event -eq 'push' -and [DateTime]$_.created_at -gt $updateCreatedAt 
} | Select-Object -First 1

if (-not $run) {
    # Fallback to the first workflow run if we can't find one based on timestamp
    Write-Host "Warning: Could not find CI/CD run based on timestamp, using first run"
    $run = $runs.workflow_runs | Select-Object -First 1
}

Write-Host "Waiting for CI/CD workflow run $($run.id) to complete..."
WaitWorkflow -repository $repository -runid $run.id -noError

# The CI/CD workflow should fail because the version number of the app in the repository is lower than the version number in AppSource
# Reason being that major.minor from the original bcsamples-bingmaps.appsource is the same and the build number in the newly created repository is lower than the one in AppSource
# This error is expected we will grab the version number from AppSource, add one to revision number (by switching to versioningstrategy 3 in the tmp repo) and use it in the next run
$MatchArr = Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Deliver' -expectedText '(?m)^.*The new version number \((\d+(?:\.\d+){3})\) is lower than the existing version number \((\d+(?:\.\d+){3})\) in Partner Center.*$' -isRegEx
$appSourceVersion = [System.Version]$MatchArr[2]
$newVersion = [System.Version]::new($appSourceVersion.Major, $appSourceVersion.Minor, $appSourceVersion.Build, 0)
$newRepoVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Build)"

# Pull changes from repo
pull

# Update version number in app.json
Get-ChildItem -recurse -filter 'app.json' | ForEach-Object {
    $appJson = $_.FullName
    Write-Host "Update version number in $appJson"
    $json = Get-Content -Path $appJson -Encoding utf8 -Raw | ConvertFrom-Json
    $json.version = $newVersion.ToString()
    $json | ConvertTo-Json -Depth 99 | Set-Content -Path $appJson -encoding utf8 -Force
}

# Update RepoVersion in settings.json
Get-ChildItem -Recurse -Path 'settings.json' | ForEach-Object {
    $settingsJson = $_.FullName
    Add-PropertiesToJsonFile -path $settingsJson -properties @{"RepoVersion" = $newRepoVersion; "versioningStrategy" = 3}
}

# Switch to versioning strategy 3 (build number) and wait for the workflow to finish
# Versioning strategy 3 uses RUN_NUMBER as revision number, causing the next build to be higher than the one in AppSource, but lower then the next from the original repo
$run = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{"versioningStrategy" = 3} -commit -wait

# Check that workflow run uses federated credentials and signing was successful
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)*Main App (Default)' -stepName 'Sign' -expectedText 'Connecting to Azure using clientId and federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)*Main App (Default)' -stepName 'Sign' -expectedText '(?m)^.*Signing .* succeeded.*$' -isRegEx | Out-Null

# Check that Deliver to AppSource uses federated credentials and that a new submission was created
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Read secrets' -expectedText 'Query federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Deliver' -expectedText 'New AppSource submission created'

# Test artifacts generated
$artifacts = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$repository/actions/runs/$($run.id)/artifacts | ConvertFrom-Json
@($artifacts.artifacts.Name) -like "Library Apps-main-Apps-$($newVersion.Major).$($newVersion.Minor).$($newVersion.Build).*" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-main-Apps-$($newVersion.Major).$($newVersion.Minor).$($newVersion.Build).*" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-main-Dependencies-$($newVersion.Major).$($newVersion.Minor).$($newVersion.Build).*" | Should -Be $true

Write-Host "Download build artifacts"
invoke-gh run download $run.id --repo $repository --dir 'signedApps'

$noOfApps = 0
Get-Item "signedApps/Main App-main-Apps-$($newVersion.Major).$($newVersion.Minor).$($newVersion.Build).*/*.app" | ForEach-Object {
    $appFile = $_.FullName
    Write-Host "Check that $appFile was signed"
    [System.Text.Encoding]::Ascii.GetString([System.IO.File]::ReadAllBytes($appFile)).indexof('DigiCert Trusted G4 TimeStamping RSA4096 SHA') | Should -BeGreaterThan -1
    $noOfApps++
}
# Check that two apps were signed
$noOfApps | Should -Be 2
