# ---------------------------------------------------------------------------
# Patch line map (for placing inline review comments)
# ---------------------------------------------------------------------------
function Build-LineMap {
    param([string] $Patch)

    $map      = @{}   # Numeric RIGHT keys and namespaced LEFT keys keep both coordinates.
    $oldLine  = 0
    $newLine  = 0
    $newStart = 0
    $newEnd   = 0

    foreach ($raw in ($Patch -split "`n")) {
        if ($raw -match '^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@') {
            $oldLine = [int]$Matches[1]
            $newStart = [int]$Matches[2]
            $newLine = $newStart
            $newCount = if ($Matches[3]) { [int]$Matches[3] } else { 1 }
            $newEnd = $newStart + $newCount - 1
            continue
        }
        if ($raw.StartsWith('+') -and -not $raw.StartsWith('+++')) {
            if (-not $map.ContainsKey($newLine)) {
                $map[$newLine] = @{
                    line = $newLine; side = 'RIGHT'
                    newStart = $newStart; newEnd = $newEnd
                }
            }
            $newLine++; continue
        }
        if ($raw.StartsWith('-') -and -not $raw.StartsWith('---')) {
            $oldKey = "LEFT:$oldLine"
            if (-not $map.ContainsKey($oldKey)) {
                $map[$oldKey] = @{
                    line = $oldLine; side = 'LEFT'
                    newStart = $newStart; newEnd = $newEnd; deletionPosition = $newLine
                }
            }
            $oldLine++; continue
        }
        if ($raw.StartsWith('\')) { continue }
        $oldLine++; $newLine++
    }

    return $map
}

function Resolve-FindingLocation {
    param([hashtable] $LineMap, [int] $LineNumber)

    if (-not $LineMap -or $LineMap.Count -eq 0) { return $null }
    if ($LineMap.ContainsKey($LineNumber) -and $LineMap[$LineNumber].side -eq 'RIGHT') {
        $exact = $LineMap[$LineNumber]
        return @{ line = [int]$exact.line; side = $exact.side; inferred = $false }
    }

    $locations = @($LineMap.Values)
    $sameHunkRight = @($locations | Where-Object {
        $_.side -eq 'RIGHT' -and $LineNumber -ge $_.newStart -and $LineNumber -le $_.newEnd
    })
    if ($sameHunkRight.Count -gt 0) {
        $nearest = $sameHunkRight |
            Sort-Object @{ Expression = { [Math]::Abs([int]$_.line - $LineNumber) } }, line |
            Select-Object -First 1
        return @{ line = [int]$nearest.line; side = $nearest.side; inferred = $true }
    }

    $sameHunkLeft = @($locations | Where-Object {
        $_.side -eq 'LEFT' -and $LineNumber -ge $_.newStart -and $LineNumber -le $_.newEnd
    })
    if ($sameHunkLeft.Count -gt 0) {
        $nearest = $sameHunkLeft |
            Sort-Object @{ Expression = { [Math]::Abs([int]$_.deletionPosition - $LineNumber) } }, line |
            Select-Object -First 1
        return @{ line = [int]$nearest.line; side = $nearest.side; inferred = $true }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Suggestion placement (anchor validation for ```suggestion``` blocks)
#
# A GitHub suggestion block replaces *exactly* the line(s) its comment is
# anchored to. The model reports a single semantic `location.line` for a
# finding, which often is not the line (or full span) the suggested code is
# meant to replace — e.g. it anchors a procedure declaration while the fix
# rewrites a statement two lines below, or anchors one line of a multi-line
# field while the suggestion is the whole field plus an inserted property.
# Posting such a suggestion verbatim corrupts the file when applied. These
# helpers re-derive the correct RIGHT-side span by matching the suggested
# code against the actual PR-head file content, so the block lands in place.
# ---------------------------------------------------------------------------

# Cache of PR-head file contents (relative path -> string[] lines) so a file is
# read at most once across all of its findings.
$script:PrHeadFileCache = @{}

function Get-PrHeadFileLines {
    param([string] $RelativePath)

    if ($script:PrHeadFileCache.ContainsKey($RelativePath)) {
        return $script:PrHeadFileCache[$RelativePath]
    }

    $lines = $null
    $full = Join-Path $AnalysisWorkspace $RelativePath
    if (Test-Path -LiteralPath $full) {
        try {
            $lines = @(Get-Content -LiteralPath $full -ErrorAction Stop)
        } catch {
            Write-Warning "Could not read PR-head file for suggestion placement: $RelativePath ($_)"
            $lines = $null
        }
    }

    $script:PrHeadFileCache[$RelativePath] = $lines
    return $lines
}

# Whitespace-insensitive comparison key. Indentation and inter-token spacing
# frequently differ between the suggested fix and the original line (the fix is
# often *about* whitespace, e.g. 'exit (X)' -> 'exit(X)'), so boundary/context
# matching collapses all whitespace to find the line a fix corresponds to.
function ConvertTo-LooseLine {
    param([string] $Line)
    if ($null -eq $Line) { return '' }
    return ($Line -replace '\s+', '')
}

function Test-OrderedSubsequence {
    param([string[]] $FileSpan, [string[]] $Suggestion)

    $suggestionLines = @($Suggestion | ForEach-Object { ConvertTo-LooseLine $_ })
    $suggestionIndex = 0
    foreach ($fileLine in $FileSpan) {
        $fileLoose = ConvertTo-LooseLine $fileLine
        $found = $false
        while ($suggestionIndex -lt $suggestionLines.Count) {
            $current = $suggestionLines[$suggestionIndex]
            $suggestionIndex++
            if ($current -eq $fileLoose) { $found = $true; break }
        }
        if (-not $found) { return $false }
    }
    return $true
}

function Test-LooseMultisetEqual {
    param([string[]] $A, [string[]] $B)

    if ($A.Count -ne $B.Count) { return $false }
    $bag = @{}
    foreach ($line in $A) {
        $key = ConvertTo-LooseLine $line
        $bag[$key] = [int]$bag[$key] + 1
    }
    foreach ($line in $B) {
        $key = ConvertTo-LooseLine $line
        if (-not $bag.ContainsKey($key)) { return $false }
        $bag[$key] = [int]$bag[$key] - 1
        if ($bag[$key] -lt 0) { return $false }
    }
    return $true
}

function Test-SuggestionReusesOutsideSpan {
    param(
        [string[]] $FileLines,
        [int] $SearchStart,
        [int] $SearchEnd,
        [int] $SpanStart,
        [int] $SpanEnd,
        [string[]] $Suggestion
    )

    $remaining = @{}
    foreach ($line in $Suggestion) {
        $key = ConvertTo-LooseLine $line
        $remaining[$key] = [int]$remaining[$key] + 1
    }
    for ($line = $SpanStart; $line -le $SpanEnd; $line++) {
        $key = ConvertTo-LooseLine $FileLines[$line - 1]
        if ($remaining.ContainsKey($key)) {
            $remaining[$key] = [int]$remaining[$key] - 1
        }
    }
    for ($line = $SearchStart; $line -le $SearchEnd; $line++) {
        if ($line -ge $SpanStart -and $line -le $SpanEnd) { continue }
        $key = ConvertTo-LooseLine $FileLines[$line - 1]
        if ($remaining.ContainsKey($key) -and $remaining[$key] -gt 0) { return $true }
    }
    return $false
}

function Select-SuggestionSpan {
    param([object[]] $Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }
    $ranked = @($Candidates | Sort-Object `
        @{ Expression = 'inserted'; Descending = $false },
        @{ Expression = 'containsAnchor'; Descending = $true },
        @{ Expression = 'distance'; Descending = $false },
        @{ Expression = 'startLine'; Descending = $false })
    $best = $ranked[0]
    if ($ranked.Count -gt 1) {
        $runnerUp = $ranked[1]
        if ($best.inserted -eq $runnerUp.inserted -and
            $best.containsAnchor -eq $runnerUp.containsAnchor -and
            $best.distance -eq $runnerUp.distance) {
            return $null
        }
    }
    return [pscustomobject]@{ startLine = $best.startLine; endLine = $best.endLine }
}

# Resolve the RIGHT-side file span a suggestion should replace.
# Returns @{ startLine; endLine } (1-based, inclusive) or $null when the
# suggestion cannot be placed with confidence (caller drops the block).
function Resolve-SuggestionPlacement {
    param([string[]] $FileLines, [int] $AnchorLine, [string[]] $SuggestedLines)

    if (-not $FileLines -or $FileLines.Count -eq 0) { return $null }
    if (-not $SuggestedLines -or $SuggestedLines.Count -eq 0) { return $null }

    $fileCount = $FileLines.Count
    if ($AnchorLine -lt 1) { $AnchorLine = 1 }
    if ($AnchorLine -gt $fileCount) { $AnchorLine = $fileCount }

    $sCount    = $SuggestedLines.Count
    $firstLoose = ConvertTo-LooseLine $SuggestedLines[0]
    $lastLoose = ConvertTo-LooseLine $SuggestedLines[$sCount - 1]
    $suggestionIsComment = $firstLoose -match '^(//|/\*|\*)'
    $anchorLoose = ConvertTo-LooseLine $FileLines[$AnchorLine - 1]
    $anchorIsComment = $anchorLoose -match '^(//|/\*|\*)'
    $anchorCanBeReplaced = $anchorLoose -and ($anchorIsComment -eq $suggestionIsComment)

    # A changed single-line suggestion cannot be placed safely without the
    # original source line. Fail closed instead of guessing from similarity.
    if ($sCount -eq 1) {
        if ($firstLoose -and $anchorLoose -eq $firstLoose) {
            return [pscustomobject]@{ startLine = $AnchorLine; endLine = $AnchorLine }
        }
        return $null
    }

    # --- Multi-line suggestion: first cover a complete same-length reorder. ---
    $reorderCandidates = @()
    $lo = [math]::Max(1, $AnchorLine - $sCount)
    $hi = [math]::Min($fileCount - $sCount + 1, $AnchorLine + $sCount)
    for ($s = $lo; $s -le $hi; $s++) {
        $e = $s + $sCount - 1
        if ($AnchorLine -lt ($s - 1) -or $AnchorLine -gt ($e + 1)) { continue }
        $span = @($FileLines[($s - 1)..($e - 1)])
        if (Test-LooseMultisetEqual -A $span -B $SuggestedLines) {
            $containsAnchor = $AnchorLine -ge $s -and $AnchorLine -le $e
            if (-not $containsAnchor -and $anchorCanBeReplaced) { continue }
            $distance = if ($AnchorLine -lt $s) { $s - $AnchorLine } elseif ($AnchorLine -gt $e) { $AnchorLine - $e } else { 0 }
            $reorderCandidates += [pscustomobject]@{
                startLine = $s; endLine = $e; inserted = 0
                containsAnchor = $containsAnchor; distance = $distance
            }
        }
    }
    if ($reorderCandidates.Count -gt 0) {
        return Select-SuggestionSpan -Candidates $reorderCandidates
    }

    # Then cover ordinary insertions that preserve source-line order.
    $additiveCandidates = @()
    $lo = [math]::Max(1, $AnchorLine - $sCount - 4)
    $hi = [math]::Min($fileCount, $AnchorLine + $sCount + 4)
    for ($s = $lo; $s -le $hi; $s++) {
        if ((ConvertTo-LooseLine $FileLines[$s - 1]) -ne $firstLoose) { continue }
        $eMax = [math]::Min($fileCount, $s + $sCount - 1)
        for ($e = $s; $e -le $eMax; $e++) {
            if ((ConvertTo-LooseLine $FileLines[$e - 1]) -ne $lastLoose) { continue }
            if ($AnchorLine -lt ($s - 1) -or $AnchorLine -gt ($e + 1)) { continue }
            $span = @($FileLines[($s - 1)..($e - 1)])
            if (-not (Test-OrderedSubsequence -FileSpan $span -Suggestion $SuggestedLines)) { continue }
            if (Test-SuggestionReusesOutsideSpan -FileLines $FileLines -SearchStart $lo -SearchEnd $hi `
                    -SpanStart $s -SpanEnd $e -Suggestion $SuggestedLines) { continue }
            $containsAnchor = $AnchorLine -ge $s -and $AnchorLine -le $e
            if (-not $containsAnchor -and $anchorCanBeReplaced) { continue }
            $distance = if ($AnchorLine -lt $s) { $s - $AnchorLine } elseif ($AnchorLine -gt $e) { $AnchorLine - $e } else { 0 }
            $additiveCandidates += [pscustomobject]@{
                startLine = $s; endLine = $e; inserted = $sCount - ($e - $s + 1)
                containsAnchor = $containsAnchor; distance = $distance
            }
        }
    }

    return Select-SuggestionSpan -Candidates $additiveCandidates
}

function Test-GlobMatch {
    param([string] $Filename, [string] $Pattern)
    $f = $Filename -replace '\\', '/'
    $p = $Pattern -replace '\\', '/'
    # Collapse both `**/` and a bare trailing `**` (e.g. `src/**`) to `*`.
    $likePattern = $p -replace '\*\*/?', '*'
    return $f -like $likePattern
}
