[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
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
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText),
    [string] $azureConnectionSecret = ($global:SecureAzureConnectionSecret | Get-PlainText),
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
# During the test, the bcsamples-bingmaps.appsource repository will be copied to a new repository called tmp-bingmaps.appsource.
# tmp-bingmaps.appsource has access to the same Azure KeyVault as bcsamples-bingmaps.appsource using federated credentials.
# The bcSamples-bingmaps.appsource repository is setup for continuous delivery to AppSource
# This test will deliver another build of the latest app version already delivered to AppSource (without go-live)
#
# This test tests the following scenario:
#
# bcsamples-bingmaps.appsource is setup to use an Azure KeyVault for secrets and app signing
# Access to the Azure KeyVault is using federated credentials (branches main and e2e)
# bcsamples-bingmaps.appsource is using a Entra ID app registration for delivering to AppSource
# The Entra ID app registration is using federated credentials (branches main and e2e)
#
#  - Create a new repository called tmp-bingmaps.appsource (based on bcsamples-bingmaps.appsource)
#  - Update AL-Go System Files in branch main in tmp-bingmaps.appsource
#  - Invoke CI/CD in branch main in repository tmp-bingmaps.appsource
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
$branch = "main"
$template = "https://github.com/$appSourceTemplate"
$sourceRepository = 'microsoft/bcsamples-bingmaps.appsource' # E2E test will create a copy of this repository

# Create temp repository from sourceRepository
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository
CreateAlGoRepository `
    -github:$github `
    -template "https://github.com/$sourceRepository" `
    -repository $repository `
    -addRepoSettings @{"ghTokenWorkflowSecretName" = "e2eghTokenWorkflow" } `
    -branch $branch

SetRepositorySecret -repository $repository -name 'Azure_Credentials' -value $azureConnectionSecret

# Upgrade AL-Go System Files to test version
# bcsamples-bingmaps.appsource already has the GHTOKENWORKFLOW secret
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -repository $repository -branch $branch | Out-Null

# Run CI/CD workflow
$run = RunCICD -repository $repository -branch $branch -wait

# Check that workflow run uses federated credentials and signing was successful
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)  Main App (Default)' -stepName 'Sign' -expectedText 'Connecting to Azure using clientId and federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Build Main App (Default)  Main App (Default)' -stepName 'Sign' -expectedText 'Signing .* succeeded' -isRegEx

# Check that Deliver to AppSource uses federated credentials and that a new submission was created
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Read secrets' -expectedText 'Query federated token'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'Deliver to AppSource' -stepName 'Deliver' -expectedText 'New AppSource submission created'

# Test artifacts generated
$artifacts = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$repository/actions/runs/$($run.id)/artifacts | ConvertFrom-Json
@($artifacts.artifacts.Name) -like "Library Apps-$branch-Apps-*.*.*.0" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-$branch-Apps-*.*.*.0" | Should -Be $true
@($artifacts.artifacts.Name) -like "Main App-$branch-Dependencies-*.*.*.0" | Should -Be $true

Write-Host "Download build artifacts"
invoke-gh run download $run.id --repo $repository --dir 'signedApps'

$noOfApps = 0
Get-Item "signedApps/Main App-$branch-Apps-*.*.*.0/*.app" | ForEach-Object {
    $appFile = $_.FullName
    Write-Host "Check that $appFile was signed"
    [System.Text.Encoding]::Ascii.GetString([System.IO.File]::ReadAllBytes($appFile)).indexof('DigiCert Trusted G4 RSA4096 SHA256 TimeStamping CA') | Should -BeGreaterThan -1
    $noOfApps++
}
# Check that two apps were signed
$noOfApps | Should -Be 2
