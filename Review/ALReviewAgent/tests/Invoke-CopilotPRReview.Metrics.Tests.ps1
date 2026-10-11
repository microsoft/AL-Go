[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'The imported functions resolve these test fixtures through PowerShell dynamic scope.'
)]
param()

BeforeAll {
    $scriptPath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') 'Invoke-CopilotPRReview.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw ($parseErrors | ForEach-Object Message | Out-String)
    }

    $wantedFunctions = @(
        'Get-ObjectPropertyValue',
        'ConvertFrom-CopilotOtelJsonLines',
        'Test-CopilotNumericValue',
        'ConvertTo-CopilotNonNegativeInt64',
        'ConvertTo-CopilotNonNegativeDecimal',
        'Get-CopilotNumericAttribute',
        'Get-CopilotRunMetrics',
        'Write-LogPhaseDetail',
        'Remove-CopilotOtelFile',
        'Read-CopilotOtelFile',
        'Save-CopilotRunMetrics',
        'Assert-RequestedLeafModelObserved',
        'Save-CurrentCopilotRunMetrics',
        'Complete-CopilotProcess',
        'Clear-CopilotMetricsArtifacts'
    )
    $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $wantedFunctions -contains $node.Name
    }, $true) | ForEach-Object {
        . ([scriptblock]::Create($_.Extent.Text))
    }

    function New-ChatSpan {
        param(
            [string] $Model,
            [int64] $InputTokens,
            [int64] $OutputTokens,
            [object] $CachedTokens = $null,
            [object] $CacheCreationTokens = $null,
            [object] $ReasoningTokens = $null,
            [object] $NanoAiu = $null,
            [object] $PremiumRequests = $null,
            [int] $StatusCode = 0,
            [switch] $WithoutUsage
        )

        $attributes = [ordered]@{
            'gen_ai.operation.name' = 'chat'
            'gen_ai.request.model'  = $Model
            'gen_ai.response.model' = $Model
        }
        if (-not $WithoutUsage) {
            $attributes['gen_ai.usage.input_tokens'] = $InputTokens
            $attributes['gen_ai.usage.output_tokens'] = $OutputTokens
        }
        if ($null -ne $CachedTokens) {
            $attributes['gen_ai.usage.cache_read.input_tokens'] = [int64]$CachedTokens
        }
        if ($null -ne $CacheCreationTokens) {
            $attributes['gen_ai.usage.cache_creation.input_tokens'] = [int64]$CacheCreationTokens
        }
        if ($null -ne $ReasoningTokens) {
            $attributes['gen_ai.usage.reasoning.output_tokens'] = [int64]$ReasoningTokens
        }
        if ($null -ne $NanoAiu) {
            $attributes['github.copilot.nano_aiu'] = [decimal]$NanoAiu
        }
        if ($null -ne $PremiumRequests) {
            $attributes['github.copilot.cost'] = [decimal]$PremiumRequests
        }
        return [pscustomobject]@{
            type       = 'span'
            name       = "chat $Model"
            status     = [pscustomobject]@{ code = $StatusCode }
            attributes = [pscustomobject]$attributes
        }
    }
}

Describe 'Get-CopilotRunMetrics' {
    It 'aggregates raw model requests, nested invocations, tokens, and exact AI credits' {
        $records = @(
            [pscustomobject]@{
                type = 'span'
                name = 'invoke_agent'
                attributes = [pscustomobject]@{
                    'gen_ai.operation.name' = 'invoke_agent'
                    'gen_ai.agent.version' = '1.0.81-0'
                }
            },
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 100 -OutputTokens 20 `
                -CachedTokens 40 -CacheCreationTokens 10 -ReasoningTokens 7 `
                -NanoAiu 1500000000 -PremiumRequests 1.5),
            (New-ChatSpan -Model 'gpt-5.4-mini' -InputTokens 50 -OutputTokens 8 `
                -CachedTokens 20 -CacheCreationTokens 0 -NanoAiu 250000000 `
                -PremiumRequests 0.25 -StatusCode 2)
        )

        $metrics = Get-CopilotRunMetrics -Records $records -WallTimeSeconds 12.34567

        $metrics.schema_version | Should -Be 1
        $metrics.metrics_source | Should -Be 'copilot-cli-otel'
        $metrics.cli_version | Should -Be '1.0.81-0'
        $metrics.wall_time_seconds | Should -Be 12.346
        $metrics.prompt_tokens | Should -Be 150
        $metrics.cached_tokens | Should -Be 60
        $metrics.cache_creation_tokens | Should -Be 10
        $metrics.completion_tokens | Should -Be 28
        $metrics.reasoning_tokens | Should -Be 7
        $metrics.total_tokens | Should -Be 178
        $metrics.api_calls | Should -Be 2
        $metrics.failed_api_calls | Should -Be 1
        $metrics.usage_api_calls | Should -Be 2
        $metrics.ai_credits | Should -Be 1.75
        $metrics.premium_requests | Should -Be 1.75
        $metrics.models | Should -Be @('gpt-5.4-mini', 'gpt-5.6-sol')
        $metrics.usage_complete | Should -BeTrue
    }

    It 'keeps the schema stable' {
        $metrics = Get-CopilotRunMetrics

        $metrics.PSObject.Properties.Name | Should -Be @(
            'schema_version',
            'metrics_source',
            'cli_version',
            'wall_time_seconds',
            'prompt_tokens',
            'cached_tokens',
            'cache_creation_tokens',
            'completion_tokens',
            'reasoning_tokens',
            'total_tokens',
            'api_calls',
            'failed_api_calls',
            'usage_api_calls',
            'ai_credits',
            'premium_requests',
            'models',
            'usage_complete',
            'malformed_records'
        )
    }

    It 'retains conflicting OTel CLI versions so integrity validation fails closed' {
        $records = @(
            [pscustomobject]@{
                type = 'span'
                name = 'invoke_agent'
                attributes = [pscustomobject]@{
                    'gen_ai.operation.name' = 'invoke_agent'
                    'gen_ai.agent.version' = '1.0.83'
                }
            },
            [pscustomobject]@{
                type = 'span'
                name = 'invoke_agent'
                attributes = [pscustomobject]@{
                    'gen_ai.operation.name' = 'invoke_agent'
                    'gen_ai.agent.version' = '1.0.88'
                }
            }
        )

        $metrics = Get-CopilotRunMetrics -Records $records

        $metrics.cli_version | Should -Be '1.0.83, 1.0.88'
    }

    It 'ignores cumulative metric snapshots to avoid double counting' {
        $records = @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 100 -OutputTokens 10 `
                -NanoAiu 100000000 -PremiumRequests 0.1),
            [pscustomobject]@{
                type = 'metric'
                name = 'gen_ai.client.token.usage'
                dataPoints = @([pscustomobject]@{ value = [pscustomobject]@{ sum = 999999 } })
            },
            [pscustomobject]@{
                type = 'metric'
                name = 'gen_ai.invoke_agent.inference_calls'
                dataPoints = @([pscustomobject]@{ value = [pscustomobject]@{ sum = 50 } })
            }
        )

        $metrics = Get-CopilotRunMetrics -Records $records

        $metrics.prompt_tokens | Should -Be 100
        $metrics.completion_tokens | Should -Be 10
        $metrics.api_calls | Should -Be 1
    }

    It 'uses null for optional fields absent from the structured source' {
        $metrics = Get-CopilotRunMetrics -Records @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 25 -OutputTokens 5)
        )

        $metrics.cached_tokens | Should -BeNullOrEmpty
        $metrics.cache_creation_tokens | Should -BeNullOrEmpty
        $metrics.reasoning_tokens | Should -BeNullOrEmpty
        $metrics.ai_credits | Should -BeNullOrEmpty
        $metrics.premium_requests | Should -BeNullOrEmpty
    }

    It 'reports incomplete usage when a failed or retried request lacks usage fields' {
        $metrics = Get-CopilotRunMetrics -Records @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 25 -OutputTokens 5 -NanoAiu 100000000),
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 0 -OutputTokens 0 -StatusCode 2 -WithoutUsage)
        )

        $metrics.api_calls | Should -Be 2
        $metrics.failed_api_calls | Should -Be 1
        $metrics.usage_api_calls | Should -Be 1
        $metrics.prompt_tokens | Should -Be 25
        $metrics.usage_complete | Should -BeFalse
        $metrics.ai_credits | Should -BeNullOrEmpty
        $metrics.premium_requests | Should -BeNullOrEmpty
    }

    It 'skips malformed structured spans while preserving valid usage' {
        $invalidAttributes = @(
            @{ Name = 'gen_ai.usage.input_tokens'; Value = 'invalid' },
            @{ Name = 'gen_ai.usage.input_tokens'; Value = '10' },
            @{ Name = 'gen_ai.usage.output_tokens'; Value = -1 },
            @{ Name = 'gen_ai.usage.cache_read.input_tokens'; Value = 1.5 },
            @{ Name = 'gen_ai.usage.cache_creation.input_tokens'; Value = 'invalid' },
            @{ Name = 'gen_ai.usage.reasoning.output_tokens'; Value = 'invalid' },
            @{ Name = 'github.copilot.nano_aiu'; Value = 'invalid' },
            @{ Name = 'github.copilot.cost'; Value = -0.5 }
        )
        $records = [System.Collections.Generic.List[object]]::new()
        $records.Add((New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 25 -OutputTokens 5 `
            -NanoAiu 100000000 -PremiumRequests 1))
        foreach ($invalid in $invalidAttributes) {
            $span = New-ChatSpan -Model 'invalid-model' -InputTokens 10 -OutputTokens 2 `
                -CachedTokens 5 -CacheCreationTokens 5 -ReasoningTokens 1 `
                -NanoAiu 100000000 -PremiumRequests 1
            $span.attributes.PSObject.Properties[$invalid.Name].Value = $invalid.Value
            $records.Add($span)
        }
        $invalidStatus = New-ChatSpan -Model 'invalid-status' -InputTokens 10 -OutputTokens 2 `
            -NanoAiu 100000000 -PremiumRequests 1
        $invalidStatus.status.code = 'invalid'
        $records.Add($invalidStatus)

        $metrics = Get-CopilotRunMetrics -Records @($records) -MalformedRecords 2

        $metrics.api_calls | Should -Be 1
        $metrics.prompt_tokens | Should -Be 25
        $metrics.completion_tokens | Should -Be 5
        $metrics.ai_credits | Should -Be 0.1
        $metrics.premium_requests | Should -Be 1
        $metrics.models | Should -Be @('gpt-5.6-sol')
        $metrics.malformed_records | Should -Be 11
    }
}

Describe 'Assert-RequestedLeafModelObserved' {
    BeforeEach {
        $ReviewOutputDir = Join-Path $TestDrive 'leaf-model-output'
        New-Item -ItemType Directory -Path $ReviewOutputDir -Force | Out-Null
        $CopilotModel = 'claude-sonnet-5'
        $LeafModel = 'gpt-5.6-luna'
        $RequireLeafModel = $true
    }

    It 'accepts the explicitly requested model when telemetry observed it' {
        @{ models = @('claude-sonnet-5', 'gpt-5.6-luna') } |
            ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-metrics.json')

        { Assert-RequestedLeafModelObserved } | Should -Not -Throw
    }

    It 'fails when the requested model was substituted' {
        @{ models = @('claude-sonnet-5', 'gemini-3.6-flash') } |
            ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-metrics.json')

        { Assert-RequestedLeafModelObserved } |
            Should -Throw "*Required leaf model 'gpt-5.6-luna' was not observed*gemini-3.6-flash*"
    }

    It 'fails when an additional model was substituted alongside the requested model' {
        @{ models = @('claude-sonnet-5', 'gemini-3.6-flash', 'gpt-5.6-luna') } |
            ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-metrics.json')

        { Assert-RequestedLeafModelObserved } |
            Should -Throw "*Expected only 'claude-sonnet-5' and 'gpt-5.6-luna'*gemini-3.6-flash*"
    }

    It 'does not enforce the model unless explicitly requested' {
        $RequireLeafModel = $false

        { Assert-RequestedLeafModelObserved } | Should -Not -Throw
    }
}

Describe 'ConvertFrom-CopilotOtelJsonLines' {
    It 'retains valid records and counts malformed structured records' {
        $valid = (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 10 -OutputTokens 2) |
            ConvertTo-Json -Depth 8 -Compress

        $parsed = ConvertFrom-CopilotOtelJsonLines -Lines @($valid, '{broken', '', 'null')

        $parsed.Records.Count | Should -Be 2
        $parsed.MalformedRecords | Should -Be 1
    }
}

Describe 'Copilot metrics artifact lifecycle' {
    It 'harvests OTel JSONL into the versioned output artifact' {
        $otelPath = Join-Path $TestDrive '_copilot-otel.jsonl'
        $outputDir = Join-Path $TestDrive 'harvest-output'
        @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 80 -OutputTokens 12 `
                -CachedTokens 30 -ReasoningTokens 3 -NanoAiu 500000000 `
                -PremiumRequests 1)
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $otelPath -Encoding UTF8

        $parsed = Read-CopilotOtelFile -OtelPath $otelPath
        $metrics = Save-CopilotRunMetrics `
            -Records $parsed.Records `
            -OutputDir $outputDir `
            -WallTimeSeconds 4.2 `
            -MalformedRecords $parsed.MalformedRecords
        $saved = Get-Content -LiteralPath (Join-Path $outputDir '_run-metrics.json') -Raw |
            ConvertFrom-Json

        $metrics.api_calls | Should -Be 1
        $saved.schema_version | Should -Be 1
        $saved.prompt_tokens | Should -Be 80
        $saved.reasoning_tokens | Should -Be 3
        $saved.ai_credits | Should -Be 0.5
        $saved.premium_requests | Should -Be 1
        $otelPath | Should -Not -Exist
        (Join-Path $outputDir '_copilot-otel.jsonl') | Should -Not -Exist
    }

    It 'retries transient raw OTel deletion failures' {
        $otelPath = Join-Path $TestDrive 'retry-delete-otel.jsonl'
        '{}' | Set-Content -LiteralPath $otelPath
        $script:removeAttempts = 0
        Mock Remove-Item {
            param($LiteralPath, $Force, $ErrorAction)
            $script:removeAttempts++
            if ($script:removeAttempts -eq 1) { throw 'file is still locked' }
            [System.IO.File]::Delete($LiteralPath)
        }
        Mock Start-Sleep {}

        Remove-CopilotOtelFile -OtelPath $otelPath -RetryDelayMilliseconds 1

        $otelPath | Should -Not -Exist
        Should -Invoke Remove-Item -Times 2
        Should -Invoke Start-Sleep -Times 1
    }

    It 'terminates and disposes the process before harvesting timeout telemetry' {
        $otelPath = Join-Path $TestDrive 'timeout-otel.jsonl'
        '{}' | Set-Content -LiteralPath $otelPath
        $events = [System.Collections.Generic.List[string]]::new()
        $fakeProcess = [pscustomobject]@{
            HasExited = $false
            Events = $events
        }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Kill -Value {
            param([bool] $EntireProcessTree)
            $this.Events.Add('kill')
        }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param([int] $Milliseconds)
            $this.Events.Add("wait:$Milliseconds")
            $this.HasExited = $true
            return $true
        }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Events.Add('dispose')
        }

        Complete-CopilotProcess `
            -Process $fakeProcess `
            -ProcessStarted $true `
            -TerminationWaitMilliseconds 25 `
            -HarvestAction {
                $events.Add('harvest')
                $null = Read-CopilotOtelFile -OtelPath $otelPath
            }

        $events | Should -Be @('kill', 'wait:25', 'dispose', 'harvest')
        $otelPath | Should -Not -Exist
    }

    It 'disposes and harvests when an exception occurs before process start' {
        $otelPath = Join-Path $TestDrive 'startup-failure-otel.jsonl'
        '{}' | Set-Content -LiteralPath $otelPath
        $events = [System.Collections.Generic.List[string]]::new()
        $fakeProcess = [pscustomobject]@{ Events = $events }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Events.Add('dispose')
        }

        Complete-CopilotProcess `
            -Process $fakeProcess `
            -ProcessStarted $false `
            -HarvestAction {
                $events.Add('harvest')
                $null = Read-CopilotOtelFile -OtelPath $otelPath
            }

        $events | Should -Be @('dispose', 'harvest')
        $otelPath | Should -Not -Exist
    }

    It 'does not replace the review failure when telemetry harvest also fails' {
        $events = [System.Collections.Generic.List[string]]::new()
        $fakeProcess = [pscustomobject]@{ Events = $events }
        $fakeProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Events.Add('dispose')
        }
        Mock Write-Warning {}

        {
            Complete-CopilotProcess `
                -Process $fakeProcess `
                -ProcessStarted $false `
                -HarvestAction { throw 'harvest failed' }
        } | Should -Not -Throw

        $events | Should -Be @('dispose')
        Should -Invoke Write-Warning -Times 1 -ParameterFilter {
            $Message -match 'Failed to harvest Copilot CLI telemetry'
        }
    }

    It 'reuses cached records after deleting the raw file and only updates wall time' {
        $script:ReviewPhase = 'all'
        $script:CopilotOtelPath = Join-Path $TestDrive 'repeated-save-otel.jsonl'
        $script:ReviewOutputDir = Join-Path $TestDrive 'repeated-save-output'
        $script:ReviewStartedAt = [DateTime]::UtcNow.AddSeconds(-2)
        $script:CopilotOtelRecords = $null
        $script:CopilotOtelMalformedRecords = 0
        @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 80 -OutputTokens 12 `
                -NanoAiu 500000000 -PremiumRequests 1)
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $script:CopilotOtelPath -Encoding UTF8

        Save-CurrentCopilotRunMetrics
        $first = Get-Content -LiteralPath (
            Join-Path $script:ReviewOutputDir '_run-metrics.json'
        ) -Raw | ConvertFrom-Json
        $script:ReviewStartedAt = [DateTime]::UtcNow.AddSeconds(-5)
        Save-CurrentCopilotRunMetrics
        $second = Get-Content -LiteralPath (
            Join-Path $script:ReviewOutputDir '_run-metrics.json'
        ) -Raw | ConvertFrom-Json

        $script:CopilotOtelPath | Should -Not -Exist
        $first.prompt_tokens | Should -Be 80
        $second.prompt_tokens | Should -Be 80
        $second.ai_credits | Should -Be 0.5
        $second.wall_time_seconds | Should -BeGreaterThan $first.wall_time_seconds
    }

    It 'adds later Copilot invocations once without recounting cached records' {
        $script:ReviewPhase = 'all'
        $script:CopilotOtelPath = Join-Path $TestDrive 'multiple-invocations-otel.jsonl'
        $script:ReviewOutputDir = Join-Path $TestDrive 'multiple-invocations-output'
        $script:ReviewStartedAt = [DateTime]::UtcNow.AddSeconds(-1)
        $script:CopilotOtelRecords = $null
        $script:CopilotOtelMalformedRecords = 0
        @(
            (New-ChatSpan -Model 'gpt-5.6-sol' -InputTokens 80 -OutputTokens 12 `
                -NanoAiu 500000000 -PremiumRequests 1)
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $script:CopilotOtelPath -Encoding UTF8
        Save-CurrentCopilotRunMetrics

        @(
            (New-ChatSpan -Model 'gpt-5.4-mini' -InputTokens 20 -OutputTokens 4 `
                -NanoAiu 250000000 -PremiumRequests 0.25)
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $script:CopilotOtelPath -Encoding UTF8
        Save-CurrentCopilotRunMetrics
        Save-CurrentCopilotRunMetrics
        $saved = Get-Content -LiteralPath (
            Join-Path $script:ReviewOutputDir '_run-metrics.json'
        ) -Raw | ConvertFrom-Json

        $saved.api_calls | Should -Be 2
        $saved.prompt_tokens | Should -Be 100
        $saved.completion_tokens | Should -Be 16
        $saved.ai_credits | Should -Be 0.75
        $saved.premium_requests | Should -Be 1.25
        $saved.models | Should -Be @('gpt-5.4-mini', 'gpt-5.6-sol')
        $script:CopilotOtelPath | Should -Not -Exist
    }

    It 'clears stale source and output metrics before a new run' {
        $agentDir = Join-Path $TestDrive 'agent'
        $outputDir = Join-Path $TestDrive 'cleanup-output'
        New-Item -ItemType Directory -Path $agentDir, $outputDir | Out-Null
        $otelPath = Join-Path $agentDir '_copilot-otel.jsonl'
        $metricsPath = Join-Path $outputDir '_run-metrics.json'
        '{}' | Set-Content -LiteralPath $otelPath
        '{}' | Set-Content -LiteralPath $metricsPath

        Clear-CopilotMetricsArtifacts -AgentWorkDir $agentDir -OutputDir $outputDir

        $otelPath | Should -Not -Exist
        $metricsPath | Should -Not -Exist
    }

    It 'removes a legacy raw OTel file from the output directory' {
        $outputDir = Join-Path $TestDrive 'legacy-output'
        New-Item -ItemType Directory -Path $outputDir | Out-Null
        $rawPath = Join-Path $outputDir '_copilot-otel.jsonl'
        '{}' | Set-Content -LiteralPath $rawPath

        Clear-CopilotMetricsArtifacts -OutputDir $outputDir

        $rawPath | Should -Not -Exist
    }

    It 'does not abort the review when a stale metrics file is locked' {
        $agentDir = Join-Path $TestDrive 'locked-agent'
        New-Item -ItemType Directory -Path $agentDir | Out-Null
        '{}' | Set-Content -LiteralPath (Join-Path $agentDir '_copilot-otel.jsonl')
        Mock Remove-Item { throw 'file is locked' }

        { Clear-CopilotMetricsArtifacts -AgentWorkDir $agentDir } | Should -Not -Throw

        Should -Invoke Remove-Item -Times 1
    }
}

Describe 'Copilot OTel wiring' {
    It 'enables the file exporter without parsing transcript prose' {
        $source = Get-Content -LiteralPath $scriptPath -Raw

        $source | Should -Match "COPILOT_OTEL_EXPORTER_TYPE'\]\s*=\s*'file'"
        $source | Should -Match "COPILOT_OTEL_FILE_EXPORTER_PATH"
        $source | Should -Match '\[System\.IO\.Path\]::GetTempPath\(\)'
        $source | Should -Not -Match 'Join-Path\s+\$AgentWorkDir\s+\$CopilotOtelFileName'
        $source | Should -Not -Match 'Get-CopilotSummaryMetrics'
        $source | Should -Not -Match 'token_prices'
    }
}
