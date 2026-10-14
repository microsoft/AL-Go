# ---------------------------------------------------------------------------
# Artifacts
# ---------------------------------------------------------------------------
function Write-FindingsBreakdown {
    <#
    Emits a per-severity and knowledge-backed-vs-agent breakdown plus a
    per-domain pre-post finding count. Called inside the Parse & filter
    phase so the follower sees what is about to be posted.
    #>
    param([object[]] $Findings)

    $sev = [ordered]@{ Critical = 0; High = 0; Medium = 0; Low = 0 }
    $domains = Get-OrdinalDictionary
    $backed = 0
    $agent  = 0
    foreach ($f in @($Findings)) {
        if ($null -eq $f) { continue }
        if ($sev.Contains($f.severity)) { $sev[$f.severity] = $sev[$f.severity] + 1 }
        if ($f.isAgentFinding) { $agent++ } else { $backed++ }
        $d = if ($f.domain) { [string]$f.domain } else { 'Other' }
        if (-not $domains.ContainsKey($d)) { $domains[$d] = 0 }
        $domains[$d] = $domains[$d] + 1
    }

    $sevLine = ($sev.Keys | ForEach-Object { "$($_): $($sev[$_])" }) -join '  '
    Write-LogPhaseDetail "By severity: $sevLine"
    Write-LogPhaseDetail "By origin:   knowledge-backed: $backed  agent: $agent"
    if ($domains.Count -gt 0) {
        $domainLine = (Get-OrdinalSortedKey -Dictionary $domains |
            ForEach-Object { "$($_): $($domains[$_])" }) -join '  '
        Write-LogPhaseDetail "By domain:   $domainLine"
    }
}

function Publish-FindingsByDomain {
    param(
        [object[]] $Findings,
        [hashtable] $LineMaps,
        [hashtable] $ChangedFileSet
    )

    $findingsByDomain = Get-OrdinalDictionary
    foreach ($finding in $Findings) {
        $domain = [string]$finding.domain
        if (-not $findingsByDomain.ContainsKey($domain)) {
            $findingsByDomain[$domain] = [System.Collections.Generic.List[object]]::new()
        }
        $findingsByDomain[$domain].Add($finding) | Out-Null
    }

    $domainSummary = Get-OrdinalDictionary
    foreach ($domain in (Get-OrdinalSortedKey -Dictionary $findingsByDomain)) {
        $domainFindings = @($findingsByDomain[$domain])
        Write-Host "Posting $($domainFindings.Count) $domain finding(s)…"
        $posted = Publish-Findings -Domain $domain -Findings $domainFindings `
            -LineMaps $LineMaps -ChangedFileSet $ChangedFileSet
        $agentCount = @($domainFindings | Where-Object { $_.isAgentFinding }).Count
        $backedCount = $domainFindings.Count - $agentCount
        Write-LogPhaseDetail "inline: $($posted.inline)  fallback: $($posted.fallback)  knowledge-backed: $backedCount  agent: $agentCount"
        $domainSummary[$domain] = @{
            findings        = $domainFindings.Count
            inline          = $posted.inline
            fallback        = $posted.fallback
            knowledgeBacked = $backedCount
            agentFindings   = $agentCount
        }
    }

    return $domainSummary
}

function Test-MechanicalLookingFinding {
    <#
    Best-effort heuristic for diagnostics only. The BCQuality contract now
    expects suggested-code for small, local, mechanical fixes; this helper
    identifies findings that look mechanical so CI logs can flag missing
    suggestions or missing omission reasons. It does not affect posting.
    #>
    param([object] $Finding)

    if ($null -eq $Finding) { return $false }
    $text = @(
        [string]$Finding.rawId,
        [string]$Finding.issue,
        [string]$Finding.recommendation,
        [string]$Finding.domain
    ) -join ' '

    $mechanicalPatterns = @(
        'Count\(\)\s*(?:>|=)',
        '\bIsEmpty\(\)',
        '\bCommit\(\)',
        '\bSetLoadFields\b',
        '\bTextBuilder\b',
        '\bToolTip\b',
        '\bOptionCaption\b',
        '\bDataClassification\b',
        '\bToBeClassified\b',
        '\bLabel\b',
        '\bError\(',
        '\bSession\.LogMessage\b',
        '\b0000\b',
        '\bplaceholder event ID\b',
        '\bPermissions?\b',
        '\brimd\b',
        '\bRIMD\b',
        '\bunreachable\b',
        '\bdead code\b',
        '\buppercase reserved\b',
        '\bspaces? before\b',
        '\belse\b',
        '\bguard branch\b',
        '\bUpgradeTag\b'
    )

    foreach ($pattern in $mechanicalPatterns) {
        if ($text -match $pattern) { return $true }
    }
    return $false
}

function Write-SuggestedCodeDiagnostics {
    param([object[]] $Findings)

    $mechanical = @()
    foreach ($f in @($Findings)) {
        if (Test-MechanicalLookingFinding -Finding $f) { $mechanical += $f }
    }
    if ($mechanical.Count -eq 0) {
        Write-LogPhaseDetail 'Suggested-code diagnostics: no mechanical-looking findings detected.'
        return
    }

    $withSuggestion = @($mechanical | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.suggestedCode) })
    $withReason = @($mechanical | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.suggestedCode) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.suggestedCodeOmissionReason)
    })
    $withoutEither = @($mechanical | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.suggestedCode) -and
        [string]::IsNullOrWhiteSpace([string]$_.suggestedCodeOmissionReason)
    })

    Write-LogPhaseDetail "Suggested-code diagnostics: mechanical-looking=$($mechanical.Count) with-suggestion=$($withSuggestion.Count) omission-reason=$($withReason.Count) missing-both=$($withoutEither.Count)"
    if ($withoutEither.Count -gt 0) {
        $examples = @($withoutEither | Select-Object -First 5 | ForEach-Object {
            $label = if ($_.rawId) { [string]$_.rawId } elseif ($_.issue) { [string]$_.issue } else { '(unknown finding)' }
            if ($label.Length -gt 120) { $label = $label.Substring(0, 117) + '...' }
            $label
        })
        Write-LogWarn 'Mechanical findings missing suggested-code' "Detected $($withoutEither.Count) mechanical-looking finding(s) without suggested-code and without suggested-code-omission-reason. Examples: $($examples -join ' || ')"
    }
}

function Save-ReviewArtifacts {
    param(
        [string] $RawOutput,
        [object] $Report,
        [string[]] $ParseErrors,
        [object] $TaskContext,
        [string] $Transcript
    )

    New-Item -Path $ReviewOutputDir -ItemType Directory -Force | Out-Null

    $savedFiles = [System.Collections.Generic.List[string]]::new()

    $rawPath = Join-Path $ReviewOutputDir 'al-code-review-raw.txt'
    Set-Content -Path $rawPath -Value $RawOutput -Encoding UTF8
    $savedFiles.Add('al-code-review-raw.txt') | Out-Null

    $taskPath = Join-Path $ReviewOutputDir 'task-context.json'
    Set-Content -Path $taskPath -Value ($TaskContext | ConvertTo-Json -Depth 10) -Encoding UTF8
    $savedFiles.Add('task-context.json') | Out-Null

    $payload = @{
        repository    = $Repository
        prNumber      = $PrNumber
        baseBranch    = $BaseBranch
        headSha       = $PrHeadSha
        bcqualityVersion = $BCQualityVersion
        agentLabel    = $AgentLabel
        agentVersion  = $AgentVersion
        outcome       = $Report.Outcome
        outcomeReason = $Report.OutcomeReason
        findings      = @($Report.Findings)
        suppressed    = $Report.Suppressed
        subResults    = @($Report.SubResults)
        skippedSubSkills = $Report.SkippedSubSkills
        parseErrors   = @($ParseErrors)
    }
    $findingsPath = Join-Path $ReviewOutputDir 'al-code-review-findings.json'
    Set-Content -Path $findingsPath -Value ($payload | ConvertTo-Json -Depth 12) -Encoding UTF8
    $savedFiles.Add('al-code-review-findings.json') | Out-Null

    if ($Transcript) {
        $transcriptPath = Join-Path $ReviewOutputDir 'agent-transcript.log'
        Set-Content -Path $transcriptPath -Value $Transcript -Encoding UTF8
        $savedFiles.Add('agent-transcript.log') | Out-Null
    }
    if (Test-Path -LiteralPath (Join-Path $ReviewOutputDir '_run-metrics.json') -PathType Leaf) {
        $savedFiles.Add('_run-metrics.json') | Out-Null
    }
    if (Test-Path -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -PathType Leaf) {
        $savedFiles.Add('_run-manifest.json') | Out-Null
    }

    Write-Host "Saved review artifacts to $ReviewOutputDir"
    foreach ($f in $savedFiles) { Write-LogPhaseDetail "- $f" }
}
