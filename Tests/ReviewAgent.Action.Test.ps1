[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0

Describe 'ReviewAgent action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/ReviewAgent' -Resolve
        $script:actionScriptPath = Join-Path $scriptRoot 'ReviewAgent.ps1'
        . (Join-Path $scriptRoot '..\AL-Go-Helper.ps1' -Resolve)
        $script:originalGitHubOutput = $env:GITHUB_OUTPUT
        $script:bcqualitySettings = @{
            marketplaceRepo = 'https://github.com/microsoft/BCQuality'
            version = '1.7'
            enabledLayers = @('microsoft', 'community', 'custom')
            disabledSkills = @()
            knowledge = @{ allow = @(); deny = @() }
        }
        $script:bcqualitySettingsJson = $script:bcqualitySettings | ConvertTo-Json -Compress -Depth 10
    }

    BeforeEach {
        $script:contextArguments = @{ repository = 'contoso/app'; token = 'test-token'; workflowRunId = '7' }
        $script:apiPullRequest = @{
            number = 42; state = 'open'; draft = $false
            user = @{ login = 'contributor' }
            head = @{ sha = 'abc123'; ref = 'feature'; repo = @{ full_name = 'contributor/app' } }
            base = @{ ref = 'main'; repo = @{ full_name = 'contoso/app' } }
        }
        $script:apiRun = @{
            event = 'pull_request'; conclusion = 'success'; head_sha = 'abc123'; head_branch = 'feature'
            repository = @{ full_name = 'contoso/app' }
            head_repository = @{ full_name = 'contributor/app' }
            pull_requests = @(@{ number = 42 })
        }
        $script:apiCandidates = @($script:apiPullRequest)
        Mock InvokeWebRequest {
            param($uri)
            $response = switch -Regex ($uri) {
                '/actions/runs/7$' { $apiRun; break }
                '/pulls/42$' { $apiPullRequest; break }
                '/pulls\?state=open&head=' {
                    $page = [int] [regex]::Match($uri, '[?&]page=(\d+)').Groups[1].Value
                    ,@($apiCandidates | Select-Object -Skip (($page - 1) * 100) -First 100)
                    break
                }
                default { throw "Unexpected API request: $uri" }
            }
            @{ Content = $response | ConvertTo-Json -Depth 10 -Compress }
        }
    }

    AfterAll {
        $env:GITHUB_OUTPUT = $script:originalGitHubOutput
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'ReviewAgent.ps1'
        $yamlTestRoot = Join-Path $TestDrive 'review-agent-standard-contract'
        New-Item -ItemType Directory -Path $yamlTestRoot | Out-Null
        Get-Content -LiteralPath (Join-Path $scriptRoot 'action.yaml') |
            Where-Object { $_ -notmatch 'COPILOT_REVIEW_ENGINE_(?:REPOSITORY|REF):' } |
            Set-Content -LiteralPath (Join-Path $yamlTestRoot 'action.yaml')
        YamlTest -scriptRoot $yamlTestRoot -actionName 'ReviewAgent' -actionScript $actionScript -DefaultShell pwsh -outputs ([ordered]@{
            eligible = 'Whether the pull request is eligible for review'
            model = 'Model used for final review consolidation'
            leafModel = 'Model used for isolated leaf reviews'
            prNumber = 'Validated pull request number'
            headSha = 'Validated pull request head SHA'
            baseRef = 'Validated pull request base branch'
            bcqualitySettingsJson = 'Validated BCQuality settings as compressed JSON'
        })
    }

    It 'Forwards the action repository and requested ref without claiming the ref is a commit' {
        $actionYaml = Get-Content -LiteralPath (Join-Path $scriptRoot 'action.yaml') -Raw
        $actionYaml | Should -Match 'COPILOT_REVIEW_ENGINE_REPOSITORY:\s+\$\{\{\s+github\.action_repository\s+\}\}'
        $actionYaml | Should -Match 'COPILOT_REVIEW_ENGINE_REF:\s+\$\{\{\s+github\.action_ref\s+\}\}'
        $actionYaml | Should -Not -Match 'COPILOT_REVIEW_ENGINE_COMMIT:'
    }

    It 'Resolves and validates eligible pull request context' {
        $metadataPath = Join-Path $TestDrive 'event.json'
        @{
            pull_request = @{
                number = 42
                draft = $true
                user = @{ login = 'forged-owner' }
                head = @{ sha = 'forged-sha' }
                base = @{ ref = 'forged-base' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'

        $customBCQualitySettings = $script:bcqualitySettings.Clone()
        $customBCQualitySettings.marketplaceRepo = 'https://github.com/contoso/BCQuality'
        $customBCQualitySettings.version = '2.0'

        & $script:actionScriptPath `
            @script:contextArguments `
            -phase context `
            -codeReviewSettingsJson '{"enabled":true,"model":"root-model","leafModel":"leaf-model","excludedOwners":[]}' `
            -bcqualitySettingsJson ($customBCQualitySettings | ConvertTo-Json -Compress -Depth 10) `
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
        $resolvedBCQualitySettings = $outputs.bcqualitySettingsJson | ConvertFrom-Json
        $resolvedBCQualitySettings.marketplaceRepo | Should -Be 'https://github.com/contoso/BCQuality'
        $resolvedBCQualitySettings.version | Should -Be '2.0'
        $resolvedBCQualitySettings.enabledLayers | Should -Be @('microsoft', 'community', 'custom')
    }

    It 'Rejects an authoritative head that does not match the triggering workflow run' {
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
                @script:contextArguments `
                -phase context `
                -codeReviewSettingsJson '{"model":"root-model","leafModel":"leaf-model","excludedOwners":[]}' `
                -bcqualitySettingsJson $script:bcqualitySettingsJson `
                -metadataPath $metadataPath `
                -workflowHeadSha 'workflow-run-sha'
        } | Should -Throw 'Pull request head SHA does not match the triggering workflow run.'
    }

    It 'Enforces trusted branch patterns against the authoritative base: <Branch>' -TestCases @(
        @{ Branch = 'main'; Patterns = @(); Eligible = 'true' }
        @{ Branch = 'release/1'; Patterns = @(); Eligible = 'false' }
        @{ Branch = 'release/1'; Patterns = @('release/*'); Eligible = 'true' }
        @{ Branch = 'release/team/1'; Patterns = @('release/*'); Eligible = 'false' }
        @{ Branch = 'release/team/1'; Patterns = @('release/**'); Eligible = 'true' }
        @{ Branch = 'release/1-alpha'; Patterns = @('release/**', '!release/**-alpha'); Eligible = 'false' }
        @{ Branch = 'release/1-alpha'; Patterns = @('release/**', '!release/**-alpha', 'release/1-alpha'); Eligible = 'true' }
        @{ Branch = 'Main'; Patterns = @('main'); Eligible = 'false' }
        @{ Branch = 'v2.10.3'; Patterns = @('v[12].[0-9]+.[0-9]+'); Eligible = 'true' }
        @{ Branch = 'v3.10.3'; Patterns = @('v[12].[0-9]+.[0-9]+'); Eligible = 'false' }
        @{ Branch = 'releases/1'; Patterns = @('releases?/1'); Eligible = 'true' }
        @{ Branch = 'release/1'; Patterns = @('releases?/1'); Eligible = 'true' }
        @{ Branch = 'releaseX/1'; Patterns = @('releases?/1'); Eligible = 'false' }
        @{ Branch = 'release+1'; Patterns = @('release\+1'); Eligible = 'true' }
        @{ Branch = 'release11'; Patterns = @('release\+1'); Eligible = 'false' }
    ) {
        param($Branch, $Patterns, $Eligible)
        $script:apiPullRequest.base.ref = $Branch
        $metadataPath = Join-Path $TestDrive 'branch-event.json'
        '{"pull_request":{"number":42,"base":{"ref":"main"}}}' |
            Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'branch-output.txt'
        Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -Encoding UTF8
        $settingsJson = @{
            enabled = $true; branches = $Patterns; excludedOwners = @()
        } | ConvertTo-Json -Depth 5 -Compress
        $qualitySettings = $script:bcqualitySettings.Clone()
        $qualitySettings.enabledLayers = @()

        & $script:actionScriptPath @script:contextArguments -phase context -metadataPath $metadataPath `
            -workflowHeadSha 'abc123' -codeReviewSettingsJson $settingsJson `
            -bcqualitySettingsJson ($qualitySettings | ConvertTo-Json -Depth 5 -Compress)

        $outputs = Get-Content -LiteralPath $env:GITHUB_OUTPUT
        $outputs | Should -Contain "eligible=$Eligible"
        $resolvedQuality = ($outputs | Where-Object { $_ -like 'bcqualitySettingsJson=*' }) -replace '^bcqualitySettingsJson=', '' | ConvertFrom-Json
        @($resolvedQuality.enabledLayers) | Should -Be @('microsoft', 'community', 'custom')
    }

    It 'Does not review when the trusted opt-in is <Case>' -TestCases @(
        @{ Case = 'false'; Settings = '{"enabled":false,"excludedOwners":[]}' }
        @{ Case = 'missing'; Settings = '{"excludedOwners":[]}' }
        @{ Case = 'a string'; Settings = '{"enabled":"true","excludedOwners":[]}' }
    ) {
        param($Case, $Settings)
        $metadataPath = Join-Path $TestDrive 'opt-in-event.json'
        '{"pull_request":{"number":42}}' | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'opt-in-output.txt'
        & $script:actionScriptPath @script:contextArguments -phase context -metadataPath $metadataPath `
            -workflowHeadSha 'abc123' -codeReviewSettingsJson $Settings -bcqualitySettingsJson $script:bcqualitySettingsJson

        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'eligible=false'
    }

    It 'Uses authoritative <Case> rather than artifact eligibility metadata' -TestCases @(
        @{ Case = 'draft state'; Draft = $true; Owner = 'contributor'; State = 'open' }
        @{ Case = 'excluded author'; Draft = $false; Owner = 'excluded'; State = 'open' }
        @{ Case = 'closed state'; Draft = $false; Owner = 'contributor'; State = 'closed' }
    ) {
        param($Case, $Draft, $Owner, $State)
        $script:apiPullRequest.draft = $Draft
        $script:apiPullRequest.user.login = $Owner
        $script:apiPullRequest.state = $State
        $metadataPath = Join-Path $TestDrive 'eligibility-event.json'
        '{"pull_request":{"number":42,"draft":false,"user":{"login":"allowed"}}}' |
            Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'eligibility-output.txt'
        & $script:actionScriptPath @script:contextArguments -phase context -metadataPath $metadataPath `
            -workflowHeadSha 'abc123' -codeReviewSettingsJson '{"enabled":true,"excludedOwners":["excluded"]}' `
            -bcqualitySettingsJson $script:bcqualitySettingsJson

        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'eligible=false'
    }

    It 'Rejects a different pull request association even with the same head SHA' {
        $script:apiRun.pull_requests = @(@{ number = 99 })
        $metadataPath = Join-Path $TestDrive 'wrong-pr-event.json'
        '{"pull_request":{"number":42}}' | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        {
            & $script:actionScriptPath @script:contextArguments -phase context -metadataPath $metadataPath `
                -workflowHeadSha 'abc123' -codeReviewSettingsJson '{"enabled":true,"excludedOwners":[]}' `
                -bcqualitySettingsJson $script:bcqualitySettingsJson
        } | Should -Throw '*identity does not match*'
    }

    It 'Validates fork heads when the run has no pull request associations' {
        $script:apiRun.pull_requests = @()
        $metadataPath = Join-Path $TestDrive 'fork-event.json'
        '{"pull_request":{"number":42}}' | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'fork-output.txt'
        $arguments = $script:contextArguments.Clone()
        $arguments.phase = 'context'
        $arguments.metadataPath = $metadataPath
        $arguments.workflowHeadSha = 'abc123'
        $arguments.codeReviewSettingsJson = '{"enabled":true,"excludedOwners":[]}'
        $arguments.bcqualitySettingsJson = $script:bcqualitySettingsJson

        & $script:actionScriptPath @arguments
        Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain 'eligible=true'

        $script:apiRun.head_repository.full_name = 'unrelated/app'
        { & $script:actionScriptPath @arguments } | Should -Throw '*identity does not match*'
        $script:apiRun.head_repository.full_name = 'contributor/app'
        $script:apiRun.head_branch = 'unrelated-branch'
        { & $script:actionScriptPath @arguments } | Should -Throw '*identity does not match*'
        $script:apiRun.head_branch = 'feature'
        $otherPullRequest = $script:apiPullRequest.Clone()
        $otherPullRequest.number = 99
        $script:apiCandidates += @(1..99 | ForEach-Object {
            @{ number = 100 + $_; head = @{ repo = @{ full_name = 'other/app' }; ref = 'feature'; sha = 'abc123' } }
        })
        $script:apiCandidates += $otherPullRequest
        { & $script:actionScriptPath @arguments } | Should -Throw '*identity is ambiguous*'
    }

    It 'Requires BCQuality settings when resolving review context' {
        $metadataPath = Join-Path $TestDrive 'missing-bcquality-event.json'
        @{
            pull_request = @{
                number = 42
                draft = $false
                user = @{ login = 'contributor' }
                head = @{ sha = 'abc123' }
                base = @{ ref = 'main' }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        {
            & $script:actionScriptPath `
                @script:contextArguments `
                -phase context `
                -codeReviewSettingsJson '{"model":"root-model","leafModel":"leaf-model","excludedOwners":[]}' `
                -metadataPath $metadataPath `
                -workflowHeadSha 'abc123'
        } | Should -Throw 'bcqualitySettingsJson is required.'
    }

    It 'Requires an explicit semantic agent version for executable review phases' {
        {
            & $script:actionScriptPath `
                -phase post `
                -bcqualitySettingsJson $script:bcqualitySettingsJson `
                -reviewWorkspace $TestDrive `
                -reviewOutputDir $TestDrive
        } | Should -Throw "agentVersion must be an exact X.Y.Z semantic version*"
    }
}
