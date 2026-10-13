[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Describe 'DetermineCopilotPRReview action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/DetermineCopilotPRReview' -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'Used by Pester test scopes.')]
        $scriptPath = Join-Path $scriptRoot 'DetermineCopilotPRReview.ps1'
        $script:headSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    }

    BeforeEach {
        $env:GITHUB_API_URL = 'https://api.github.test'
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
        Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -Encoding UTF8
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'DetermineCopilotPRReview.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'DetermineCopilotPRReview' -actionScript $actionScript -outputs ([ordered]@{
            enabled = 'Whether Copilot code review is enabled'
            eligible = 'Whether the resolved pull request is eligible for review'
            prNumber = 'Resolved pull request number'
            headSha = 'Resolved pull request head SHA'
            baseRef = 'Resolved pull request base branch'
            model = 'Copilot consolidation model'
            leafModel = 'Copilot leaf-review model'
        })
    }

    It 'Does not call GitHub when review is disabled' {
        Mock Invoke-RestMethod { throw 'GitHub API should not be called' }

        & $scriptPath -token token -repository owner/repo -workflowHeadSha $script:headSha `
            -codeReviewAgent '{"enabled":false,"model":"root","leafModel":"leaf"}'

        $output = Get-Content -LiteralPath $env:GITHUB_OUTPUT
        $output | Should -Contain 'enabled=false'
        $output | Should -Contain 'eligible=false'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'Returns an eligible non-draft pull request from a user' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                number = 42
                state = 'open'
                draft = $false
                head = [pscustomobject]@{ sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }
                base = [pscustomobject]@{ ref = 'main' }
                user = [pscustomobject]@{ type = 'User' }
            }
        }

        & $scriptPath -token token -repository owner/repo -pullRequestNumber 42 -workflowHeadSha $script:headSha `
            -codeReviewAgent '{"enabled":true,"model":"root","leafModel":"leaf"}'

        $output = Get-Content -LiteralPath $env:GITHUB_OUTPUT
        $output | Should -Contain 'eligible=true'
        $output | Should -Contain 'prNumber=42'
        $output | Should -Contain "headSha=$script:headSha"
        $output | Should -Contain 'baseRef=main'
        $output | Should -Contain 'model=root'
        $output | Should -Contain 'leafModel=leaf'
    }

    It 'Rejects bot-authored and stale pull requests' -TestCases @(
        @{ AuthorType = 'Bot'; HeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }
        @{ AuthorType = 'User'; HeadSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' }
    ) {
        param($AuthorType, $HeadSha)

        Mock Invoke-RestMethod {
            [pscustomobject]@{
                number = 42
                state = 'open'
                draft = $false
                head = [pscustomobject]@{ sha = $HeadSha }
                base = [pscustomobject]@{ ref = 'main' }
                user = [pscustomobject]@{ type = $AuthorType }
            }
        }

        & $scriptPath -token token -repository owner/repo -pullRequestNumber 42 -workflowHeadSha $script:headSha `
            -codeReviewAgent '{"enabled":true,"model":"root","leafModel":"leaf"}'

        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'eligible=false'
    }
}
