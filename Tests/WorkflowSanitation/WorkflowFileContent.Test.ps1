Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-Go workflows should have similar content" {
    It 'All workflows existing in both templates should have similar content' {
        . (Join-Path $PSScriptRoot '..\..\Actions\CheckForUpdates\yamlclass.ps1')
        . (Join-Path $PSScriptRoot '..\..\Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1')
        $pteWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $appSourceWorkflows = ((Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath).Name
        $pteWorkflows | Where-Object { $appSourceWorkflows -contains $_.Name } | ForEach-Object {
            $pteWorkflowContent = (Get-Content -Path $_.FullName -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
            $appSourceWorkflowContent = (Get-Content -Path (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\$($_.Name)") -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
            if ($_.Name -eq 'CICD.yaml') {
                # CICD.yaml is a special case, as it contains a buildPP section that is not present in the AppSource App template
                $yaml = [Yaml]::Load($_.FullName)
                ModifyBuildWorkflows -yaml $yaml -depth 1 -includeBuildPP $false
                $pteWorkflowContent = $yaml.content -join "`n"
            }
            Write-Host "Comparing $($_.Name)"
            $pteWorkflowContent | Should -Be $appSourceWorkflowContent
        }
    }
}

Describe "PreGateCheck in PullRequestHandler should use runs-on: windows-latest" {
    It 'Check PullRequestHandler.yaml for runs-on: windows-latest' {
        # Check that PullRequestHandler.yaml in both templates uses runs-on: windows-latest, which doesn't get updated by the Update AL-Go System Files action
        $ScriptRoot = $PSScriptRoot
        . (Join-Path $ScriptRoot "../../Actions/CheckForUpdates/yamlclass.ps1")
        foreach($template in @('Per Tenant Extension','AppSource App')) {
            $yaml = [Yaml]::load((Join-Path $ScriptRoot "..\..\Templates\$template\.github\workflows\PullRequestHandler.yaml" -Resolve))
            $yaml.Get('jobs:/PregateCheck:/runs-on').content | Should -Be 'runs-on: windows-latest' -Because "PreGateCheck in $template/PullRequestHandler.yaml should use runs-on: windows-latest"
        }
    }
}

Describe "GitHub event payload should not be used in code" {
    It 'Check for GitHub event payload in code' {
        Push-Location (Join-Path $PSScriptRoot "..\..")
        try {
            $fail = $false
            foreach($file in (Get-ChildItem -Filter '*.yaml' -Recurse)) {
                $yamlFile = $file.FullName
                $lines = Get-Content -Encoding UTF8 -Path $yamlFile
                for($idx = 0; $idx -lt $lines.Count; $idx++) {
                    if ($lines[$idx] -match '^\s*([a-zA-Z_-]*:).*\$\{\{\s*github\.event\..*$') {
                        # OK to use github event payload in environment variables etc
                    }
                    elseif ($lines[$idx] -match '^.*\$\{\{\s*github\.event\..*$') {
                        Write-Host "Event Payload used in code. File: $(Resolve-Path -Path $yamlFile -Relative), Line: $idx, Content: $($lines[$idx].Trim())"
                        $fail = $true
                    }
                }
            }
            $fail | Should -Be $false -Because "GitHub event payload should not be used in code"
        }
        finally {
            Pop-Location
        }
    }
}

Describe "Copilot code review workflows" {
    BeforeAll {
        $workflowFolder = Join-Path $PSScriptRoot '..\..\Templates\Per Tenant Extension\.github\workflows' -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'reusableWorkflow', Justification = 'False positive across Pester scopes.')]
        $reusableWorkflow = Get-Content -Path (Join-Path $workflowFolder 'CopilotPRReview.yml') -Encoding UTF8 -Raw
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'intakeWorkflow', Justification = 'False positive across Pester scopes.')]
        $intakeWorkflow = Get-Content -Path (Join-Path $workflowFolder 'CopilotPRReview.yaml') -Encoding UTF8 -Raw
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'runnerWorkflow', Justification = 'False positive across Pester scopes.')]
        $runnerWorkflow = Get-Content -Path (Join-Path $workflowFolder 'CopilotPRReviewRunner.yaml') -Encoding UTF8 -Raw
    }

    It 'Reads the repository-level opt-in setting from trusted content' {
        $runnerWorkflow | Should -Match 'name:\s+Checkout trusted settings'
        $runnerWorkflow | Should -Match 'get:\s+CodeReviewAgent'
        $runnerWorkflow | Should -Match "project:\s+''"
        $runnerWorkflow | Should -Match "workflowName:\s+''"
        $runnerWorkflow | Should -Match 'model:\s+\$\{\{\s+steps\.output\.outputs\.model\s+\}\}'
        $runnerWorkflow | Should -Match 'leafModel:\s+\$\{\{\s+steps\.output\.outputs\.leafModel\s+\}\}'
        $runnerWorkflow | Should -Match '\$codeReviewAgent\.excludedOwners'
        $runnerWorkflow | Should -Match "needs\.Settings\.outputs\.enabled == 'true'"
        $runnerWorkflow | Should -Match 'copilot_model:\s+\$\{\{\s+needs\.Settings\.outputs\.model\s+\}\}'
        $runnerWorkflow | Should -Match 'copilot_leaf_model:\s+\$\{\{\s+needs\.Settings\.outputs\.leafModel\s+\}\}'
        $runnerWorkflow | Should -Match 'bcquality_token:\s+\$\{\{\s+secrets\.BCQUALITY_TOKEN\s+\}\}'
    }

    It 'Uses the local reusable reviewer workflow' {
        $runnerWorkflow | Should -Match ([regex]::Escape('uses: ./.github/workflows/CopilotPRReview.yml'))
        $runnerWorkflow | Should -Match 'engine_ref:\s+main'
        $runnerWorkflow | Should -Not -Match 'BC-ALAgents'
    }

    It 'Keeps both template workflow sets identical' {
        $appSourceWorkflowFolder = Join-Path $PSScriptRoot '..\..\Templates\AppSource App\.github\workflows' -Resolve
        Get-Content -Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReview.yaml') -Encoding UTF8 -Raw | Should -BeExactly $intakeWorkflow
        Get-Content -Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReviewRunner.yaml') -Encoding UTF8 -Raw | Should -BeExactly $runnerWorkflow
        Get-Content -Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReview.yml') -Encoding UTF8 -Raw | Should -BeExactly $reusableWorkflow
    }

    It 'Uses the installed BCQuality plugin in the reusable workflow' {
        $reusableWorkflow | Should -Match ([regex]::Escape('uses: ./engine/Actions/SetupBCQuality'))
        $reusableWorkflow | Should -Match ([regex]::Escape("token: `${{ steps.bcquality-policy.outputs.marketplace != 'microsoft/BCQuality' && secrets.bcquality_token || '' }}"))
        $reusableWorkflow | Should -Match 'BCQUALITY_ROOT:\s+\$\{\{\s+steps\.bcquality\.outputs\.pluginRoot\s+\}\}'
        $reusableWorkflow | Should -Match 'BCQUALITY_SHA:\s+\$\{\{\s+steps\.bcquality\.outputs\.sourceCommit\s+\}\}'
        $reusableWorkflow | Should -Match 'BCQUALITY_CONSUME:\s+plugin'
        $reusableWorkflow | Should -Not -Match 'BC-ALAgents'
    }

    It 'Grants only the permissions required by each security boundary' {
        $intakeWorkflow | Should -Match "(?ms)permissions:\s+contents: read\s+jobs:"
        $runnerWorkflow | Should -Match "(?ms)Settings:.*?permissions:\s+actions: read\s+contents: read"
        $runnerWorkflow | Should -Match 'copilot-requests:\s+write'
        $runnerWorkflow | Should -Match 'pull-requests:\s+write'
        $runnerWorkflow | Should -Match 'issues:\s+write'
        $reusableWorkflow | Should -Match "(?ms)review:.*?permissions:\s+contents: read\s+pull-requests: read.*?copilot-requests: write"
        $reusableWorkflow | Should -Match "(?ms)publish:.*?permissions:\s+contents: read\s+issues: write\s+pull-requests: write"
    }

    It 'Transfers pull request metadata and applies trusted eligibility settings' {
        $intakeWorkflow | Should -Match 'name:\s+copilot-pr-review-metadata'
        $intakeWorkflow | Should -Match 'path:\s+\$\{\{\s+github\.event_path\s+\}\}'
        $runnerWorkflow | Should -Match 'name:\s+copilot-pr-review-metadata'
        $runnerWorkflow | Should -Match 'run-id:\s+\$\{\{\s+github\.event\.workflow_run\.id\s+\}\}'
        $runnerWorkflow | Should -Match ([regex]::Escape('$owner -notin $excludedOwners'))
        $runnerWorkflow | Should -Not -Match 'business-central-bot'
        $runnerWorkflow | Should -Not -Match 'ALLOWED_BASE_BRANCHES'
        $runnerWorkflow | Should -Not -Match 'Invoke-RestMethod'
        $runnerWorkflow | Should -Match "needs\.Settings\.outputs\.eligible == 'true'"
        $runnerWorkflow | Should -Match 'pr_number:\s+\$\{\{\s+needs\.Settings\.outputs\.prNumber\s+\}\}'
        $runnerWorkflow | Should -Match 'head_sha:\s+\$\{\{\s+needs\.Settings\.outputs\.headSha\s+\}\}'
        $reusableWorkflow | Should -Match 'Supplied PR head SHA does not match the triggering workflow run'
        $reusableWorkflow | Should -Match 'Pull request is no longer eligible for review'
    }
}
