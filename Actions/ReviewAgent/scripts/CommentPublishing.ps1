# ---------------------------------------------------------------------------
# Agent metadata + comment rendering
# ---------------------------------------------------------------------------
function ConvertTo-AgentLabelToken {
    param([string] $Value)
    $normalized = ($Value ?? '').Trim().ToLowerInvariant().Replace('_', '-').Replace(' ', '-')
    $normalized = [regex]::Replace($normalized, '[^a-z0-9-]+', '-')
    $normalized = [regex]::Replace($normalized, '-{2,}', '-').Trim('-')
    return $normalized
}

function Resolve-AgentReleaseDate {
    if ($AgentDateRaw) {
        if ($AgentDateRaw -notmatch '^\d{4}-\d{2}-\d{2}$') {
            throw "COPILOT_REVIEW_AGENT_RELEASE_DATE must use YYYY-MM-DD format when provided. Got: $AgentDateRaw"
        }
        return $AgentDateRaw
    }
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
}

function Resolve-AgentReleaseVersion {
    if (-not $AgentVersionRaw) { return 0 }
    $normalizedVersion = if ($AgentVersionRaw.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $AgentVersionRaw.Substring(1)
    } else { $AgentVersionRaw }
    if ($normalizedVersion -notmatch '^\d+$') {
        throw "COPILOT_REVIEW_AGENT_RELEASE_VERSION must be a non-negative integer or v-prefixed integer. Got: $AgentVersionRaw"
    }
    return [int]$normalizedVersion
}

function Resolve-AgentVersion {
    param([string] $EngineRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))

    if ($AgentSemVerRaw) {
        if ($AgentSemVerRaw -notmatch '^\d+\.\d+\.\d+$') {
            throw "COPILOT_REVIEW_AGENT_VERSION must use X.Y.Z format when provided. Got: $AgentSemVerRaw"
        }
        return $AgentSemVerRaw
    }

    if ($AgentDateRaw -or $AgentVersionRaw) {
        return "$(Resolve-AgentReleaseDate).v$(Resolve-AgentReleaseVersion)"
    }

    # Preserve compatibility with standalone engine releases that tag the exact
    # commit as X.Y.Z.
    $tagOutput = @(& git -C $EngineRoot tag --points-at HEAD 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $version = @($tagOutput | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
        if ($version.Count -gt 0) {
            return [string]$version[0]
        }
    }

    # AL-Go releases use vX.Y tags. Combine the nearest release's X.Y with the
    # monotonic BCQuality content minor so review metadata remains X.Y.Z while
    # main and prototype branches between AL-Go releases still have a version.
    $releaseTagOutput = @(& git -C $EngineRoot describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*' 2>&1)
    if ($LASTEXITCODE -eq 0 -and $releaseTagOutput.Count -gt 0 -and [string]$releaseTagOutput[0] -match '^v(\d+)\.(\d+)$') {
        $engineMajor = $Matches[1]
        $engineMinor = $Matches[2]
        $bcQualityVersion = $BCQualityVersion
        if ($bcQualityVersion -notmatch '^\d+\.(\d+)$') {
            throw "BCQUALITY_VERSION must use major.minor format to derive the AL-Go review engine version. Got: '$bcQualityVersion'"
        }
        $contentMinor = $Matches[1]
        return "$engineMajor.$engineMinor.$contentMinor"
    }

    $manifestVersion = Get-PluginManifestVersion -EngineRoot $EngineRoot
    if ($manifestVersion) {
        return $manifestVersion
    }

    throw 'Could not determine engine version: no X.Y.Z tag on HEAD, no reachable AL-Go vX.Y release tag, and no version in .github/plugin/plugin.json. Set COPILOT_REVIEW_AGENT_VERSION for an unreleased commit.'
}

function Get-PluginManifestVersion {
    param([string] $EngineRoot)

    $manifestPath = Join-Path $EngineRoot '.github/plugin/plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
    $manifestVersion = ($manifest.version + '').Trim()
    if ($manifestVersion -notmatch '^\d+\.\d+\.\d+$') { return $null }
    return $manifestVersion
}

function Resolve-AgentLabel {
    $configuredLabel = if ($AgentLabelRaw) { $AgentLabelRaw } else { 'copilot-pr-review' }
    $sanitizedLabel = ConvertTo-AgentLabelToken -Value $configuredLabel
    if (-not $sanitizedLabel) {
        throw 'COPILOT_REVIEW_AGENT_LABEL must contain at least one alphanumeric character when provided.'
    }
    return $sanitizedLabel
}

function Resolve-AgentCommentDocUrl {
    $defaultUrl = 'https://github.com/microsoft/BCQuality'
    if (-not $AgentCommentDocUrlRaw) { return $defaultUrl }
    $uri = $null
    if (-not [System.Uri]::TryCreate($AgentCommentDocUrlRaw, [System.UriKind]::Absolute, [ref]$uri)) {
        Write-Warning "Ignoring invalid AGENT_COMMENT_DOC_URL value: $AgentCommentDocUrlRaw"; return $defaultUrl
    }
    if ($uri.Scheme -notin @('http', 'https')) {
        Write-Warning "Ignoring unsupported AGENT_COMMENT_DOC_URL scheme: $($uri.Scheme)"; return $defaultUrl
    }
    return $uri.AbsoluteUri
}

function Get-AgentVersionMetadata {
    $sanitizedVersion = [regex]::Replace($AgentVersion, '(--|<|>|\r|\n)', '')
    return "<!-- agent_version: $sanitizedVersion -->"
}

function Get-AgentLabelMetadata {
    return "<!-- agent_label: $AgentLabel -->"
}

function ConvertTo-DomainMetadataKey {
    param([string] $Domain)

    if ([string]::IsNullOrWhiteSpace($Domain)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Domain.Trim())
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertTo-LegacyDomainKey {
    param([string] $Domain)

    if ([string]::IsNullOrWhiteSpace($Domain)) { return '' }
    return $Domain.Trim().ToLowerInvariant()
}

function Get-AgentDomainMetadata {
    param([string] $Domain)
    # The key is base64url-encoded rather than slugged: visually similar labels
    # such as C#, C++, "a-b", and "a b" must never share a dedup bucket.
    return "<!-- agent_domain_key: $(ConvertTo-DomainMetadataKey -Domain $Domain) -->"
}

function Get-AgentFindingMetadata {
    param([bool] $IsAgentFinding)
    if ($IsAgentFinding) { return "<!-- agent_finding: true -->" }
    return "<!-- agent_finding: false -->"
}

function Get-AgentMetadataBlock {
    param([string] $Domain, [bool] $IsAgentFinding = $false)
    return @(
        Get-AgentVersionMetadata
        Get-AgentLabelMetadata
        Get-AgentDomainMetadata -Domain $Domain
        Get-AgentFindingMetadata -IsAgentFinding $IsAgentFinding
    ) -join "`n"
}

function Get-SeverityBadge {
    param([string] $Severity)
    switch ($Severity) {
        'Critical' { return '🔴' }
        'High'     { return '🟠' }
        'Medium'   { return '🟡' }
        'Low'      { return '🟢' }
        default    { return '⚪' }
    }
}

function Resolve-ReviewIteration {
    $existingSummaryComment = $null
    foreach ($comment in (Get-IssueComments)) {
        if (($comment.body ?? '') -match [regex]::Escape($SummaryMarker)) {
            $existingSummaryComment = $comment
            break
        }
    }
    if (-not $existingSummaryComment) { return 1 }
    $body = $existingSummaryComment.body ?? ''
    if ($body -match '<!-- agent_review_iteration:\s*(\d+)\s*-->') { return ([int]$Matches[1]) + 1 }
    return 1
}

function Get-BCQualityRepoUrl {
    if (-not $script:BCQualityWebRepoUrl) {
        $script:BCQualityWebRepoUrl = ([string]$env:BCQUALITY_REPO).TrimEnd('/')
        if ($script:BCQualityWebRepoUrl.EndsWith('.git')) {
            $script:BCQualityWebRepoUrl = $script:BCQualityWebRepoUrl.Substring(0, $script:BCQualityWebRepoUrl.Length - 4)
        }
    }
    return $script:BCQualityWebRepoUrl
}

function Build-ReferenceLink {
    param([object] $Reference)
    $repoUrl = Get-BCQualityRepoUrl
    if (-not $repoUrl) { return ([string]$Reference.path) }
    $ref = "v$BCQualityVersion"
    $path = ([string]$Reference.path).TrimStart('/')
    $url = "$repoUrl/blob/$ref/$path"
    return "[$path]($url)"
}

function ConvertTo-LaTexText {
    param([string] $Value)

    $singleLine = [regex]::Replace(($Value ?? ''), '[\r\n\t]+', ' ')
    $escaped = [regex]::Replace($singleLine, '[\\{}$&#%_^~]', {
        param($match)
        switch ($match.Value) {
            '\' { return '\textbackslash{}' }
            '{' { return '\{' }
            '}' { return '\}' }
            '$' { return '\$' }
            '&' { return '\&' }
            '#' { return '\#' }
            '%' { return '\%' }
            '_' { return '\_' }
            '^' { return '\textasciicircum{}' }
            '~' { return '\textasciitilde{}' }
        }
    })
    return $escaped.Replace(' ', '\ ')
}

function ConvertTo-MarkdownTableCell {
    param([string] $Value)

    $singleLine = [regex]::Replace(($Value ?? ''), '[\r\n\t]+', ' ')
    $escaped = $singleLine.Replace('\', '\\').
        Replace('|', '\|').
        Replace('`', '\`').
        Replace('*', '\*').
        Replace('_', '\_').
        Replace('~', '\~').
        Replace('[', '\[').
        Replace(']', '\]').
        Replace('(', '\(').
        Replace(')', '\)').
        Replace('#', '\#').
        Replace('!', '\!')
    $encoded = [System.Net.WebUtility]::HtmlEncode($escaped)
    return $encoded.
        Replace('$', '&#36;').
        Replace('@', '&#64;').
        Replace(':', '&#58;')
}

function Build-CommentBody {
    param([object] $Finding, [switch] $SuppressSuggestion)

    $domain   = $Finding.domain
    $severity = $Finding.severity
    $issue    = ([string]$Finding.issue).TrimEnd()
    $rec      = ([string]$Finding.recommendation).TrimEnd()
    $suggested = ([string]$Finding.suggestedCode).TrimEnd()
    $references = @($Finding.references)
    $isAgentFinding = [bool]$Finding.isAgentFinding

    $normalizedIssue = [regex]::Replace($issue, '\s+', ' ').Trim()
    if (-not $normalizedIssue) {
        $normalizedIssue = "$severity $(ConvertTo-MarkdownTableCell -Value $domain) finding"
    }

    $preheaderDomain = ConvertTo-LaTexText -Value $domain
    # The iteration counter is tracked only in the summary comment. When the
    # summary is disabled the counter cannot advance, so the label is omitted
    # rather than shown as a misleading constant "Iteration 1".
    $preheader = '$\textbf{' + (Get-SeverityBadge -Severity $severity) + '\ ' + $severity + '\ Severity\ —\ ' + $preheaderDomain + '}'
    if ($PostSummaryComment) {
        $preheader += ' \quad \color{gray}{\texttt{\small Iteration\ ' + $ReviewIteration + '}}'
    }
    $preheader += '$'

    # Render the issue as normal prose. Promoting the first sentence to an H3
    # heading made long lead sentences render as an oversized title (bug 642599).
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($preheader) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add($normalizedIssue) | Out-Null

    if ($rec) {
        $lines.Add('') | Out-Null
        $lines.Add('**Recommendation:**') | Out-Null
        foreach ($recLine in ($rec -split "(`r`n|`n|`r)")) {
            $t = $recLine.Trim()
            if ($t) { $lines.Add("- $t") | Out-Null }
        }
    }

    if ($suggested -and -not $SuppressSuggestion) {
        $lines.Add('') | Out-Null
        $lines.Add('```suggestion') | Out-Null
        $lines.Add($suggested) | Out-Null
        $lines.Add('```') | Out-Null
    } elseif ($suggested -and $SuppressSuggestion) {
        # A concrete fix was identified but its target line(s) could not be
        # matched against the PR-head file, so an applicable suggestion block
        # would risk corrupting the file. Surface the intended change as a
        # non-applicable code snippet instead.
        $lines.Add('') | Out-Null
        $lines.Add('**Suggested fix** (apply manually — could not be anchored as a one-click suggestion):') | Out-Null
        $lines.Add('```al') | Out-Null
        $lines.Add($suggested) | Out-Null
        $lines.Add('```') | Out-Null
    }

    if ($references.Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('**Knowledge:**') | Out-Null
        foreach ($ref in $references) {
            if (-not $ref.path) { continue }
            $lines.Add("- $(Build-ReferenceLink -Reference $ref)") | Out-Null
        }
    } elseif ($isAgentFinding -and $domain -cne 'Agent') {
        # Distinguish agent-judgement findings from knowledge-backed ones so
        # the reader can tell which bucket this falls into, without
        # undermining a finding that may still be high-confidence and
        # high-severity (e.g. dead code, unused parameter). Skip the note
        # when the header already reads "Agent" (super-skill self-review
        # findings) — the footer would just repeat the header. We keep it
        # for leaf-level agent findings where the header carries the
        # leaf's domain (Security, Performance, etc.) and the agent-
        # judgement provenance needs to be surfaced separately.
        $lines.Add('') | Out-Null
        $lines.Add('<sub>Agent judgement — not directly backed by a BCQuality knowledge article.</sub>') | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add((Get-AgentMetadataBlock -Domain $domain -IsAgentFinding $isAgentFinding)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("<sub>👍 useful · ❤️ especially valuable · 👎 wrong - <a href=`"$AgentCommentDocUrl`">reply with why</a> · AL review agent v$AgentVersion</sub>") | Out-Null
    return $lines -join "`n"
}

function Add-CommentNotice {
    param([string] $Body, [string] $Notice)
    $metadataMarker = "`n<!-- agent_version:"
    $metadataIndex = $Body.IndexOf($metadataMarker, [System.StringComparison]::Ordinal)
    if ($metadataIndex -lt 0) { return $Body + "`n`n$Notice" }
    return $Body.Substring(0, $metadataIndex) + "`n$Notice" + $Body.Substring($metadataIndex)
}

# ---------------------------------------------------------------------------
# Duplicate detection
# ---------------------------------------------------------------------------
function Get-CommentDomainMetadataKey {
    param([string] $Body)

    $bodyValue = $Body ?? ''
    if ($bodyValue -match '<!-- agent_domain_key:\s*([A-Za-z0-9_-]+)\s*-->') {
        return [pscustomobject]@{ Kind = 'Exact'; Key = $Matches[1] }
    }

    # Legacy comments used lowercased single-token metadata or headings.
    # Keep that lossy comparison isolated from exact metadata emitted today.
    if ($bodyValue -match '<!-- agent_domain:\s*([A-Za-z0-9_-]+)\s*-->') {
        return [pscustomobject]@{
            Kind = 'Legacy'
            Key = ConvertTo-LegacyDomainKey -Domain $Matches[1]
        }
    }

    $newHeadingPattern = '^#{1,6}\s+(?:🔴|🟠|🟡|🟢|⚪)?\s*(Critical|High|Medium|Low)\s+([A-Za-z0-9_-]+)\s+-'
    $oldHeadingPattern = '^#{1,6}\s+([A-Za-z0-9_-]+)\s+-\s+(Critical|High|Medium|Low)\s+Severity'
    if ($bodyValue -match $newHeadingPattern) {
        return [pscustomobject]@{
            Kind = 'Legacy'
            Key = ConvertTo-LegacyDomainKey -Domain $Matches[2]
        }
    }
    if ($bodyValue -match $oldHeadingPattern) {
        return [pscustomobject]@{
            Kind = 'Legacy'
            Key = ConvertTo-LegacyDomainKey -Domain $Matches[1]
        }
    }
    return $null
}

function Get-ExistingCommentKeys {
    param([string] $Domain)

    $keys = [System.Collections.Generic.HashSet[string]]::new()
    $locations = [System.Collections.Generic.List[object]]::new()
    $sourceKeys = [System.Collections.Generic.HashSet[string]]::new()
    $targetExactKey = ConvertTo-DomainMetadataKey -Domain $Domain
    $targetLegacyKey = ConvertTo-LegacyDomainKey -Domain $Domain

    foreach ($comment in (Get-ReviewComments)) {
        $body = $comment.body ?? ''
        $commentMetadata = Get-CommentDomainMetadataKey -Body $body
        if ($null -eq $commentMetadata) { continue }
        $matchesDomain = if ($commentMetadata.Kind -ceq 'Exact') {
            $commentMetadata.Key -ceq $targetExactKey
        } else {
            $commentMetadata.Key -ceq $targetLegacyKey
        }
        if (-not $matchesDomain) { continue }
        $path = $comment.path ?? ''
        $line = $comment.line ?? $comment.original_line ?? 0
        $side = $comment.side ?? 'RIGHT'
        if ($path -and $line) {
            if ($body -match '<!-- agent_source_line:\s*(\d+)\s*-->') {
                $sourceKeys.Add("${path}:$($Matches[1])") | Out-Null
                continue
            }
            $keys.Add("${path}:${line}:${side}") | Out-Null
            $locations.Add([pscustomobject]@{
                path = ($path -replace '\\', '/')
                line = [int]$line
                side = $side
            }) | Out-Null
        }
    }

    return [pscustomobject]@{ Keys = $keys; Locations = $locations; SourceKeys = $sourceKeys }
}

function Test-NearDuplicateLocation {
    param(
        [System.Collections.Generic.List[object]] $ExistingLocations,
        [string] $Path, [int] $Line, [string] $Side, [int] $Tolerance = 2
    )
    if ($null -eq $ExistingLocations -or $ExistingLocations.Count -eq 0) { return $false }
    foreach ($existing in $ExistingLocations) {
        if (($existing.path -eq $Path) -and (($existing.side ?? 'RIGHT') -eq $Side)) {
            if ([math]::Abs([int]$existing.line - $Line) -le $Tolerance) { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Post findings
# ---------------------------------------------------------------------------
function Publish-Findings {
    param([string] $Domain, [object[]] $Findings, [hashtable] $LineMaps, [hashtable] $ChangedFileSet)

    $postedInline = 0
    $postedFallback = 0

    if (-not $Findings -or $Findings.Count -eq 0) {
        return [pscustomobject]@{ inline = 0; fallback = 0 }
    }

    $existing = Get-ExistingCommentKeys -Domain $Domain
    $existingKeys = $existing.Keys
    $existingLocations = $existing.Locations
    $existingSourceKeys = $existing.SourceKeys
    if ($null -eq $existingKeys) { $existingKeys = [System.Collections.Generic.HashSet[string]]::new() }
    if ($null -eq $existingLocations) { $existingLocations = [System.Collections.Generic.List[object]]::new() }
    if ($null -eq $existingSourceKeys) { $existingSourceKeys = [System.Collections.Generic.HashSet[string]]::new() }

    foreach ($finding in ($Findings | Sort-Object @{Expression = { $SeverityOrder[$_.severity] }}, filePath, lineNumber)) {
        $filePath   = ($finding.filePath -replace '^/', '') -replace '\\', '/'
        $lineNumber = [int]$finding.lineNumber
        $location   = $null
        $locationInferred = $false

        if (-not $ChangedFileSet.ContainsKey($filePath)) {
            Write-Host "Skipping $Domain finding for non-PR file: $filePath"
            continue
        }
        if (-not (Test-GlobMatch -Filename $filePath -Pattern $ReviewApplyTo)) {
            Write-Host "Skipping $Domain finding outside REVIEW_APPLY_TO ($ReviewApplyTo): $filePath"
            continue
        }
        if ($LineMaps.ContainsKey($filePath)) {
            $location = Resolve-FindingLocation -LineMap $LineMaps[$filePath] -LineNumber $lineNumber
            if ($location) { $locationInferred = [bool]($location.inferred ?? $false) }
        }

        # Validate / re-anchor the ```suggestion``` block against the PR-head
        # file so it replaces the correct line(s). When the finding carries a
        # suggested fix we re-derive its RIGHT-side span and post the comment
        # over that span (single- or multi-line). When the fix cannot be placed
        # confidently we suppress the applicable block (Build-CommentBody falls
        # back to a manual snippet) and keep the comment at the model's anchor.
        $suppressSuggestion = $false
        $commentStartLine = 0
        $commentStartSide = ''
        if ($finding.suggestedCode) {
            $suggested = ([string]$finding.suggestedCode).TrimEnd()
            $suggLines = [string[]]@($suggested -split "`r?`n")
            $placement = $null
            $fileLines = Get-PrHeadFileLines -RelativePath $filePath
            if ($fileLines -and $suggLines.Count -gt 0) {
                $placement = Resolve-SuggestionPlacement -FileLines $fileLines -AnchorLine $lineNumber -SuggestedLines $suggLines
            }

            $placed = $false
            if ($placement) {
                $map = if ($LineMaps.ContainsKey($filePath)) { $LineMaps[$filePath] } else { @{} }
                $spanOk = $true
                for ($ln = [int]$placement.startLine; $ln -le [int]$placement.endLine; $ln++) {
                    if (-not ($map.ContainsKey($ln) -and $map[$ln].side -eq 'RIGHT')) { $spanOk = $false; break }
                }
                if ($spanOk) {
                    $location = @{ line = [int]$placement.endLine; side = 'RIGHT' }
                    $locationInferred = $false
                    if ([int]$placement.startLine -lt [int]$placement.endLine) {
                        $commentStartLine = [int]$placement.startLine
                        $commentStartSide = 'RIGHT'
                    }
                    $placed = $true
                }
            }
            if (-not $placed) {
                $suppressSuggestion = $true
                Write-Host "Suggestion for $($filePath):$lineNumber could not be anchored to the diff; posting as a manual snippet."
            }
        }

        if ($location) {
            if ($locationInferred) {
                $sourceKey = "${filePath}:${lineNumber}"
                if ($existingSourceKeys.Contains($sourceKey)) {
                    Write-Host "Skipping duplicate $Domain finding at $($filePath):$lineNumber"; continue
                }
            } else {
                $key = "$($filePath):$($location.line):$($location.side)"
                if ($existingKeys.Contains($key)) {
                    Write-Host "Skipping duplicate $Domain finding at $($filePath):$lineNumber"; continue
                }
                if (Test-NearDuplicateLocation -ExistingLocations $existingLocations -Path $filePath -Line $location.line -Side $location.side) {
                    Write-Host "Skipping near-duplicate $Domain finding at $($filePath):$lineNumber"; continue
                }
            }
        }

        $body = Build-CommentBody -Finding $finding -SuppressSuggestion:$suppressSuggestion
        if ($locationInferred) { $body = Add-CommentNotice -Body $body -Notice "<!-- agent_source_line: $lineNumber -->" }
        $otherRegionsNotice = Format-OtherRegionsNotice -Finding $finding
        if ($otherRegionsNotice) { $body = Add-CommentNotice -Body $body -Notice $otherRegionsNotice }

        try {
            if ($location) {
                $null = New-ReviewComment -Body $body -Path $filePath -Line $location.line -Side $location.side -StartLine $commentStartLine -StartSide $commentStartSide
                if ($locationInferred) {
                    $existingSourceKeys.Add("${filePath}:${lineNumber}") | Out-Null
                } else {
                    $existingKeys.Add("$($filePath):$($location.line):$($location.side)") | Out-Null
                    $existingLocations.Add([pscustomobject]@{ path = $filePath; line = [int]$location.line; side = $location.side }) | Out-Null
                }
                $postedInline++
            } else {
                $fallbackBody = Add-CommentNotice -Body $body -Notice '_Line mapping was unavailable, so this was posted as an issue comment._'
                $null = New-IssueComment -Body $fallbackBody
                $postedFallback++
            }
            Start-Sleep -Seconds $CommentDelay
        } catch {
            Write-Warning "Failed to post review comment for $filePath`:$lineNumber : $_"
            $fallbackBody = Add-CommentNotice -Body $body -Notice '_Posting this finding as an issue comment because inline comment placement failed._'
            $null = New-IssueComment -Body $fallbackBody
            $postedFallback++
        }
    }

    return [pscustomobject]@{ inline = $postedInline; fallback = $postedFallback }
}

# ---------------------------------------------------------------------------
# Summary comment upsert
# ---------------------------------------------------------------------------
function Import-FilterReport {
    # The post phase has no BCQuality plugin; it reads the report the generate
    # phase copied into the review-output artifact.
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ReviewPhase -eq 'post') {
        if ($ReviewOutputDir) { $candidates.Add((Join-Path $ReviewOutputDir '_filter-report.json')) }
    } else {
        if ($BCQualityRoot)   { $candidates.Add((Join-Path $BCQualityRoot '_filter-report.json')) }
        if ($ReviewOutputDir) { $candidates.Add((Join-Path $ReviewOutputDir '_filter-report.json')) }
    }
    foreach ($path in $candidates) {
        if (Test-Path $path) {
            try {
                return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            } catch {
                Write-Warning "Could not parse filter report at $path : $($_.Exception.Message)"
                return $null
            }
        }
    }
    return $null
}

function Build-SummaryBody {
    param(
        [string] $Outcome, [string] $OutcomeReason,
        [System.Collections.IDictionary] $DomainSummary,
        [object[]] $Suppressed,
        [object[]] $SkippedSubSkills,
        [object[]] $FailedSubSkills,
        [object] $FilterReport
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($SummaryMarker) | Out-Null
    $lines.Add("<!-- agent_review_iteration: $ReviewIteration -->") | Out-Null
    $lines.Add((Get-AgentVersionMetadata)) | Out-Null
    $lines.Add((Get-AgentLabelMetadata)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Copilot PR Review') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("Iteration **$ReviewIteration** · Outcome: **$Outcome**") | Out-Null
    if ($OutcomeReason) {
        $lines.Add('') | Out-Null
        $lines.Add("> $OutcomeReason") | Out-Null
    }

    $repoUrl = Get-BCQualityRepoUrl
    $refForLinks = "v$BCQualityVersion"
    if ($repoUrl) {
        $lines.Add('') | Out-Null
        $lines.Add("Knowledge source: [$repoUrl@$refForLinks]($repoUrl/tree/$refForLinks)") | Out-Null
    }

    if ($Outcome -in @('not-applicable', 'no-knowledge')) {
        $lines.Add('') | Out-Null
        $lines.Add('No findings were posted for this iteration.') | Out-Null
    }

    if ($DomainSummary -and $DomainSummary.Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('### Findings by domain') | Out-Null
        $lines.Add('') | Out-Null
        $lines.Add('Findings split into **Knowledge-backed** (cite a BCQuality article) and **Agent** (the agent''s own judgement, no matching BCQuality rule).') | Out-Null
        $lines.Add('') | Out-Null
        $lines.Add('| Domain | Findings | Knowledge-backed | Agent | Inline | Fallback |') | Out-Null
        $lines.Add('|---|---:|---:|---:|---:|---:|') | Out-Null
        $totalBacked = 0
        $totalAgent  = 0
        foreach ($d in (Get-OrdinalSortedKey -Dictionary $DomainSummary)) {
            $entry = $DomainSummary[$d]
            $backed = if ($entry.ContainsKey('knowledgeBacked')) { [int]$entry.knowledgeBacked } else { [int]$entry.findings }
            $agent  = if ($entry.ContainsKey('agentFindings'))   { [int]$entry.agentFindings }   else { 0 }
            $totalBacked += $backed
            $totalAgent  += $agent
            $safeDomain = ConvertTo-MarkdownTableCell -Value ([string]$d)
            $lines.Add("| $safeDomain | $($entry.findings) | $backed | $agent | $($entry.inline) | $($entry.fallback) |") | Out-Null
        }
        if (($totalBacked + $totalAgent) -gt 0) {
            $lines.Add('') | Out-Null
            $lines.Add("Totals: **$totalBacked** knowledge-backed · **$totalAgent** agent findings.") | Out-Null
        }
    }

    if ($Suppressed -and $Suppressed.Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('### Knowledge files suppressed by layer precedence or configuration') | Out-Null
        foreach ($s in $Suppressed) {
            $lines.Add("- $($s.path) — $($s.reason)") | Out-Null
        }
    }

    if ($SkippedSubSkills -and $SkippedSubSkills.Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('### Sub-skills skipped') | Out-Null
        foreach ($s in $SkippedSubSkills) {
            $lines.Add("- $($s.id) — $($s.reason)") | Out-Null
        }
    }

    if ($FailedSubSkills -and $FailedSubSkills.Count -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add('### Sub-skills failed — review coverage is incomplete') | Out-Null
        $lines.Add('') | Out-Null
        $lines.Add('| Sub-skill | Reported failure |') | Out-Null
        $lines.Add('|---|---|') | Out-Null
        foreach ($s in $FailedSubSkills) {
            $safeId = ConvertTo-MarkdownTableCell -Value ([string]$s.id)
            $reason = if ($s.reason) { [string]$s.reason } else { 'Failed without a report-provided explanation; see the run manifest for process details.' }
            $safeReason = ConvertTo-MarkdownTableCell -Value $reason
            $lines.Add("| $safeId | $safeReason |") | Out-Null
        }
    }

    if ($FilterReport -and $FilterReport.removedCount -gt 0) {
        $lines.Add('') | Out-Null
        $lines.Add("### Orchestrator pre-filter ($($FilterReport.removedCount) file(s) excluded)") | Out-Null
        $byReason = @{}
        foreach ($r in $FilterReport.removed) {
            $key = "$($r.reason) ($($r.kind))"
            if (-not $byReason.ContainsKey($key)) { $byReason[$key] = 0 }
            $byReason[$key] = $byReason[$key] + 1
        }
        foreach ($k in ($byReason.Keys | Sort-Object)) {
            $lines.Add("- $k : $($byReason[$k]) file(s)") | Out-Null
        }
    }

    $lines.Add('') | Out-Null
    $lines.Add("<sub>Findings produced by the AL review agent v$AgentVersion. Reply 👎 on any inline comment to flag false positives.</sub>") | Out-Null
    return $lines -join "`n"
}

function Set-SummaryComment {
    param([string] $Body)

    $existing = $null
    foreach ($comment in (Get-IssueComments)) {
        if (($comment.body ?? '') -match [regex]::Escape($SummaryMarker)) { $existing = $comment; break }
    }

    if ($existing) {
        $null = Update-IssueComment -CommentId $existing.id -Body $Body
        Write-Host "Updated PR summary comment (id $($existing.id))"
    } else {
        $null = New-IssueComment -Body $Body
        Write-Host 'Posted PR summary comment'
    }
}
