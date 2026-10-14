[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0

Describe 'ReviewAgent action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/ReviewAgent' -Resolve
        $script:actionScriptPath = Join-Path $scriptRoot 'ReviewAgent.ps1'
        $script:originalGitHubOutput = $env:GITHUB_OUTPUT
    }

    AfterAll {
        $env:GITHUB_OUTPUT = $script:originalGitHubOutput
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'ReviewAgent.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'ReviewAgent' -actionScript $actionScript -DefaultShell pwsh -outputs ([ordered]@{
            eligible = 'Whether the pull request is eligible for review'
            model = 'Model used for final review consolidation'
            leafModel = 'Model used for isolated leaf reviews'
            prNumber = 'Validated pull request number'
            headSha = 'Validated pull request head SHA'
            baseRef = 'Validated pull request base branch'
            bcqualityMarketplaceRepo = 'Trusted BCQuality marketplace repository'
            bcqualityVersion = 'Configured BCQuality content version'
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

        & $script:actionScriptPath `
            -phase context `
            -settingsJson '{"model":"root-model","leafModel":"leaf-model","excludedOwners":[],"bcqualityMarketplaceRepo":"https://github.com/contoso/BCQuality","bcqualityVersion":"2.0"}' `
            -metadataPath $metadataPath `
            -workflowHeadSha 'abc123'

        $outputs = @{}
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | ForEach-Object {
            $pair = $_ -split '=', 2
            if ($pair.Count -eq 2) {
                $outputs[$pair[0]] = $pair[1]
            }
        }

        $outputs.eligible | Should -Be 'true'
        $outputs.model | Should -Be 'root-model'
        $outputs.leafModel | Should -Be 'leaf-model'
        $outputs.prNumber | Should -Be '42'
        $outputs.headSha | Should -Be 'abc123'
        $outputs.baseRef | Should -Be 'main'
        $outputs.bcqualityMarketplaceRepo | Should -Be 'https://github.com/contoso/BCQuality'
        $outputs.bcqualityVersion | Should -Be '2.0'
    }

    It 'Rejects metadata that does not match the triggering workflow run' {
        $metadataPath = Join-Path $TestDrive 'mismatched-event.json'
        @{
            pull_request = @{
                number = 42
                draft = $false
                user = @{ login = 'contributor' }
                head = @{ sha = 'metadata-sha' }
                base = @{ ref = 'main' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        {
            & $script:actionScriptPath `
                -phase context `
                -settingsJson '{"model":"root-model","leafModel":"leaf-model","excludedOwners":[],"bcqualityMarketplaceRepo":"https://github.com/microsoft/BCQuality","bcqualityVersion":"1.7"}' `
                -metadataPath $metadataPath `
                -workflowHeadSha 'workflow-run-sha'
        } | Should -Throw 'Pull request head SHA does not match the triggering workflow run.'
    }
}
