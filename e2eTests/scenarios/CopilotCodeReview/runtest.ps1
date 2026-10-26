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
# Copilot code review
#
# This test tests the following scenario:
#
#  - Skip the Linux invocation so only one review runs
#  - Create a new repository based on the PTE template with 1 app
#  - Enable CodeReviewAgent with all other settings left at their defaults
#  - Run "Update AL-Go System Files" directly on main before creating the PR
#  - Create one PR adding a small AL procedure
#  - Wait up to 40 minutes for both review workflows, without rerunning them
#  - Check both workflows succeed on their first attempt with no extra runs
#  - Check the runner produces a copilot-pr-review-final-* artifact
#  - Cleanup the repository and local checkout on success; leave them on failure
#
# This tests orchestration, not review contents, findings, comments, or AL build results.
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
if ($linux) {
    Write-Host '::Notice::CopilotCodeReview runs only in the Windows scenario job to avoid duplicate paid reviews.'
    return
}

Push-Location
Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot '..\..\e2eTestHelper.psm1') -Force -DisableNameChecking

$repository = "$githubOwner/$repoName"
$template = "https://github.com/$pteTemplate"
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

CreateAlGoRepository -github:$github -template $template -repository $repository -branch main -addRepoSettings @{
    CodeReviewAgent = @{ enabled = $true }
} -contentScript {
    Param([string] $path)
    $null = CreateNewAppInFolder -folder $path -name 'ReviewFixture'
    Add-PropertiesToJsonFile -path (Join-Path $path '.AL-Go\settings.json') -properties @{ appFolders = @('ReviewFixture') }
}
$repoPath = (Get-Location).Path

# Finish trusted settings and workflow generation before opening the only PR.
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $algoauthapp -repository $repository -branch main | Out-Null
Pull -branch main

$branch = 'review-fixture'
$fixturePath = 'ReviewFixture/CustomerExistence.Codeunit.al'
invoke-git checkout -b $branch
@'
codeunit 50000 "Customer Existence"
{
    procedure HasCustomers(): Boolean
    var
        Customer: Record Customer;
    begin
        exit(not Customer.IsEmpty());
    end;
}
'@ | Set-ContentLF -Path (Join-Path $repoPath $fixturePath)
invoke-git add *
invoke-git commit -m 'Add customer existence check'
invoke-git push --set-upstream origin $branch
invoke-gh pr create --repo $repository --base main --head $branch --title 'Add customer existence check' --body 'Add a helper that checks whether any customers exist.'

# WaitWorkflow retries failed workflows. Poll these runs instead: one trigger, a finite wait, no reruns.
$deadline = [DateTime]::UtcNow.AddMinutes(40)
foreach ($workflow in @('CopilotPRReview.yaml', 'CopilotPRReviewRunner.yaml')) {
    do {
        RefreshToken -repository $repository
        $runs = invoke-gh api "/repos/$repository/actions/workflows/$workflow/runs?per_page=100" -silent -returnValue | ConvertFrom-Json | ConvertTo-HashTable -recurse
        $workflowRuns = @($runs.workflow_runs)
        if ($workflowRuns.Count -gt 1) {
            throw "Unexpected extra $workflow run; refusing further review execution."
        }
        $run = $workflowRuns | Select-Object -First 1
        if ($run -and $run.status -eq 'completed') { break }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out waiting for $workflow. No inference retry will be attempted."
        }
        Start-Sleep -Seconds 30
    } while ($true)
    if ($run.conclusion -ne 'success' -or $run.run_attempt -ne 1) {
        throw "$workflow must succeed on its first attempt; run $($run.id) concluded '$($run.conclusion)'."
    }
}

$artifacts = invoke-gh api "/repos/$repository/actions/runs/$($run.id)/artifacts" -silent -returnValue | ConvertFrom-Json | ConvertTo-HashTable -recurse
@($artifacts.artifacts | Where-Object { $_.name -like 'copilot-pr-review-final-*' }) | Should -Not -BeNullOrEmpty

Pop-Location
RemoveRepository -repository $repository -path $repoPath
