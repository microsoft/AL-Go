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
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'intakeWorkflow', Justification = 'False positive across Pester scopes.')]
        $intakeWorkflow = Get-Content -Path (Join-Path $workflowFolder 'CopilotPRReview.yaml') -Encoding UTF8 -Raw
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'runnerWorkflow', Justification = 'False positive across Pester scopes.')]
        $runnerWorkflow = Get-Content -Path (Join-Path $workflowFolder 'CopilotPRReviewRunner.yaml') -Encoding UTF8 -Raw
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'reviewAction', Justification = 'False positive across Pester scopes.')]
        $reviewAction = Get-Content -Path (Join-Path $PSScriptRoot '..\..\Actions\ReviewAgent\ReviewAgent.ps1' -Resolve) -Encoding UTF8 -Raw
    }

    It 'Reads the repository-level opt-in setting from trusted content' {
        $runnerWorkflow | Should -Match 'name:\s+Checkout trusted settings'
        $runnerWorkflow | Should -Match 'get:\s+CodeReviewAgent,BCQuality'
        $runnerWorkflow | Should -Match "project:\s+''"
        $runnerWorkflow | Should -Match "workflowName:\s+''"
        $runnerWorkflow | Should -Match 'codeReviewSettingsJson:\s+\$\{\{\s+env\.CodeReviewAgent\s+\}\}'
        $runnerWorkflow | Should -Match 'bcqualitySettingsJson:\s+\$\{\{\s+env\.BCQuality\s+\}\}'
        $runnerWorkflow | Should -Match 'model:\s+\$\{\{\s+steps\.context\.outputs\.model\s+\}\}'
        $runnerWorkflow | Should -Match 'leafModel:\s+\$\{\{\s+steps\.context\.outputs\.leafModel\s+\}\}'
        $runnerWorkflow | Should -Match 'bcqualitySettingsJson:\s+\$\{\{\s+steps\.context\.outputs\.bcqualitySettingsJson\s+\}\}'
        $reviewAction | Should -Match ([regex]::Escape('$settings[''excludedAuthors'']'))
        $runnerWorkflow | Should -Match "needs\.prepare\.outputs\.eligible == 'true'"
        $runnerWorkflow | Should -Not -Match 'needs\.prepare\.outputs\.enabled'
        $runnerWorkflow | Should -Match 'model:\s+\$\{\{\s+needs\.prepare\.outputs\.model\s+\}\}'
        $runnerWorkflow | Should -Match 'leafModel:\s+\$\{\{\s+needs\.prepare\.outputs\.leafModel\s+\}\}'
        ([regex]::Matches($runnerWorkflow, 'bcqualitySettingsJson:\s+\$\{\{\s+needs\.prepare\.outputs\.bcqualitySettingsJson\s+\}\}')).Count |
            Should -Be 3
        $runnerWorkflow | Should -Match 'token:\s+\$\{\{\s+secrets\.BCQUALITY_TOKEN\s+\}\}'
        $runnerWorkflow | Should -Not -Match 'COPILOT_CLI_VERSION'
        $runnerWorkflow | Should -Not -Match 'copilotCliVersion:'
        $runnerWorkflow | Should -Match '(?m)^  REVIEW_AGENT_VERSION:\s+10\.0\.7\r?$'
        ([regex]::Matches($runnerWorkflow, 'agentVersion:\s+\$\{\{\s+env\.REVIEW_AGENT_VERSION\s+\}\}')).Count |
            Should -Be 2
    }

    It 'Uses the review action without a third workflow' {
        ([regex]::Matches($runnerWorkflow, 'runs-on:\s+\[\s+windows-latest\s+\]')).Count | Should -Be 3
        $runnerWorkflow | Should -Match '(?m)^  review:'
        $runnerWorkflow | Should -Match '(?m)^  publish:'
        ([regex]::Matches($runnerWorkflow, 'uses:\s+microsoft/AL-Go-Actions/ReviewAgent@main')).Count | Should -Be 4
        $runnerWorkflow | Should -Not -Match '(?m)^\s+run:\s*\|'
        Test-Path (Join-Path $workflowFolder 'CopilotPRReview.yml') | Should -BeFalse
        $runnerWorkflow | Should -Not -Match 'BC-ALAgents'
    }

    It 'Separates concurrency groups by intake run rather than shared head branch' {
        $runnerWorkflow | Should -Match 'group: copilot-pr-review-runner-\$\{\{ github\.event\.workflow_run\.id \}\}'
        $runnerWorkflow | Should -Not -Match 'group:.*head_branch'
    }

    It 'Serializes publication per pull request without cancelling the active publisher' {
        $publishJob = [regex]::Match($runnerWorkflow, '(?ms)^  publish:.*').Value
        $reviewJob = [regex]::Match($runnerWorkflow, '(?ms)^  review:.*?(?=^  publish:)').Value
        $publishJob | Should -Match 'group: copilot-pr-review-publish-\$\{\{ needs\.prepare\.outputs\.prNumber \}\}'
        $publishJob | Should -Match 'cancel-in-progress: false'
        $reviewJob | Should -Not -Match 'concurrency:'
    }

    It 'Keeps both template workflow sets identical' {
        $appSourceWorkflowFolder = Join-Path $PSScriptRoot '..\..\Templates\AppSource App\.github\workflows' -Resolve
        Get-Content -Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReview.yaml') -Encoding UTF8 -Raw | Should -BeExactly $intakeWorkflow
        Get-Content -Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReviewRunner.yaml') -Encoding UTF8 -Raw | Should -BeExactly $runnerWorkflow
        Test-Path (Join-Path $appSourceWorkflowFolder 'CopilotPRReview.yml') | Should -BeFalse
    }

    It 'Uses the installed BCQuality plugin through the review action' {
        $runnerWorkflow | Should -Match '(?ms)name:\s+Setup Copilot CLI.*?phase:\s+prepare'
        $runnerWorkflow | Should -Match '(?ms)name:\s+Setup BCQuality\s+id:\s+setup\s+uses:\s+microsoft/AL-Go-Actions/SetupBCQuality@main'
        $runnerWorkflow | Should -Match 'bcqualitySettingsJson:\s+\$\{\{\s+needs\.prepare\.outputs\.bcqualitySettingsJson\s+\}\}'
        $runnerWorkflow | Should -Match 'bcqualityRoot:\s+\$\{\{\s+steps\.setup\.outputs\.pluginRoot\s+\}\}'
        $reviewAction | Should -Not -Match 'SetupBCQuality'
        $reviewAction | Should -Match '\$env:BCQUALITY_ROOT = \$bcqualityRoot'
        $reviewAction | Should -Match '\$env:BCQUALITY_REPO = \[string\] \$bcqualitySettings\.marketplaceRepo'
        $reviewAction | Should -Match '\$env:BCQUALITY_VERSION = \[string\] \$bcqualitySettings\.version'
        $reviewAction | Should -Match '\$env:BCQUALITY_SETTINGS_JSON = \(\$bcqualitySettings'
        $reviewAction | Should -Match ([regex]::Escape('$env:BCQUALITY_CONSUME = ''plugin'''))
        $runnerWorkflow | Should -Match "(?ms)uses:\s+microsoft/AL-Go-Actions/SetupBCQuality@main.*?token:\s+\$\{\{\s+secrets\.BCQUALITY_TOKEN\s+\}\}"
        $runnerWorkflow | Should -Not -Match 'bcqualityToken:'
        $runnerWorkflow | Should -Not -Match 'bcqualitySha|bcquality_sha'
        $runnerWorkflow | Should -Not -Match '(?ms)^  review:.*?^    outputs:'
        $runnerWorkflow | Should -Not -Match 'BC-ALAgents'
    }

    It 'Grants only the permissions required by each security boundary' {
        $prepareJob = [regex]::Match($runnerWorkflow, '(?ms)^  prepare:.*?(?=^  review:)').Value
        $intakeWorkflow | Should -Match "(?ms)permissions:\s+contents: read\s+jobs:"
        $runnerWorkflow | Should -Match "(?ms)prepare:.*?permissions:\s+actions: read\s+contents: read"
        $prepareJob | Should -Match 'pull-requests:\s+read'
        $runnerWorkflow | Should -Match 'copilot-requests:\s+write'
        $runnerWorkflow | Should -Match 'pull-requests:\s+write'
        $runnerWorkflow | Should -Match 'issues:\s+write'
        $runnerWorkflow | Should -Match "(?ms)review:.*?permissions:\s+contents: read\s+pull-requests: read\s+copilot-requests: write"
        $runnerWorkflow | Should -Match "(?ms)publish:.*?permissions:\s+contents: read\s+issues: write\s+pull-requests: write"
    }

    It 'Transfers pull request metadata and applies trusted eligibility settings' {
        $intakeWorkflow | Should -Match 'name:\s+copilot-pr-review-metadata'
        $intakeWorkflow | Should -Match 'path:\s+\$\{\{\s+github\.event_path\s+\}\}'
        $runnerWorkflow | Should -Match 'name:\s+copilot-pr-review-metadata'
        $runnerWorkflow | Should -Match 'run-id:\s+\$\{\{\s+github\.event\.workflow_run\.id\s+\}\}'
        $runnerWorkflow | Should -Match "workflowHeadSha:\s+\$\{\{\s+github\.event\.workflow_run\.head_sha\s+\}\}"
        $runnerWorkflow | Should -Match "workflowRunId:\s+\$\{\{\s+github\.event\.workflow_run\.id\s+\}\}"
        $reviewAction | Should -Match ([regex]::Escape('$owner -notin $excludedAuthors'))
        $runnerWorkflow | Should -Not -Match 'business-central-bot'
        $runnerWorkflow | Should -Not -Match 'ALLOWED_BASE_BRANCHES'
        $runnerWorkflow | Should -Not -Match 'Invoke-RestMethod'
        $reviewAction | Should -Match 'InvokeWebRequest'
        $runnerWorkflow | Should -Match "needs\.prepare\.outputs\.eligible == 'true'"
        $runnerWorkflow | Should -Match 'prNumber:\s+\$\{\{\s+needs\.prepare\.outputs\.prNumber\s+\}\}'
        $runnerWorkflow | Should -Match 'prHeadSha:\s+\$\{\{\s+needs\.prepare\.outputs\.headSha\s+\}\}'
        $reviewAction | Should -Match 'Pull request head SHA does not match the triggering workflow run'
    }
}
