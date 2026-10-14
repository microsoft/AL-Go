[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0

Describe 'CopilotPRReview action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/CopilotPRReview' -Resolve
        $script:actionScriptPath = Join-Path $scriptRoot 'CopilotPRReview.ps1'
        $script:originalGitHubOutput = $env:GITHUB_OUTPUT
        $script:originalGitHubApiUrl = $env:GITHUB_API_URL
    }

    AfterAll {
        $env:GITHUB_OUTPUT = $script:originalGitHubOutput
        $env:GITHUB_API_URL = $script:originalGitHubApiUrl
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'CopilotPRReview.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'CopilotPRReview' -actionScript $actionScript -DefaultShell pwsh -outputs ([ordered]@{
            enabled = 'Whether Copilot review is enabled'
            eligible = 'Whether the pull request is eligible for review'
            model = 'Model used for final review consolidation'
            leafModel = 'Model used for isolated leaf reviews'
            prNumber = 'Validated pull request number'
            headSha = 'Validated pull request head SHA'
            baseRef = 'Validated pull request base branch'
            bcqualitySha = 'Resolved BCQuality marketplace commit'
            bcqualityRoot = 'Path to the installed and filtered BCQuality plugin'
            filterReport = 'Path to the BCQuality filter report'
            copilotCliVersion = 'Installed Copilot CLI version'
        })
    }

    It 'Resolves and validates eligible pull request context' {
        $metadataPath = Join-Path $TestDrive 'event.json'
        @{
            pull_request = @{
                number = 42
                draft = $false
                user = @{ login = 'contributor' }
                head = @{ sha = 'abc123' }
                base = @{ ref = 'main' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
        $env:GITHUB_API_URL = 'https://api.github.test'
        Mock Invoke-RestMethod {
            @{
                number = 42
                state = 'open'
                draft = $false
                head = @{ sha = 'abc123' }
                base = @{ ref = 'main' }
            }
        }

        & $script:actionScriptPath `
            -phase context `
            -settingsJson '{"enabled":true,"model":"root-model","leafModel":"leaf-model","excludedOwners":[]}' `
            -metadataPath $metadataPath `
            -workflowHeadSha 'abc123' `
            -token 'token' `
            -repository 'owner/repository'

        $outputs = @{}
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | ForEach-Object {
            $pair = $_ -split '=', 2
            if ($pair.Count -eq 2) {
                $outputs[$pair[0]] = $pair[1]
            }
        }

        $outputs.enabled | Should -Be 'true'
        $outputs.eligible | Should -Be 'true'
        $outputs.model | Should -Be 'root-model'
        $outputs.leafModel | Should -Be 'leaf-model'
        $outputs.prNumber | Should -Be '42'
        $outputs.headSha | Should -Be 'abc123'
        $outputs.baseRef | Should -Be 'main'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.github.test/repos/owner/repository/pulls/42'
        }
    }
}
