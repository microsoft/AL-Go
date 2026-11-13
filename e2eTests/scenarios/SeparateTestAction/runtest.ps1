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
#  ____                              _       _____         _        _        _   _
# / ___|  ___ _ __   __ _ _ __ __ _| |_ ___|_   _|__  ___| |_     / \   ___| |_(_) ___  _ __
# \___ \ / _ \ '_ \ / _` | '__/ _` | __/ _ \ | |/ _ \/ __| __|   / _ \ / __| __| |/ _ \| '_ \
#  ___) |  __/ |_) | (_| | | | (_| | ||  __/ | |  __/\__ \ |_   / ___ \ (__| |_| | (_) | | | |
# |____/ \___| .__/ \__,_|_|  \__,_|\__\___| |_|\___||___/\__| /_/   \_\___|\__|_|\___/|_| |_|
#            |_|
#
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with an app and a test app
#    - Enable useSeparateTestAction with Windows PowerShell 5.1
#    - Add three test codeunits with one test each
#  - Run the "CI/CD" workflow
#  - Verify that RunPipeline skips test execution and the RunTests action runs the test app
#  - Verify the app, test app, and test result artifacts, including each codeunit's result
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

if ($linux) {
    Write-Host 'The separate RunTests action requires a Windows container; skipping this scenario on Linux.'
    return
}

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

function Test-ActionLogContainsFromRun {
    Param(
        [string] $repository,
        [string] $runId,
        [string] $jobName,
        [string] $stepName,
        [string] $actionName,
        [string] $expectedText
    )

    try {
        Test-LogContainsFromRun -repository $repository -runid $runId -jobName $jobName `
            -stepName $stepName -expectedText $expectedText
    }
    catch {
        Test-LogContainsFromRun -repository $repository -runid $runId -jobName $jobName `
            -stepName $actionName -expectedText $expectedText
    }
}

$previousLocation = Get-Location
$repository = "$githubOwner/$repoName"
$branch = "main"
$template = "https://github.com/$pteTemplate"
$expectedTestCases = [ordered]@{
    "60000" = "SeparateTestActionE2E"
    "60001" = "SeparateTestActionE2E2"
    "60002" = "SeparateTestActionE2E3"
}

SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

CreateAlGoRepository `
    -github:$github `
    -template $template `
    -repository $repository `
    -branch $branch `
    -contentPath (Join-Path $PSScriptRoot "..\..\pte") `
    -contentScript {
        Param([string] $path)

        Add-PropertiesToJsonFile -path (Join-Path $path ".AL-Go\settings.json") -properties @{
            "appFolders" = @("My App")
            "testFolders" = @("My App.Test")
            "githubRunnerShell" = "powershell"
            "useSeparateTestAction" = @{
                "enabled"  = $true
                "testType" = ""
            }
        }

        @'
codeunit 60000 "Separate Test Action E2E"
{
    Subtype = Test;

    [Test]
    procedure SeparateTestActionE2E()
    begin
        if (2 + 2 <> 4) then
            Error('Unexpected arithmetic result.');
    end;
}

codeunit 60001 "Separate Test Action E2E 2"
{
    Subtype = Test;

    [Test]
    procedure SeparateTestActionE2E2()
    begin
        if (3 + 3 <> 6) then
            Error('Unexpected arithmetic result.');
    end;
}

codeunit 60002 "Separate Test Action E2E 3"
{
    Subtype = Test;

    [Test]
    procedure SeparateTestActionE2E3()
    begin
        if (4 + 4 <> 8) then
            Error('Unexpected arithmetic result.');
    end;
}
'@ | Set-ContentLF -Path (Join-Path $path "My App.Test\HelloWorld.Test.al")
    }
$repoPath = (Get-Location).Path

$run = RunCICD -repository $repository -branch $branch -wait

RefreshToken -repository $repository
$headers = GetHeaders -token $ENV:GH_TOKEN -repository $repository
$url = "https://api.github.com/repos/$repository/actions/runs/$($run.id)"
$run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json)
if ($run.conclusion -ne "success") {
    throw "CI/CD workflow run $($run.id) concluded with '$($run.conclusion)' (expected 'success')"
}

$buildJobName = "Build . (Default)*(Default)"
Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
    -stepName "Build" -actionName "RunPipeline" `
    -expectedText "useSeparateTestAction is enabled: skipping normal test execution in RunPipeline and keeping the container alive for the RunTests action"
Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
    -stepName "Run Tests" -actionName "RunTests" -expectedText "Running tests against container"
Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
    -stepName "Run Tests" -actionName "RunTests" -expectedText "Running on Windows, PowerShell 5.1"
Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
    -stepName "Run Tests" -actionName "RunTests" -expectedText "Using al CLI version"
Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
    -stepName "Run Tests" -actionName "RunTests" -expectedText "Running tests in My App.Test"

Test-ArtifactsFromRun `
    -runid $run.id `
    -folder "artifacts" `
    -expectedArtifacts @{"Apps" = 1; "TestApps" = 1} `
    -expectedNumberOfTests $expectedTestCases.Count `
    -repoVersion "1.0" `
    -appVersion ""

$testResultFiles = @(Get-Item -Path (Join-Path $repoPath "artifacts\*-TestResults*\TestResults.xml"))
$testResultFiles.Count | Should -Be 1
[xml] $testResults = Get-Content -Path $testResultFiles[0].FullName -Encoding UTF8
foreach ($codeunitId in $expectedTestCases.Keys) {
    $testCaseName = $expectedTestCases[$codeunitId]
    @($testResults.SelectNodes("//testcase[@name='$testCaseName' and starts-with(@classname, '$codeunitId ')]")).Count | Should -Be 1
}

Set-Location $previousLocation
RemoveRepository -repository $repository -path $repoPath
