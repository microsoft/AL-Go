# ---------------------------------------------------------------------------
# Parse BCQuality findings-report (DO output contract)
# ---------------------------------------------------------------------------
function Convert-BCQualitySeverity {
    param([string] $Severity)
    if (-not $Severity) { return $null }
    $lower = $Severity.Trim().ToLowerInvariant()
    if ($BCQualitySeverityMap.ContainsKey($lower)) { return $BCQualitySeverityMap[$lower] }
    # Be lenient: if the agent returned a capitalized legacy label, accept it.
    if ($SeverityOrder.ContainsKey($Severity)) { return $Severity }
    return $null
}

function Get-ExplicitFindingDomain {
    param([object] $Finding)

    if (-not $Finding -or -not $Finding.PSObject) { return $null }

    # Prefer the contract's lowercase spelling, while accepting objects created
    # by case-preserving PowerShell callers that expose Domain instead.
    foreach ($propertyName in @('domain', 'Domain')) {
        $property = $Finding.PSObject.Properties |
            Where-Object { $_.Name -ceq $propertyName } |
            Select-Object -First 1
        if ($property -and $null -ne $property.Value) {
            $label = ([string]$property.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($label)) { return $label }
        }
    }
    return $null
}

function Resolve-FindingDomain {
    param([object] $Finding)

    $explicitDomain = Get-ExplicitFindingDomain -Finding $Finding
    if ($explicitDomain) { return $explicitDomain }

    $fromSub = $null
    if ($Finding -and $Finding.PSObject -and $Finding.PSObject.Properties.Match('from-sub-skill').Count -gt 0) {
        $fromSub = [string]$Finding.'from-sub-skill'
    } elseif ($Finding -and $Finding.PSObject -and $Finding.PSObject.Properties.Match('from_sub_skill').Count -gt 0) {
        $fromSub = [string]$Finding.from_sub_skill
    }
    $fromSub = ($fromSub ?? '').Trim()
    if ($fromSub -and $DomainMap.ContainsKey($fromSub)) { return $DomainMap[$fromSub] }
    return 'Other'
}

function Get-OrdinalDictionary {
    return [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
}

function Get-OrdinalSortedKey {
    param([System.Collections.IDictionary] $Dictionary)

    [string[]]$keys = @($Dictionary.Keys)
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    return $keys
}

function Find-BalancedJsonCandidates {
    <#
    Extracts substrings that look like balanced JSON objects/arrays from a
    blob of mixed text. Walks the string scanning for '{' or '['; when one
    is found, advances character-by-character honouring string literals
    (including escaped quotes) until the matching closing brace is reached,
    then yields that substring and resumes scanning after it. Yields
    candidates largest-first so the most complete document is tried first.
    #>
    param([string] $Text)
    if (-not $Text) { return @() }

    $results = [System.Collections.Generic.List[string]]::new()
    $len = $Text.Length
    $i = 0
    while ($i -lt $len) {
        $c = $Text[$i]
        if ($c -eq '{' -or $c -eq '[') {
            $open = $c
            $close = if ($c -eq '{') { '}' } else { ']' }
            $depth = 0
            $inString = $false
            $escape = $false
            $end = -1
            for ($j = $i; $j -lt $len; $j++) {
                $ch = $Text[$j]
                if ($inString) {
                    if ($escape) { $escape = $false; continue }
                    if ($ch -eq '\') { $escape = $true; continue }
                    if ($ch -eq '"') { $inString = $false }
                    continue
                }
                if ($ch -eq '"') { $inString = $true; continue }
                if ($ch -eq $open) { $depth++; continue }
                if ($ch -eq $close) {
                    $depth--
                    if ($depth -eq 0) { $end = $j; break }
                }
            }
            if ($end -gt $i) {
                $results.Add($Text.Substring($i, $end - $i + 1)) | Out-Null
                $i = $end + 1
                continue
            }
        }
        $i++
    }

    return $results | Sort-Object -Property Length -Descending
}

function Repair-InterruptedAgentJson {
    <#
    Repairs Copilot CLI stdout when the agent's response is sliced by a
    "Placeholder to satisfy parallel tool requirement" TUI block. The CLI
    sometimes injects this marker mid-stream (mid-string in the model's
    fenced JSON output) to satisfy its parallel-tool-call requirement; the
    model then re-opens a fresh ```json fence after the placeholder and
    re-emits the truncated line in full. We discard the broken pre-marker
    partial line and splice the post-fence resumption in its place, which
    naturally de-duplicates because the re-emission re-includes the
    truncated field from its start.

    The marker wording is matched with a tolerant regex because the CLI's TUI
    text drifts between releases (observed variants: "parallel tool
    requirement" and "parallel tool call requirement (shell)"). Matching the
    literal string broke silently when the wording changed, leaving the
    interrupted JSON unrepaired and producing zero findings.
    #>
    param([string] $Output)
    if (-not $Output) { return $Output }

    $result   = $Output
    $markerRe = [regex]::new('[^\r\n]*Placeholder to satisfy parallel tool(?: call)? requirement(?:\s*\([^)\r\n]*\))?')
    $fenceRe  = [regex]::new('```(?:json)?\s*\r?\n')

    while ($true) {
        $mMatch = $markerRe.Match($result)
        if (-not $mMatch.Success) { break }
        $mIdx = $mMatch.Index

        $preTrim  = $result.Substring(0, $mIdx).TrimEnd()
        $nlIdx    = $preTrim.LastIndexOf("`n")
        $rollback = if ($nlIdx -lt 0) { 0 } else { $nlIdx + 1 }

        $afterMarker = $mMatch.Index + $mMatch.Length
        $fenceMatch  = $fenceRe.Match($result, $afterMarker)
        $resumeIdx   = -1
        if ($fenceMatch.Success -and ($fenceMatch.Index - $afterMarker) -lt 4000) {
            $resumeIdx = $fenceMatch.Index + $fenceMatch.Length
        } else {
            $blank = $result.IndexOf("`n`n", $afterMarker)
            if ($blank -lt 0) { break }   # cannot repair; bail out to avoid infinite loop
            $resumeIdx = $blank + 2
        }

        $result = $result.Substring(0, $rollback) + $result.Substring($resumeIdx)
    }

    return $result
}

function Remove-StructuralFences {
    <#
    Removes stray markdown code-fence lines (``` optionally followed by a
    language tag such as 'json') that the Copilot CLI splices INTO the JSON
    body when its output stream is interrupted mid-emission and resumes by
    re-opening a fresh ```json fence. Unlike Repair-InterruptedAgentJson, this
    handles the shape with NO "Placeholder" marker: the agent simply emits a
    bare ```json line in the middle of the findings-report (e.g. right after a
    sub-result's `summary` object), which leaves the balanced-brace candidate
    structurally complete but syntactically invalid ("Invalid property
    identifier character: `").

    The scan honours JSON string state (quote + backslash escape), so backticks
    inside string values (e.g. a `suggestedCode` field containing a ```al code
    sample) are preserved verbatim. Only a fence that occupies a whole line by
    itself OUTSIDE a string literal is removed; its trailing newline is kept as
    harmless whitespace. This is intentionally conservative so a structurally
    valid candidate is never turned into a different valid document.
    #>
    param([string] $Text)
    if (-not $Text) { return $Text }

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $len = $Text.Length
    $i = 0
    $inString = $false
    $escape = $false
    $lineStartWhitespaceOnly = $true

    while ($i -lt $len) {
        $ch = $Text[$i]
        if ($inString) {
            [void]$sb.Append($ch)
            if ($escape) { $escape = $false }
            elseif ($ch -eq '\') { $escape = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }
        if ($ch -eq '"') { $inString = $true; $lineStartWhitespaceOnly = $false; [void]$sb.Append($ch); $i++; continue }
        if ($ch -eq "`n") { [void]$sb.Append($ch); $lineStartWhitespaceOnly = $true; $i++; continue }
        if ($ch -eq '`' -and $lineStartWhitespaceOnly -and ($i + 2) -lt $len -and $Text[$i + 1] -eq '`' -and $Text[$i + 2] -eq '`') {
            # Confirm the rest of the line is only an optional language tag and
            # whitespace; only then is this a stray fence line we should drop.
            $k = $i + 3
            while ($k -lt $len -and $Text[$k] -ne "`n" -and ($Text[$k] -eq ' ' -or $Text[$k] -eq "`r" -or $Text[$k] -eq "`t" -or [char]::IsLetterOrDigit($Text[$k]))) { $k++ }
            if ($k -ge $len -or $Text[$k] -eq "`n") { $i = $k; continue }
        }
        if ($ch -ne ' ' -and $ch -ne "`t" -and $ch -ne "`r") { $lineStartWhitespaceOnly = $false }
        [void]$sb.Append($ch)
        $i++
    }

    return $sb.ToString()
}

function Repair-ResumeFenceJson {
    # The agent sometimes cuts off mid-value and restarts the line after a stray
    # ```json fence, like:
    #     "suggested-code": "    ODataKey        <- string never closed
    #     ```json
    #     "suggested-code": "    ODataKey = SystemId;"   <- same field, retried
    # The unclosed string breaks the whole report. This drops the fence and the
    # broken half, keeping the retried line.
    param([string] $Output)
    if (-not $Output) { return $Output }

    # An odd number of unescaped quotes means the string was never closed.
    $unescapedQuoteCount = {
        param([string] $s)
        $n = 0; $esc = $false
        foreach ($c in $s.ToCharArray()) {
            if ($esc) { $esc = $false; continue }
            if ($c -eq '\') { $esc = $true; continue }
            if ($c -eq '"') { $n++ }
        }
        return $n
    }

    $result = $Output
    $maxPasses = 50
    for ($pass = 0; $pass -lt $maxPasses; $pass++) {
        $lines = $result -split "`n"
        $repaired = $false

        for ($li = 0; $li -lt $lines.Count; $li++) {
            if (($lines[$li].Trim()) -notmatch '^```[A-Za-z0-9]*$') { continue }

            # The line before the fence must be a property whose string is still open.
            $p = $li - 1
            while ($p -ge 0 -and $lines[$p].Trim().Length -eq 0) { $p-- }
            if ($p -lt 0) { continue }
            $before = $lines[$p].Trim()
            if ($before -notmatch '^"([^"\\]+)"\s*:') { continue }
            $key = $Matches[1]
            if (((& $unescapedQuoteCount $before) % 2) -eq 0) { continue }

            # The line after the fence must start the same key again.
            $a = $li + 1
            while ($a -lt $lines.Count -and $lines[$a].Trim().Length -eq 0) { $a++ }
            if ($a -ge $lines.Count) { continue }
            $after = $lines[$a].Trim()
            if ($after -notmatch ('^"' + [regex]::Escape($key) + '"\s*:')) { continue }

            # Drop the broken line and the fence, and keep the restart. The agent
            # rewrites the field from scratch, so nothing is duplicated.
            $newLines = [System.Collections.Generic.List[string]]::new()
            if ($p -gt 0) { for ($x = 0; $x -lt $p; $x++) { $newLines.Add($lines[$x]) | Out-Null } }
            for ($x = $a; $x -lt $lines.Count; $x++) { $newLines.Add($lines[$x]) | Out-Null }
            $result = ($newLines -join "`n")
            $repaired = $true
            break
        }

        if (-not $repaired) { break }
    }

    return $result
}

function Repair-ShellEscapedQuotes {
    <#
    Normalizes POSIX shell single-quote escaping that can leak into the
    findings report. When a suggested-code field carries AL content with a
    single-quoted token (e.g. a Label like BearerTok: Label '******') and the
    agent emits it through a single-quoted shell argument, the shell
    close/escape/reopen idiom '\'' can survive verbatim into
    _review-report.json. The 4-char sequence '\'' is invalid JSON (a
    backslash-escaped single quote is not a legal string escape), so both
    ConvertFrom-Json and json.loads reject the entire report. Collapsing the
    exact sequence back to a bare single quote restores valid JSON. That
    sequence can never appear in well-formed JSON (a bare ' is only legal
    inside a string and \' is always invalid), so the replacement is safe
    globally; AL doubles quotes ('') to escape them and never emits '\''.
    #>
    param([string] $Text)
    if (-not $Text) { return $Text }
    return $Text.Replace("'\''", "'")
}

function ConvertFrom-BCQualityReport {
    <#
    Parses Copilot CLI output into a findings-report. Returns a PSCustomObject:
      Outcome      : completed | not-applicable | no-knowledge | partial | failed
      OutcomeReason: string (or '')
      Findings     : normalized list of [pscustomobject] @{ filePath; lineNumber;
                       severity (Critical|High|Medium|Low); domain; issue; recommendation;
                       suggestedCode; suggestedCodeOmissionReason; references; confidence;
                       rawId; isAgentFinding }
      Suppressed   : list of @{ path; sha; reason }
      SkippedSubSkills: list of @{ id; reason }
      SubResultCount: integer
    Caps findings per sub-skill at $MaxFindings and filters by $MinimumSeverity
    (or $AgentMinimumSeverity for findings marked as agent findings).
    #>
    param([string] $Output)

    $parseErrors = [System.Collections.Generic.List[string]]::new()

    # Extract the first parseable JSON object/array from the output.
    # The Copilot CLI's stdout can be noisy: tool-call TUI markers (e.g.
    # "* Read entry.md"), ANSI escapes, and other diagnostics may be
    # interleaved with the model's final response. Try in order:
    #   1. Fenced ```json / ``` blocks.
    #   2. The first balanced JSON object/array we can find in the stripped
    #      output (handles cases where the fenced block was mangled in
    #      transit, e.g. only partially captured by the async output reader).
    #   3. The trimmed output as-is.
    $repaired = Repair-InterruptedAgentJson -Output (Repair-ShellEscapedQuotes -Text $Output)
    $stripped = [regex]::Replace($repaired, "`e\[[\d;]*[A-Za-z]", '')

    $candidates = [System.Collections.Generic.List[string]]::new()
    $codeBlocks = [regex]::Matches($stripped, '```(?:json)?\s*([\s\S]*?)\s*```')
    foreach ($m in $codeBlocks) { $candidates.Add($m.Groups[1].Value) | Out-Null }
    foreach ($balanced in (Find-BalancedJsonCandidates -Text $stripped)) {
        $candidates.Add($balanced) | Out-Null
    }
    if ($candidates.Count -eq 0) { $candidates.Add($stripped.Trim()) | Out-Null }

    # Append de-fenced variants as additional fallbacks. The agent sometimes
    # splices a bare ```json fence line into the middle of the findings-report
    # (an interrupted-emission resume with no "Placeholder" marker), which keeps
    # the balanced candidate structurally complete but syntactically invalid.
    # Stripping the stray fence recovers the full report. Originals are tried
    # first so clean output is unaffected.
    $defenced = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        $clean = Remove-StructuralFences -Text $candidate
        if ($clean -ne $candidate) { $defenced.Add($clean) | Out-Null }
    }
    foreach ($clean in $defenced) { $candidates.Add($clean) | Out-Null }

    # Repair the resume-fence shape (a stray ```json fence inside an open
    # string, which Remove-StructuralFences leaves alone), then add its
    # candidates after the originals so clean output stays untouched.
    $resumeRepaired = Repair-ResumeFenceJson -Output $stripped
    if ($resumeRepaired -ne $stripped) {
        $resumeCandidates = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($resumeRepaired, '```(?:json)?\s*([\s\S]*?)\s*```')) { $resumeCandidates.Add($m.Groups[1].Value) | Out-Null }
        foreach ($balanced in (Find-BalancedJsonCandidates -Text $resumeRepaired)) { $resumeCandidates.Add($balanced) | Out-Null }
        foreach ($candidate in $resumeCandidates) {
            $candidates.Add($candidate) | Out-Null
            $clean = Remove-StructuralFences -Text $candidate
            if ($clean -ne $candidate) { $candidates.Add($clean) | Out-Null }
        }
    }

    # A fragment can parse fine but still be the wrong one. The output repeats
    # each sub-skill report and the findings[] array as separate JSON, so if the
    # full document won't parse, one of those can win and the real report is
    # lost. Pick the orchestrator report first (it has sub-results or dispatch),
    # then any object with findings, then any fragment that parses.
    $report = $null
    $shapedReport = $null
    $fallbackReport = $null
    foreach ($candidate in $candidates) {
        $trimmed = $candidate.Trim()
        if (-not $trimmed) { continue }
        $parsed = $null
        try {
            $parsed = $trimmed | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $preview = $trimmed
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
            $parseErrors.Add("$($_.Exception.Message) | candidate: $preview") | Out-Null
            continue
        }

        $isObject = $parsed -is [System.Management.Automation.PSCustomObject]
        $isOrchestratorShaped = $isObject -and (
            $parsed.PSObject.Properties.Match('sub-results').Count -gt 0 -or
            $parsed.PSObject.Properties.Match('dispatch').Count -gt 0)
        if ($isOrchestratorShaped) { $report = $parsed; break }
        if ($null -eq $shapedReport -and $isObject -and $parsed.PSObject.Properties.Match('findings').Count -gt 0) {
            $shapedReport = $parsed
        }
        if ($null -eq $fallbackReport) { $fallbackReport = $parsed }
    }
    if ($null -eq $report) { $report = $shapedReport }
    if ($null -eq $report) { $report = $fallbackReport }

    $script:LastParsingErrors = $parseErrors

    if ($null -eq $report) {
        return [pscustomobject]@{
            Outcome = 'failed'; OutcomeReason = 'No parseable JSON object in Copilot output'
            Findings = @(); Suppressed = @(); SkippedSubSkills = @(); FailedSubSkills = @(); SubResults = @(); SubResultCount = 0
        }
    }

    # Distinguish a dispatch record (Entry returns outcome routed/no-match/failed)
    # from a findings-report. A dispatch record has `dispatch[]`, no `findings[]`.
    $isDispatchRecord = $report.PSObject.Properties.Match('dispatch').Count -gt 0 -and `
                        $report.PSObject.Properties.Match('findings').Count -eq 0
    if ($isDispatchRecord) {
        $reason = if ($report.PSObject.Properties.Match('outcome-reason').Count -gt 0) { [string]$report.'outcome-reason' } else { 'Entry returned a dispatch record (no action skill ran)' }
        return [pscustomobject]@{
            Outcome = ([string]$report.outcome ?? 'failed')
            OutcomeReason = $reason
            Findings = @(); Suppressed = @(); SkippedSubSkills = @(); FailedSubSkills = @(); SubResults = @(); SubResultCount = 0
        }
    }

    $outcome = if ($report.PSObject.Properties.Match('outcome').Count -gt 0) { [string]$report.outcome } else { 'completed' }
    $outcomeReason = if ($report.PSObject.Properties.Match('outcome-reason').Count -gt 0) { [string]$report.'outcome-reason' } else { '' }

    $rawFindings = @()
    if ($report.PSObject.Properties.Match('findings').Count -gt 0 -and $null -ne $report.findings) {
        $rawFindings = @($report.findings)
    }

    $normalized = [System.Collections.Generic.List[object]]::new()
    $backedMinRank = $SeverityOrder[$MinimumSeverity]
    $agentMinRank  = $SeverityOrder[$AgentMinimumSeverity]

    foreach ($f in $rawFindings) {
        if ($null -eq $f) { continue }
        $sev = $null
        if ($f.PSObject.Properties.Match('severity').Count -gt 0) {
            $sev = Convert-BCQualitySeverity -Severity ([string]$f.severity)
        }
        if (-not $sev) { continue }

        # Extract the structural fields the detection logic needs.
        $references = @()
        if ($f.PSObject.Properties.Match('references').Count -gt 0 -and $null -ne $f.references) {
            $references = @($f.references | Where-Object { $_ -ne $null } | ForEach-Object {
                $r = $_
                $path = ''
                $sha  = ''
                if ($r.PSObject.Properties.Match('path').Count -gt 0) { $path = [string]$r.path }
                if ($r.PSObject.Properties.Match('sha').Count  -gt 0) { $sha  = [string]$r.sha }
                [pscustomobject]@{ path = $path; sha = $sha }
            })
        }

        $rawId = ''
        if ($f.PSObject.Properties.Match('id').Count -gt 0) { $rawId = [string]$f.id }

        # Detect agent-finding marker. Three encodings are accepted so the
        # orchestrator stays lenient against the BCQuality DO contract:
        #   - from-sub-skill: "agent"     — super-skill self-review marker
        #   - knowledge-backed: false     — explicit legacy boolean
        #   - references: [] AND id starts with "agent:"  — the canonical
        #     leaf-level encoding introduced by microsoft/BCQuality#21,
        #     where a leaf may emit an agent finding within its own domain
        #     while keeping from-sub-skill as the leaf's own id
        $isAgentFinding = $false
        $fromSubRaw = $null
        if ($f.PSObject.Properties.Match('from-sub-skill').Count -gt 0) {
            $fromSubRaw = [string]$f.'from-sub-skill'
        } elseif ($f.PSObject.Properties.Match('from_sub_skill').Count -gt 0) {
            $fromSubRaw = [string]$f.from_sub_skill
        }
        if ($fromSubRaw -and $fromSubRaw.Trim().ToLowerInvariant() -eq 'agent') {
            $isAgentFinding = $true
        }
        if (-not $isAgentFinding -and $f.PSObject.Properties.Match('knowledge-backed').Count -gt 0) {
            if ($f.'knowledge-backed' -eq $false) { $isAgentFinding = $true }
        }
        if (-not $isAgentFinding -and $f.PSObject.Properties.Match('knowledge_backed').Count -gt 0) {
            if ($f.knowledge_backed -eq $false) { $isAgentFinding = $true }
        }
        if (-not $isAgentFinding -and $references.Count -eq 0 -and $rawId -and $rawId.StartsWith('agent:')) {
            $isAgentFinding = $true
        }

        $sevRank = $SeverityOrder[$sev]
        if ($isAgentFinding) {
            if ($sevRank -gt $agentMinRank) { continue }
        } else {
            if ($sevRank -gt $backedMinRank) { continue }
        }

        $filePath = ''
        $lineNumber = 0
        if ($f.PSObject.Properties.Match('location').Count -gt 0 -and $null -ne $f.location) {
            if ($f.location.PSObject.Properties.Match('file').Count -gt 0) { $filePath = [string]$f.location.file }
            if ($f.location.PSObject.Properties.Match('line').Count -gt 0 -and $f.location.line) { $lineNumber = [int]$f.location.line }
        }

        $message = ''
        if ($f.PSObject.Properties.Match('message').Count -gt 0) { $message = [string]$f.message }

        $confidence = ''
        if ($f.PSObject.Properties.Match('confidence').Count -gt 0) { $confidence = [string]$f.confidence }

        # Optional concrete code-replacement payload. When present, the
        # orchestrator renders it as a GitHub ```suggestion``` block so the
        # reviewer can one-click apply the fix. Accept a few aliases to stay
        # lenient against skill-author variations.
        $suggestedCode = ''
        foreach ($prop in @('suggested-code', 'suggested_code', 'suggestion', 'suggestedCode')) {
            if ($f.PSObject.Properties.Match($prop).Count -gt 0 -and $null -ne $f.$prop) {
                $suggestedCode = [string]$f.$prop
                if ($suggestedCode) { break }
            }
        }
        $suggestedCodeOmissionReason = ''
        foreach ($prop in @('suggested-code-omission-reason', 'suggested_code_omission_reason', 'suggestedCodeOmissionReason')) {
            if ($f.PSObject.Properties.Match($prop).Count -gt 0 -and $null -ne $f.$prop) {
                $suggestedCodeOmissionReason = [string]$f.$prop
                if ($suggestedCodeOmissionReason) { break }
            }
        }

        $explicitDomain = Get-ExplicitFindingDomain -Finding $f
        $domain = Resolve-FindingDomain -Finding $f
        # Preserve emitted labels even for agent-judgement findings: leaf skills
        # may intentionally keep their own domain. Only retain the historical
        # Agent override when an older producer supplied no label and no mapped
        # sub-skill domain.
        if ($isAgentFinding -and -not $explicitDomain -and $domain -eq 'Other') { $domain = 'Agent' }

        # Split the message on a conventional 'Recommendation:' or 'Fix:'
        # marker so the inline comment can render guidance separately. The
        # DO contract does not require this; it is a best-effort affordance
        # for skills whose authors include it.
        $issueText = $message
        $recommendation = ''
        if ($message -match '(?ims)^(.+?)\s*\b(?:Recommendation|Fix)\s*:\s*(.+)$') {
            $issueText = $Matches[1].Trim()
            $recommendation = $Matches[2].Trim()
        }

        $normalized.Add([pscustomobject]@{
            filePath        = ($filePath -replace '\\', '/')
            lineNumber      = $lineNumber
            severity        = $sev
            domain          = $domain
            issue           = $issueText
            recommendation  = $recommendation
            suggestedCode   = $suggestedCode
            suggestedCodeOmissionReason = $suggestedCodeOmissionReason
            references      = $references
            confidence      = $confidence
            rawId           = $rawId
            isAgentFinding  = $isAgentFinding
        }) | Out-Null
    }

    $suppressed = @()
    if ($report.PSObject.Properties.Match('suppressed').Count -gt 0 -and $null -ne $report.suppressed) {
        $suppressed = @($report.suppressed | Where-Object { $_ -ne $null } | ForEach-Object {
            $s = $_
            $path = ''; $sha = ''; $reason = ''
            if ($s.PSObject.Properties.Match('reference').Count -gt 0 -and $null -ne $s.reference) {
                if ($s.reference.PSObject.Properties.Match('path').Count -gt 0) { $path = [string]$s.reference.path }
                if ($s.reference.PSObject.Properties.Match('sha').Count  -gt 0) { $sha  = [string]$s.reference.sha }
            }
            if ($s.PSObject.Properties.Match('reason').Count -gt 0) { $reason = [string]$s.reason }
            [pscustomobject]@{ path = $path; sha = $sha; reason = $reason }
        })
    }

    $skippedSubSkills = @()
    if ($report.PSObject.Properties.Match('skipped-sub-skills').Count -gt 0 -and $null -ne $report.'skipped-sub-skills') {
        $skippedSubSkills = @($report.'skipped-sub-skills' | Where-Object { $_ -ne $null } | ForEach-Object {
            $s = $_
            $id = ''; $reason = ''
            if ($s.PSObject.Properties.Match('skill').Count -gt 0 -and $null -ne $s.skill -and $s.skill.PSObject.Properties.Match('id').Count -gt 0) {
                $id = [string]$s.skill.id
            }
            if ($s.PSObject.Properties.Match('reason').Count -gt 0) { $reason = [string]$s.reason }
            [pscustomobject]@{ id = $id; reason = $reason }
        })
    }

    $subResults = @()
    if ($report.PSObject.Properties.Match('sub-results').Count -gt 0 -and $null -ne $report.'sub-results') {
        $subResults = @($report.'sub-results' | Where-Object { $_ -ne $null } | ForEach-Object {
            $sr = $_
            $id = ''
            if ($sr.PSObject.Properties.Match('skill').Count -gt 0 -and $null -ne $sr.skill) {
                if ($sr.skill.PSObject.Properties.Match('id').Count -gt 0) { $id = [string]$sr.skill.id }
            }
            if (-not $id -and $sr.PSObject.Properties.Match('skill-id').Count -gt 0) { $id = [string]$sr.'skill-id' }
            if (-not $id -and $sr.PSObject.Properties.Match('id').Count -gt 0)        { $id = [string]$sr.id }

            $srOutcome = ''
            if ($sr.PSObject.Properties.Match('outcome').Count -gt 0) { $srOutcome = [string]$sr.outcome }
            $srOutcomeReason = ''
            if ($sr.PSObject.Properties.Match('outcome-reason').Count -gt 0) {
                $srOutcomeReason = [string]$sr.'outcome-reason'
            }

            $srFindingCount = $null
            if ($sr.PSObject.Properties.Match('findings').Count -gt 0 -and $null -ne $sr.findings) {
                $srFindingCount = @($sr.findings).Count
            }

            # Knowledge references consumed by this sub-skill. The DO contract
            # is best-effort here; skills may surface them under any of the
            # following property names. Collect a flat list of {path; sha}.
            $srRefs = [System.Collections.Generic.List[object]]::new()
            foreach ($prop in @('knowledge', 'knowledge-consumed', 'references', 'sources')) {
                if ($sr.PSObject.Properties.Match($prop).Count -gt 0 -and $null -ne $sr.$prop) {
                    foreach ($r in @($sr.$prop)) {
                        if ($null -eq $r) { continue }
                        $rPath = ''; $rSha = ''
                        if ($r -is [string]) { $rPath = [string]$r }
                        else {
                            if ($r.PSObject.Properties.Match('path').Count -gt 0) { $rPath = [string]$r.path }
                            if ($r.PSObject.Properties.Match('sha').Count  -gt 0) { $rSha  = [string]$r.sha }
                        }
                        if ($rPath) { $srRefs.Add([pscustomobject]@{ path = $rPath; sha = $rSha }) | Out-Null }
                    }
                }
            }

            [pscustomobject]@{
                id           = $id
                outcome      = $srOutcome
                outcomeReason = $srOutcomeReason
                findingCount = $srFindingCount
                references   = @($srRefs)
            }
        })
    }
    $subResultCount = $subResults.Count
    $failedSubSkills = @($subResults | Where-Object { $_.outcome -eq 'failed' } | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            reason = $_.outcomeReason
        }
    })

    # Per-domain cap, then global sort.
    $byDomain = Get-OrdinalDictionary
    foreach ($f in $normalized) {
        if (-not $byDomain.ContainsKey($f.domain)) { $byDomain[$f.domain] = [System.Collections.Generic.List[object]]::new() }
        $byDomain[$f.domain].Add($f) | Out-Null
    }
    $capped = [System.Collections.Generic.List[object]]::new()
    foreach ($d in (Get-OrdinalSortedKey -Dictionary $byDomain)) {
        $sorted = $byDomain[$d] |
            Sort-Object @{Expression = { $SeverityOrder[$_.severity] }}, filePath, lineNumber |
            Select-Object -First $MaxFindings
        foreach ($f in $sorted) { $capped.Add($f) | Out-Null }
    }

    return [pscustomobject]@{
        Outcome = $outcome
        OutcomeReason = $outcomeReason
        Findings = @($capped)
        Suppressed = $suppressed
        SkippedSubSkills = $skippedSubSkills
        FailedSubSkills = $failedSubSkills
        SubResults = @($subResults)
        SubResultCount = $subResultCount
    }
}

# ---------------------------------------------------------------------------
# Log which BCQuality skills and knowledge articles were consumed
# ---------------------------------------------------------------------------
function Write-ConsumedBCQualityLog {
    <#
    Emits a workflow-log-friendly summary of which BCQuality skills the
    Copilot agent invoked during the review and which knowledge articles
    those skills cited. Sources, in precedence order:

      - SubResults[].id / outcome / findingCount       (from `sub-results[]`)
      - SubResults[].references[].path                 (per-sub-skill knowledge)
      - Findings[].domain via Findings[].rawId         (sub-skill fallback)
      - Findings[].references[].path                   (knowledge cited inline)

    The log is best-effort and informational; absent fields are tolerated.
    #>
    param([object] $Report)

    if ($null -eq $Report) { return }

    Write-Host '--- BCQuality skills and knowledge consumed ---'

    $subResults = @()
    if ($Report.PSObject.Properties.Match('SubResults').Count -gt 0 -and $null -ne $Report.SubResults) {
        $subResults = @($Report.SubResults)
    }
    $findings = @()
    if ($Report.PSObject.Properties.Match('Findings').Count -gt 0 -and $null -ne $Report.Findings) {
        $findings = @($Report.Findings)
    }

    # Aggregate per-skill data from SubResults; fall back to from-sub-skill on
    # findings when the super-skill did not return sub-results[].
    $skillMap = Get-OrdinalDictionary
    foreach ($sr in $subResults) {
        if ($null -eq $sr) { continue }
        $sid = if ($sr.id) { [string]$sr.id } else { '(unknown)' }
        if (-not $skillMap.ContainsKey($sid)) {
            $skillMap[$sid] = [pscustomobject]@{
                Outcome      = [string]$sr.outcome
                FindingCount = if ($null -ne $sr.findingCount) { [int]$sr.findingCount } else { 0 }
                Knowledge    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        foreach ($r in @($sr.references)) {
            if ($r -and $r.path) { [void]$skillMap[$sid].Knowledge.Add([string]$r.path) }
        }
    }

    # Fallback: when the agent did not return sub-results[], derive a coarse
    # per-domain bucket from each finding so we still surface a "skills"
    # rollup. The normalized finding does not retain its raw from-sub-skill,
    # so the domain label is the best signal we have here.
    $useDomainFallback = ($skillMap.Count -eq 0)
    if ($useDomainFallback) {
        foreach ($f in $findings) {
            if ($null -eq $f) { continue }
            $bucket = [string]$f.domain
            if (-not $bucket) { $bucket = 'Other' }
            if (-not $skillMap.ContainsKey($bucket)) {
                $skillMap[$bucket] = [pscustomobject]@{
                    Outcome      = ''
                    FindingCount = 0
                    Knowledge    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                }
            }
            $skillMap[$bucket].FindingCount = $skillMap[$bucket].FindingCount + 1
            foreach ($r in @($f.references)) {
                if ($r -and $r.path) { [void]$skillMap[$bucket].Knowledge.Add([string]$r.path) }
            }
        }
    }

    if ($skillMap.Count -eq 0) {
        Write-Host '  (no sub-skills reported by the agent)'
    } else {
        Write-Host "Sub-skills executed ($($skillMap.Count)):"
        $skillKeys = if ($useDomainFallback) {
            Get-OrdinalSortedKey -Dictionary $skillMap
        } else {
            @($skillMap.Keys)
        }
        foreach ($sid in $skillKeys) {
            $entry = $skillMap[$sid]
            $parts = [System.Collections.Generic.List[string]]::new()
            if ($entry.Outcome)          { $parts.Add("outcome=$($entry.Outcome)") | Out-Null }
            if ($entry.FindingCount -gt 0) { $parts.Add("findings=$($entry.FindingCount)") | Out-Null }
            if ($entry.Knowledge.Count -gt 0) { $parts.Add("knowledge=$($entry.Knowledge.Count)") | Out-Null }
            $suffix = if ($parts.Count -gt 0) { " ($($parts -join ', '))" } else { '' }
            Write-Host "  - $sid$suffix"
            foreach ($k in ($entry.Knowledge | Sort-Object)) {
                Write-Host "      knowledge: $k"
            }
        }
    }

    # Flat de-duplicated list of all knowledge articles cited, regardless
    # of which sub-skill cited them — useful for at-a-glance review.
    $allKnowledge = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $skillMap.Values) {
        foreach ($k in $entry.Knowledge) { [void]$allKnowledge.Add($k) }
    }
    foreach ($f in @($Report.Findings)) {
        if ($null -eq $f) { continue }
        foreach ($r in @($f.references)) {
            if ($r -and $r.path) { [void]$allKnowledge.Add([string]$r.path) }
        }
    }

    if ($allKnowledge.Count -gt 0) {
        Write-Host "Knowledge articles cited ($($allKnowledge.Count)):"
        foreach ($k in ($allKnowledge | Sort-Object)) {
            Write-Host "  - $k"
        }
    } else {
        Write-Host 'Knowledge articles cited: (none)'
    }

    if ($Report.SkippedSubSkills -and $Report.SkippedSubSkills.Count -gt 0) {
        Write-Host "Sub-skills skipped ($($Report.SkippedSubSkills.Count)):"
        foreach ($s in $Report.SkippedSubSkills) {
            $reason = if ($s.reason) { " — $($s.reason)" } else { '' }
            Write-Host "  - $($s.id)$reason"
        }
    }

    if ($Report.Suppressed -and $Report.Suppressed.Count -gt 0) {
        Write-Host "Knowledge files suppressed by filter ($($Report.Suppressed.Count)):"
        foreach ($s in $Report.Suppressed) {
            $reason = if ($s.reason) { " — $($s.reason)" } else { '' }
            Write-Host "  - $($s.path)$reason"
        }
    }

    Write-Host '--- end BCQuality consumption summary ---'
}
