# ---------------------------------------------------------------------------
# BCQuality task-context (passed verbatim to entry.md)
# ---------------------------------------------------------------------------
$script:BCQualitySettingsCache = $null
function Get-BCQualitySettingsCached {
    if ($null -eq $script:BCQualitySettingsCache) {
        if ([string]::IsNullOrWhiteSpace($env:BCQUALITY_SETTINGS_JSON)) {
            throw 'BCQUALITY_SETTINGS_JSON is required.'
        }
        try {
            $script:BCQualitySettingsCache = $env:BCQUALITY_SETTINGS_JSON |
                ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            throw "BCQUALITY_SETTINGS_JSON is invalid: $($_.Exception.Message)"
        }
    }
    return $script:BCQualitySettingsCache
}

function Build-TaskContext {
    $settings = Get-BCQualitySettingsCached

    $context = [ordered]@{
        goal               = 'review pull request'
        'inputs-available' = @('pr-diff', 'file-path', 'repository')
        'enabled-layers'   = @($settings.enabledLayers)
        'disabled-skills'  = @($settings.disabledSkills)
        technologies       = @('al')
        countries          = @('w1')
        'application-area' = @('all')
    }

    return $context
}

function Save-TaskContext {
    param([object] $TaskContext)

    $path = Join-Path $AgentWorkDir '_task-context.json'
    $json = $TaskContext | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    Write-Host "Task context written to $path"
    return $path
}

function Clear-BCQualityRunArtifacts {
    # BCQualityRoot is the nested agent's working directory. Per-run artifacts
    # are written into the installed plugin and can survive when the engine is
    # invoked more than once in the same job. Two concrete hazards this clears:
    #   1. A stale `_review-report.json` would be harvested as THIS run's
    #      findings if the agent fails to write a fresh one (silent wrong
    #      result).
    #   2. Stale `_review-changed-files.txt` / `_review-object-index.txt` from a
    #      prior changeset can mislead the agent about what changed when its
    #      primary diff access is degraded.
    # Removing them before the run guarantees the agent and the harvester only
    # ever see artifacts produced by the current run.
    if (-not $AgentWorkDir -or -not (Test-Path -LiteralPath $AgentWorkDir)) { return }

    # NOTE: _filter-report.json is deliberately NOT cleared here. It is produced
    # by the upstream BCQuality filter step (before this engine runs) and is
    # harvested into the output dir AFTER the agent run - clearing it would
    # delete a live input of the current run.
    $stalePatterns = @(
        '_task-context.json',
        '_review-report.json',
        '_review-changed-files.txt',
        '_review-object-index.txt',
        '_run-metrics.json',
        '_copilot-otel.jsonl',
        '_review-*'
    )

    $removed = 0
    foreach ($pattern in $stalePatterns) {
        foreach ($file in (Get-ChildItem -LiteralPath $AgentWorkDir -File -Filter $pattern -ErrorAction SilentlyContinue)) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removed++
            } catch {
                Write-Warning "Could not remove stale artifact '$($file.FullName)': $($_.Exception.Message)"
            }
        }
    }

    if ($removed -gt 0) {
        Write-Host "Cleared $removed stale review artifact(s) from $AgentWorkDir"
    }
}

function Get-ObjectPropertyValue {
    param(
        [object] $InputObject,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function ConvertFrom-CopilotOtelJsonLines {
    param([string[]] $Lines = @())

    $records = [System.Collections.Generic.List[object]]::new()
    $malformedRecords = 0
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $records.Add(($line | ConvertFrom-Json -Depth 100 -ErrorAction Stop)) | Out-Null
        }
        catch {
            $malformedRecords++
        }
    }

    return [pscustomobject]@{
        Records          = @($records)
        MalformedRecords = $malformedRecords
    }
}

function Test-CopilotNumericValue {
    param([Parameter(Mandatory)][object] $Value)

    $numericTypeCodes = @(
        [System.TypeCode]::Byte,
        [System.TypeCode]::SByte,
        [System.TypeCode]::Int16,
        [System.TypeCode]::UInt16,
        [System.TypeCode]::Int32,
        [System.TypeCode]::UInt32,
        [System.TypeCode]::Int64,
        [System.TypeCode]::UInt64,
        [System.TypeCode]::Single,
        [System.TypeCode]::Double,
        [System.TypeCode]::Decimal
    )
    return [System.Type]::GetTypeCode($Value.GetType()) -in $numericTypeCodes
}

function ConvertTo-CopilotNonNegativeInt64 {
    param(
        [Parameter(Mandatory)][object] $Value,
        [Parameter(Mandatory)][string] $AttributeName
    )

    if (-not (Test-CopilotNumericValue -Value $Value)) {
        throw "Copilot OTel attribute '$AttributeName' must be a numeric JSON value."
    }

    $parsed = 0L
    $text = [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    if (
        -not [int64]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        ) -or
        $parsed -lt 0
    ) {
        throw "Copilot OTel attribute '$AttributeName' must be a non-negative integer."
    }
    return $parsed
}

function ConvertTo-CopilotNonNegativeDecimal {
    param(
        [Parameter(Mandatory)][object] $Value,
        [Parameter(Mandatory)][string] $AttributeName
    )

    if (-not (Test-CopilotNumericValue -Value $Value)) {
        throw "Copilot OTel attribute '$AttributeName' must be a numeric JSON value."
    }

    $parsed = [decimal]0
    $text = [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    if (
        -not [decimal]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        ) -or
        $parsed -lt 0
    ) {
        throw "Copilot OTel attribute '$AttributeName' must be a non-negative number."
    }
    return $parsed
}

function Get-CopilotNumericAttribute {
    param(
        [object] $InputObject,
        [Parameter(Mandatory)][string] $Name,
        [ValidateSet('Integer', 'Decimal')][string] $Kind = 'Integer',
        [string] $DisplayName = $Name
    )

    $value = Get-ObjectPropertyValue -InputObject $InputObject -Name $Name
    if ($null -eq $value) { return $null }
    if ($Kind -eq 'Decimal') {
        return ConvertTo-CopilotNonNegativeDecimal -Value $value -AttributeName $DisplayName
    }
    return ConvertTo-CopilotNonNegativeInt64 -Value $value -AttributeName $DisplayName
}

function Get-CopilotRunMetrics {
    param(
        [object[]] $Records = @(),
        [object] $WallTimeSeconds = $null,
        [int] $MalformedRecords = 0
    )

    $apiCalls = 0
    $failedApiCalls = 0
    $usageApiCalls = 0
    $inputTokens = 0L
    $outputTokens = 0L
    $cachedTokens = 0L
    $cacheCreationTokens = 0L
    $reasoningTokens = 0L
    $nanoAiu = [decimal]0
    $premiumRequests = [decimal]0
    $hasCachedTokens = $false
    $hasCacheCreationTokens = $false
    $hasReasoningTokens = $false
    $nanoAiuApiCalls = 0
    $premiumRequestApiCalls = 0
    $invalidStructuredRecords = 0
    $models = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $cliVersions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $hasEmptyCliVersion = $false

    foreach ($record in @($Records)) {
        if ((Get-ObjectPropertyValue -InputObject $record -Name 'type') -ne 'span') { continue }
        $attributes = Get-ObjectPropertyValue -InputObject $record -Name 'attributes'
        $operation = [string](Get-ObjectPropertyValue -InputObject $attributes -Name 'gen_ai.operation.name')

        if ($operation -eq 'invoke_agent') {
            $rawVersion = Get-ObjectPropertyValue -InputObject $attributes -Name 'gen_ai.agent.version'
            if ($null -ne $rawVersion) {
                $version = ([string]$rawVersion).Trim()
                if ($version) {
                    [void]$cliVersions.Add($version)
                }
                else {
                    $hasEmptyCliVersion = $true
                }
            }
            continue
        }
        if ($operation -ne 'chat') { continue }

        try {
            $status = Get-ObjectPropertyValue -InputObject $record -Name 'status'
            $statusCode = Get-CopilotNumericAttribute `
                -InputObject $status `
                -Name 'code' `
                -DisplayName 'status.code'
            if ($null -ne $statusCode -and $statusCode -gt 2) {
                throw "Copilot OTel attribute 'status.code' must be 0, 1, or 2."
            }

            $parsedInput = Get-CopilotNumericAttribute -InputObject $attributes -Name 'gen_ai.usage.input_tokens'
            $parsedOutput = Get-CopilotNumericAttribute -InputObject $attributes -Name 'gen_ai.usage.output_tokens'
            $parsedCached = Get-CopilotNumericAttribute -InputObject $attributes -Name 'gen_ai.usage.cache_read.input_tokens'
            $parsedCacheCreation = Get-CopilotNumericAttribute -InputObject $attributes -Name 'gen_ai.usage.cache_creation.input_tokens'
            $parsedReasoning = Get-CopilotNumericAttribute -InputObject $attributes -Name 'gen_ai.usage.reasoning.output_tokens'
            $parsedNanoAiu = Get-CopilotNumericAttribute `
                -InputObject $attributes `
                -Name 'github.copilot.nano_aiu' `
                -Kind 'Decimal'
            $parsedPremiumRequests = Get-CopilotNumericAttribute `
                -InputObject $attributes `
                -Name 'github.copilot.cost' `
                -Kind 'Decimal'
        }
        catch {
            $invalidStructuredRecords++
            continue
        }

        $apiCalls++
        if ($statusCode -eq 2) { $failedApiCalls++ }
        $model = [string](Get-ObjectPropertyValue -InputObject $attributes -Name 'gen_ai.response.model')
        if (-not $model) {
            $model = [string](Get-ObjectPropertyValue -InputObject $attributes -Name 'gen_ai.request.model')
        }
        if ($model) { [void]$models.Add($model) }

        if ($null -ne $parsedInput -and $null -ne $parsedOutput) {
            $inputTokens += $parsedInput
            $outputTokens += $parsedOutput
            $usageApiCalls++
        }
        if ($null -ne $parsedCached) {
            $cachedTokens += $parsedCached
            $hasCachedTokens = $true
        }
        if ($null -ne $parsedCacheCreation) {
            $cacheCreationTokens += $parsedCacheCreation
            $hasCacheCreationTokens = $true
        }
        if ($null -ne $parsedReasoning) {
            $reasoningTokens += $parsedReasoning
            $hasReasoningTokens = $true
        }
        if ($null -ne $parsedNanoAiu) {
            $nanoAiu += $parsedNanoAiu
            $nanoAiuApiCalls++
        }
        if ($null -ne $parsedPremiumRequests) {
            $premiumRequests += $parsedPremiumRequests
            $premiumRequestApiCalls++
        }
    }

    $hasApiSpans = $apiCalls -gt 0
    $usageComplete = $hasApiSpans -and $usageApiCalls -eq $apiCalls
    $roundedWallTime = if ($null -eq $WallTimeSeconds) { $null } else { [math]::Round([double]$WallTimeSeconds, 3) }
    return [pscustomobject][ordered]@{
        schema_version        = 1
        metrics_source        = 'copilot-cli-otel'
        cli_version           = if ($hasEmptyCliVersion) {
            '(empty)'
        } elseif ($cliVersions.Count -eq 1) {
            [string]@($cliVersions)[0]
        } elseif ($cliVersions.Count -gt 1) {
            (@($cliVersions | Sort-Object) -join ', ')
        } else {
            $null
        }
        wall_time_seconds     = $roundedWallTime
        prompt_tokens         = if ($usageApiCalls -gt 0) { $inputTokens } else { $null }
        cached_tokens         = if ($hasCachedTokens) { $cachedTokens } else { $null }
        cache_creation_tokens = if ($hasCacheCreationTokens) { $cacheCreationTokens } else { $null }
        completion_tokens     = if ($usageApiCalls -gt 0) { $outputTokens } else { $null }
        reasoning_tokens      = if ($hasReasoningTokens) { $reasoningTokens } else { $null }
        total_tokens          = if ($usageApiCalls -gt 0) { $inputTokens + $outputTokens } else { $null }
        api_calls             = if ($hasApiSpans) { $apiCalls } else { $null }
        failed_api_calls      = if ($hasApiSpans) { $failedApiCalls } else { $null }
        usage_api_calls       = if ($hasApiSpans) { $usageApiCalls } else { $null }
        ai_credits            = if ($hasApiSpans -and $nanoAiuApiCalls -eq $apiCalls) {
            [math]::Round(($nanoAiu / [decimal]1000000000), 9)
        } else {
            $null
        }
        premium_requests      = if ($hasApiSpans -and $premiumRequestApiCalls -eq $apiCalls) {
            [math]::Round($premiumRequests, 9)
        } else {
            $null
        }
        models                = @($models | Sort-Object)
        usage_complete        = $usageComplete
        malformed_records     = $MalformedRecords + $invalidStructuredRecords
    }
}

function Remove-CopilotOtelFile {
    param(
        [Parameter(Mandatory)][string] $OtelPath,
        [int] $MaxAttempts = 5,
        [int] $RetryDelayMilliseconds = 100
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (-not (Test-Path -LiteralPath $OtelPath -PathType Leaf)) { return }
        try {
            Remove-Item -LiteralPath $OtelPath -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Start-Sleep -Milliseconds $RetryDelayMilliseconds
        }
    }
}

function Read-CopilotOtelFile {
    param([Parameter(Mandatory)][string] $OtelPath)

    try {
        $lines = if (Test-Path -LiteralPath $OtelPath -PathType Leaf) {
            @(Get-Content -LiteralPath $OtelPath -ErrorAction Stop)
        } else {
            @()
        }
        return ConvertFrom-CopilotOtelJsonLines -Lines $lines
    }
    finally {
        Remove-CopilotOtelFile -OtelPath $OtelPath
    }
}

function Save-CopilotRunMetrics {
    param(
        [object[]] $Records = @(),
        [Parameter(Mandatory)][string] $OutputDir,
        [object] $WallTimeSeconds = $null,
        [int] $MalformedRecords = 0
    )

    $metrics = Get-CopilotRunMetrics `
        -Records $Records `
        -WallTimeSeconds $WallTimeSeconds `
        -MalformedRecords $MalformedRecords

    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $metricsPath = Join-Path $OutputDir '_run-metrics.json'
    Set-Content -LiteralPath $metricsPath -Value ($metrics | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $metrics
}

function Assert-RequestedLeafModelObserved {
    if (-not $RequireLeafModel) { return }

    $metricsPath = Join-Path $ReviewOutputDir '_run-metrics.json'
    if (-not (Test-Path -LiteralPath $metricsPath -PathType Leaf)) {
        throw "Required leaf model '$LeafModel' could not be verified because '$metricsPath' was not produced."
    }

    try {
        $metrics = Get-Content -LiteralPath $metricsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Required leaf model '$LeafModel' could not be verified because '$metricsPath' is unreadable: $($_.Exception.Message)"
    }

    $observedModels = @($metrics.models | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($LeafModel -notin $observedModels) {
        $observed = if ($observedModels.Count -gt 0) { $observedModels -join ', ' } else { '(none)' }
        throw "Required leaf model '$LeafModel' was not observed in Copilot telemetry. Observed models: $observed."
    }

    $unexpectedModels = @($observedModels | Where-Object { $_ -notin @($CopilotModel, $LeafModel) })
    if ($unexpectedModels.Count -gt 0) {
        throw "Unexpected model substitution was observed in Copilot telemetry. Expected only '$CopilotModel' and '$LeafModel'; observed: $($observedModels -join ', ')."
    }

    Write-LogPhaseDetail "Verified required leaf model '$LeafModel' in Copilot telemetry."
}

function Save-CurrentCopilotRunMetrics {
    if ($ReviewPhase -eq 'post') { return }

    try {
        if (Test-Path -LiteralPath $CopilotOtelPath -PathType Leaf) {
            $parsed = Read-CopilotOtelFile -OtelPath $CopilotOtelPath
            $existingRecords = if ($null -eq $script:CopilotOtelRecords) {
                @()
            } else {
                @($script:CopilotOtelRecords)
            }
            $script:CopilotOtelRecords = @($existingRecords) + @($parsed.Records)
            $script:CopilotOtelMalformedRecords += $parsed.MalformedRecords
            $invocationElapsed = if ($null -ne $script:CurrentCopilotInvocationStartedAt) {
                ([DateTime]::UtcNow - $script:CurrentCopilotInvocationStartedAt).TotalSeconds
            } else {
                $null
            }
            $script:LastCopilotInvocationMetrics = Get-CopilotRunMetrics `
                -Records $parsed.Records `
                -WallTimeSeconds $invocationElapsed `
                -MalformedRecords $parsed.MalformedRecords
            if ($parsed.MalformedRecords -gt 0) {
                Write-Warning "Ignored $($parsed.MalformedRecords) malformed Copilot OTel record(s)."
            }
        } elseif ($null -eq $script:CopilotOtelRecords) {
            $script:CopilotOtelRecords = @()
        }
        $elapsedSeconds = ([DateTime]::UtcNow - $ReviewStartedAt).TotalSeconds
        $null = Save-CopilotRunMetrics `
            -Records $script:CopilotOtelRecords `
            -OutputDir $ReviewOutputDir `
            -WallTimeSeconds $elapsedSeconds `
            -MalformedRecords $script:CopilotOtelMalformedRecords
    }
    catch {
        Write-Warning "Could not save Copilot run metrics: $($_.Exception.Message)"
    }
}

function Complete-CopilotProcess {
    param(
        [object] $Process,
        [bool] $ProcessStarted,
        [Parameter(Mandatory)][scriptblock] $HarvestAction,
        [int] $TerminationWaitMilliseconds = 10000
    )

    try {
        if ($Process -and $ProcessStarted -and -not $Process.HasExited) {
            try {
                $Process.Kill($true)
            }
            catch {
                try {
                    if (-not $Process.HasExited) { $Process.Kill() }
                }
                catch {
                    Write-Warning "Failed to terminate Copilot CLI process: $($_.Exception.Message)"
                }
            }

            try {
                if (-not $Process.WaitForExit($TerminationWaitMilliseconds)) {
                    Write-Warning "Copilot CLI did not terminate within $TerminationWaitMilliseconds ms after kill."
                }
            }
            catch {
                Write-Warning "Failed while waiting for Copilot CLI termination: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Failed during Copilot CLI process cleanup: $($_.Exception.Message)"
    }
    finally {
        if ($Process) {
            try { $Process.Dispose() }
            catch { Write-Warning "Failed to dispose Copilot CLI process: $($_.Exception.Message)" }
        }
        try { & $HarvestAction }
        catch { Write-Warning "Failed to harvest Copilot CLI telemetry: $($_.Exception.Message)" }
    }
}

function Clear-CopilotMetricsArtifacts {
    param(
        [string] $AgentWorkDir,
        [string] $OutputDir,
        [string] $OtelPath
    )

    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($OtelPath) { [void]$paths.Add($OtelPath) }
    if ($AgentWorkDir) { [void]$paths.Add((Join-Path $AgentWorkDir '_copilot-otel.jsonl')) }
    if ($OutputDir) {
        [void]$paths.Add((Join-Path $OutputDir '_run-metrics.json'))
        [void]$paths.Add((Join-Path $OutputDir '_run-manifest.json'))
        [void]$paths.Add((Join-Path $OutputDir '_copilot-otel.jsonl'))
    }
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not remove stale metrics artifact '$path': $($_.Exception.Message)"
            }
        }
    }
}
