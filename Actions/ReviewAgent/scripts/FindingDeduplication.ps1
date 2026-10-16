# ---------------------------------------------------------------------------
# Regional duplicate collapsing (same code across W1 + country layers)
# ---------------------------------------------------------------------------
# Business Central ships the same or near-identical code in multiple regional
# copies (the W1 base layer plus country layers such as US / BE / DE, laid out
# under both src/Apps/<region>/ and src/Layers/<region>/). When a change touches
# several copies, the identical finding lands on each regional file. Rather than
# posting N identical comments (noise) or silently dropping the country copies
# (the author is never told to fix them), we collapse an identical finding that
# spans >=2 regions into ONE comment on a primary location (prefer W1) and list
# the other affected regional files in that comment's body. Findings whose
# content actually differs keep distinct signatures and are never collapsed.

function Get-RegionalPathInfo {
    param([string] $FilePath)

    $normalized = ((($FilePath ?? '') -replace '\\', '/') -replace '^/', '')
    if ($normalized -match '(?i)^src/(apps|layers)/([^/]+)/(.+)$') {
        return [pscustomobject]@{
            Tree     = $Matches[1].ToLowerInvariant()
            Region   = $Matches[2].ToLowerInvariant()
            Relative = $Matches[3]
            Path     = $normalized
        }
    }
    return $null
}

function Get-FindingOtherRegions {
    param([object] $Finding)

    if ($null -eq $Finding) { return @() }
    if ($Finding.PSObject.Properties.Match('otherRegions').Count -eq 0) { return @() }
    $value = $Finding.otherRegions
    if ($null -eq $value) { return @() }
    return @($value)
}

function Format-OtherRegionsNotice {
    param([object] $Finding)

    $others = @(Get-FindingOtherRegions -Finding $Finding)
    if ($others.Count -eq 0) { return '' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('**The same issue exists in these regional copies — apply the equivalent fix in each:**') | Out-Null
    foreach ($other in $others) {
        $label = if ($other.region) { " ($($other.region))" } else { '' }
        $lines.Add("- ``$($other.path):$($other.line)``$label") | Out-Null
    }
    return ($lines -join "`n")
}

function Group-RegionalFindings {
    param([object[]] $Findings)

    if (-not $Findings -or $Findings.Count -lt 2) { return @($Findings) }

    # Location alone cannot distinguish two defects on the same line. Only merge
    # equivalent findings, preserving differing prose, severity and suggested fixes.
    $result     = [System.Collections.Generic.List[object]]::new()
    $byLocality = [ordered]@{}

    foreach ($finding in $Findings) {
        $info = Get-RegionalPathInfo -FilePath $finding.filePath
        if ($null -eq $info) {
            $result.Add($finding) | Out-Null            # non-regional: never collapsed
            continue
        }
        $domain = ([string]$finding.domain).Trim().ToLowerInvariant()
        $line   = [int]$finding.lineNumber
        $issue = [string](Get-ObjectPropertyValue -InputObject $finding -Name 'issue')
        if ([string]::IsNullOrWhiteSpace($issue)) {
            $result.Add($finding) | Out-Null
            continue
        }
        $identity = @(
            $info.Tree
            $info.Relative
            $domain
            $line
            foreach ($name in @('rawId', 'isAgentFinding', 'issue', 'recommendation', 'severity', 'confidence', 'suggestedCode', 'suggestedCodeOmissionReason')) {
                ([string](Get-ObjectPropertyValue -InputObject $finding -Name $name)).Replace("`r`n", "`n").Trim()
            }
        )
        $key = ConvertTo-Json -InputObject $identity -Compress
        if (-not $byLocality.Contains($key)) {
            $byLocality[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $byLocality[$key].Add([pscustomobject]@{ Finding = $finding; Info = $info }) | Out-Null
    }

    foreach ($key in $byLocality.Keys) {
        $group = @($byLocality[$key])
        $distinctRegions = @($group | ForEach-Object { $_.Info.Region } | Select-Object -Unique)

        # Only collapse a genuine cross-region cluster: same location in >=2 regions.
        if ($group.Count -lt 2 -or $distinctRegions.Count -ne $group.Count) {
            foreach ($entry in $group) { $result.Add($entry.Finding) | Out-Null }
            continue
        }

        $primaryEntry = $group | Where-Object { $_.Info.Region -eq 'w1' } | Select-Object -First 1
        if (-not $primaryEntry) {
            $primaryEntry = $group | Sort-Object { $_.Info.Region }, { $_.Info.Path } | Select-Object -First 1
        }

        $otherRegions = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in ($group | Sort-Object { $_.Info.Region }, { $_.Info.Path })) {
            if ([object]::ReferenceEquals($entry, $primaryEntry)) { continue }
            $otherRegions.Add([pscustomobject]@{
                path   = $entry.Info.Path
                line   = [int]$entry.Finding.lineNumber
                region = $entry.Info.Region.ToUpperInvariant()
            }) | Out-Null
        }

        $primaryFinding = $primaryEntry.Finding
        Add-Member -InputObject $primaryFinding -NotePropertyName 'otherRegions' -NotePropertyValue @($otherRegions) -Force
        $result.Add($primaryFinding) | Out-Null
    }

    return @($result)
}
