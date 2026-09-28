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

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

if ($linux) {
    Write-Host 'The separate RunTests action requires a Windows container; skipping this scenario on Linux.'
    return
}

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

function Test-E2ERepositoryExists {
    Param(
        [string] $repository
    )

    RefreshToken -repository $repository
    $headers = GetHeaders -token $ENV:GH_TOKEN -repository $repository
    try {
        InvokeWebRequest -Method Get -Headers $headers -Uri "https://api.github.com/repos/$repository" | Out-Null
        return $true
    }
    catch {
        if ($null -ne $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        throw
    }
}

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

function Remove-E2ELocalRepository {
    Param(
        [string] $path
    )

    if (-not $path) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($path)
    $tempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $fullPath.StartsWith($tempPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$fullPath is not a temporary path"
    }

    if (Test-Path -LiteralPath $fullPath) {
        Set-Location $tempPath
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
}

$previousLocation = Get-Location
$repository = "$githubOwner/$repoName"
$branch = "main"
$template = "https://github.com/$pteTemplate"
$repoPath = ""
$expectedTestCaseName = "SeparateTestActionE2E"
$scenarioError = $null

SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository
if (Test-E2ERepositoryExists -repository $repository) {
    throw "Refusing to use existing repository $repository for the E2E scenario."
}

try {
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
                "useSeparateTestAction" = $true
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
        -stepName "Run Tests" -actionName "RunTests" -expectedText "Using al CLI version"
    Test-ActionLogContainsFromRun -repository $repository -runId $run.id -jobName $buildJobName `
        -stepName "Run Tests" -actionName "RunTests" -expectedText "Running tests in My App.Test"

    Test-ArtifactsFromRun `
        -runid $run.id `
        -folder "artifacts" `
        -expectedArtifacts @{"Apps" = 1; "TestApps" = 1} `
        -expectedNumberOfTests 1 `
        -repoVersion "1.0" `
        -appVersion ""

    $testResultFiles = @(Get-Item -Path (Join-Path $repoPath "artifacts\*-TestResults*\TestResults.xml"))
    $testResultFiles.Count | Should -Be 1
    [xml] $testResults = Get-Content -Path $testResultFiles[0].FullName -Encoding UTF8
    @($testResults.SelectNodes("//testcase[@name='$expectedTestCaseName']")).Count | Should -Be 1
}
catch {
    $scenarioError = $_
    throw
}
finally {
    if (-not $repoPath) {
        $currentPath = [System.IO.Path]::GetFullPath((Get-Location).Path)
        $tempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($currentPath -ne [System.IO.Path]::GetFullPath($previousLocation.Path) -and
            $currentPath.StartsWith($tempPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $repoPath = $currentPath
        }
    }
    Set-Location $previousLocation
    try {
        try {
            if (Test-E2ERepositoryExists -repository $repository) {
                RemoveRepository -repository $repository
            }
        }
        finally {
            Remove-E2ELocalRepository -path $repoPath
        }
    }
    catch {
        if ($null -ne $scenarioError) {
            Write-Host "::Warning::E2E cleanup failed: $($_.Exception.Message)"
        }
        else {
            throw
        }
    }
}
