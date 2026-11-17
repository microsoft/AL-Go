$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Get-CoverageArray {
    <#
    .SYNOPSIS
        Normalizes a coverage value to an array.
    .PARAMETER Value
        Coverage value that must be an enumerable collection or null.
    #>
    Param($Value)

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Expected an array."
    }
    return @($Value)
}

function Test-PathInsideRoot {
    <#
    .SYNOPSIS
        Tests whether a path is contained by a root path.
    .PARAMETER Path
        Path to test.
    .PARAMETER Root
        Root directory that must contain the path.
    #>
    Param(
        [string] $Path,
        [string] $Root
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
        $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else {
            [System.StringComparison]::Ordinal
        }
        if ($fullPath.Equals($fullRoot, $comparison)) {
            return $true
        }
        $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
        return $fullPath.StartsWith($prefix, $comparison)
    }
    catch {
        return $false
    }
}

function Get-NormalizedCoverageSourceRoots {
    <#
    .SYNOPSIS
        Returns validated, deduplicated coverage source roots.
    .PARAMETER RepositoryRoot
        Absolute repository root containing the configured source roots.
    .PARAMETER SourceRoots
        Repository-relative source-root paths from coverage metadata.
    #>
    Param(
        [string] $RepositoryRoot,
        [string[]] $SourceRoots
    )

    $repositoryPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath)
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $result = @()
    foreach ($sourceRoot in $SourceRoots) {
        $relative = "$sourceRoot".Trim().Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($relative) -or -not $seen.Add($relative)) {
            continue
        }

        $entry = @{
            Relative = $relative
            FullPath = ""
            Name = @($relative -split '/')[-1]
            Valid = $false
        }
        if (-not [System.IO.Path]::IsPathRooted($relative) -and
            $relative -notmatch '(^|/)\.\.(/|$)') {
            $candidate = Join-Path $repositoryPath $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            if ((Test-Path -LiteralPath $candidate -PathType Container)) {
                $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).ProviderPath)
                if (Test-PathInsideRoot -Path $resolved -Root $repositoryPath) {
                    $entry.FullPath = $resolved
                    $entry.Valid = $true
                }
            }
        }
        $result += $entry
    }
    return @($result)
}

function Resolve-ExistingCoverageSource {
    <#
    .SYNOPSIS
        Resolves an existing source file beneath the repository and source root.
    .PARAMETER Candidate
        Candidate source-file path.
    .PARAMETER RepositoryRoot
        Absolute repository root that must contain the source file.
    .PARAMETER SourceRoot
        Optional source root that must also contain the source file.
    #>
    Param(
        [string] $Candidate,
        [string] $RepositoryRoot,
        [AllowEmptyString()][string] $SourceRoot = ""
    )

    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        return $null
    }
    $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Candidate).ProviderPath)
    if (-not (Test-PathInsideRoot -Path $resolved -Root $RepositoryRoot)) {
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot) -and
        -not (Test-PathInsideRoot -Path $resolved -Root $SourceRoot)) {
        return $null
    }
    $identity = $resolved.Substring($RepositoryRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/').ToLowerInvariant()
    return @{
        Included = $true
        Identity = $identity
    }
}

function Read-BcCoverageReport {
    <#
    .SYNOPSIS
        Parses and validates a Business Central coverage schema 1.0 report.
    .PARAMETER Path
        Path to the BC JSON coverage report.
    .PARAMETER Model
        Coverage metadata containing source-root paths and application attribution.
    .PARAMETER RepositoryRoot
        Absolute repository root used to resolve source paths.
    .PARAMETER SemanticLineUnion
        Aggregate dictionary updated with executable-line coverage facts.
    .PARAMETER SourceMappingCache
        Optional shared cache of report source paths and their repository mappings.
    #>
    Param(
        [string] $Path,
        [hashtable] $Model,
        [string] $RepositoryRoot,
        [hashtable] $SemanticLineUnion,
        [System.Collections.Generic.Dictionary[string,object]] $SourceMappingCache = $null
    )

    $file = Get-Item -LiteralPath $Path
    $extractedLineCount = 0
    $newLineCount = 0
    $sourceCache = if ($null -ne $SourceMappingCache) {
        $SourceMappingCache
    }
    else {
        [System.Collections.Generic.Dictionary[string,object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }
    $normalizedRepositoryRoot = [System.IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
    ).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $normalizedSourceRoots = @(
        Get-NormalizedCoverageSourceRoots -RepositoryRoot $normalizedRepositoryRoot `
            -SourceRoots $Model.SourceRoots
    )
    $reportData = @{
        schemaVersion = $null
        coverageMode = $null
        complete = $null
        diagnostics = @()
    }
    $requiredRootProperties = @(
        "schemaVersion", "coverageMode", "complete", "diagnostics", "sources",
        "tests", "procedureEdges", "methods", "lines"
    )
    $seenRootProperties = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )

    try {
        $fileStream = $null
        $textReader = $null
        $jsonReader = $null
        try {
            $fileStream = [System.IO.FileStream]::new(
                    $file.FullName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::Read,
                    65536,
                    [System.IO.FileOptions]::SequentialScan)
                $textReader = [System.IO.StreamReader]::new(
                    $fileStream,
                    [System.Text.Encoding]::UTF8,
                    $true,
                    65536,
                    $false)
                $jsonReader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
                if (-not $jsonReader.Read() -or
                    $jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartObject) {
                    throw [System.IO.InvalidDataException]::new("corrupt")
                }

                $rootComplete = $false
                while ($jsonReader.Read()) {
                    if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndObject -and
                        $jsonReader.Depth -eq 0) {
                        $rootComplete = $true
                        break
                    }
                    if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::PropertyName -or
                        $jsonReader.Depth -ne 1) {
                        throw [System.IO.InvalidDataException]::new("corrupt")
                    }

                    $propertyName = "$($jsonReader.Value)"
                    if (-not $jsonReader.Read()) {
                        throw [System.IO.InvalidDataException]::new("corrupt")
                    }
                    if ($propertyName -cnotin $requiredRootProperties) {
                        if ($jsonReader.TokenType -in @(
                                [Newtonsoft.Json.JsonToken]::StartArray,
                                [Newtonsoft.Json.JsonToken]::StartObject)) {
                            $jsonReader.Skip()
                        }
                        continue
                    }
                    if (-not $seenRootProperties.Add($propertyName)) {
                        throw [System.IO.InvalidDataException]::new("shape")
                    }

                    switch -CaseSensitive ($propertyName) {
                        "schemaVersion" {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::String) {
                                throw [System.IO.InvalidDataException]::new("schema")
                            }
                            $reportData.schemaVersion = "$($jsonReader.Value)"
                        }
                        "coverageMode" {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::String) {
                                throw [System.IO.InvalidDataException]::new("mode")
                            }
                            $reportData.coverageMode = "$($jsonReader.Value)"
                        }
                        "complete" {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::Boolean) {
                                throw [System.IO.InvalidDataException]::new("complete")
                            }
                            $reportData.complete = [bool]$jsonReader.Value
                        }
                        "diagnostics" {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartArray) {
                                throw [System.IO.InvalidDataException]::new("shape")
                            }
                            $diagnostics = @()
                            while ($jsonReader.Read()) {
                                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndArray) {
                                    break
                                }
                                if ($jsonReader.TokenType -in @(
                                        [Newtonsoft.Json.JsonToken]::StartArray,
                                        [Newtonsoft.Json.JsonToken]::StartObject)) {
                                    $token = [Newtonsoft.Json.Linq.JToken]::ReadFrom($jsonReader)
                                    $diagnostics += $token.ToString([Newtonsoft.Json.Formatting]::None)
                                }
                                else {
                                    $diagnostics += "$($jsonReader.Value)"
                                }
                            }
                            $reportData.diagnostics = @($diagnostics)
                        }
                        { $_ -in @("sources", "tests", "methods", "procedureEdges") } {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartArray) {
                                throw [System.IO.InvalidDataException]::new("shape")
                            }
                            $jsonReader.Skip()
                        }
                        "lines" {
                            if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartArray) {
                                throw [System.IO.InvalidDataException]::new("shape")
                            }
                            while ($jsonReader.Read()) {
                                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndArray) {
                                    break
                                }
                                if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartObject) {
                                    throw [System.IO.InvalidDataException]::new("shape")
                                }
                                $line = [Newtonsoft.Json.Linq.JObject]::Load($jsonReader)
                                try {
                                    $objectType = [int]$line["objectType"]
                                    $objectId = [int]$line["objectId"]
                                    $lineNumber = [int]$line["lineNumber"]
                                    $lineType = [int]$line["lineType"]
                                    $hitCount = [int]$line["hitCount"]
                                    $sourcePath = [string]$line["sourcePath"]
                                }
                                catch {
                                    throw [System.IO.InvalidDataException]::new("shape")
                                }
                                $extractedLineCount++
                                if ($lineType -ne 3) {
                                    continue
                                }

                                $source = $null
                                if (-not $sourceCache.TryGetValue($sourcePath, [ref]$source)) {
                                    $source = Resolve-NormalizedRepositoryCoverageSource `
                                        -SourcePath $sourcePath `
                                        -RepositoryRoot $normalizedRepositoryRoot `
                                        -NormalizedRoots $normalizedSourceRoots
                                    if ($source.Included) {
                                        $detail = $Model.SourceRootDetails[[int]$source.SourceRootIndex]
                                        $source.AppRootIdentity = ""
                                        if ($detail -and "$($detail.Kind)" -eq "app") {
                                            $source.AppRootIdentity = "$($detail.Identity)"
                                        }
                                    }
                                    $sourceCache[$sourcePath] = $source
                                }
                                if ($source.Included) {
                                    $rootIdentity = "$($source.AppRootIdentity)"
                                    if (-not [string]::IsNullOrWhiteSpace($rootIdentity)) {
                                        $factKey = "$($source.Identity)|$objectType|$objectId|$lineNumber"
                                        if (-not $SemanticLineUnion.ContainsKey($rootIdentity)) {
                                            $SemanticLineUnion[$rootIdentity] =
                                                [System.Collections.Generic.Dictionary[string,bool]]::new(
                                                    [System.StringComparer]::Ordinal)
                                        }
                                        $rootLines = $SemanticLineUnion[$rootIdentity]
                                        if (-not $rootLines.ContainsKey($factKey)) {
                                            $newLineCount++
                                            $rootLines.Add($factKey, $hitCount -gt 0)
                                        }
                                        elseif ($hitCount -gt 0) {
                                            $rootLines[$factKey] = $true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (-not $rootComplete -or $jsonReader.Read()) {
                    throw [System.IO.InvalidDataException]::new("corrupt")
                }
        }
        finally {
            if ($jsonReader) {
                $jsonReader.Dispose()
            }
            if ($textReader) {
                $textReader.Dispose()
            }
            if ($fileStream) {
                $fileStream.Dispose()
            }
        }

        foreach ($propertyName in $requiredRootProperties) {
            if (-not $seenRootProperties.Contains($propertyName)) {
                $failureKind = if ($propertyName -eq "schemaVersion") { "schema" }
                    elseif ($propertyName -eq "coverageMode") { "mode" }
                    elseif ($propertyName -eq "complete") { "complete" }
                    else { "shape" }
                throw [System.IO.InvalidDataException]::new($failureKind)
            }
        }
        if ("$($reportData.schemaVersion)" -ne "1.0") {
            throw [System.IO.InvalidDataException]::new("schema")
        }
        if ("$($reportData.coverageMode)" -ne "line") {
            throw [System.IO.InvalidDataException]::new("mode")
        }

        return @{
            Data = $reportData
            ExtractedLineCount = $extractedLineCount
            NewLineCount = $newLineCount
        }
    }
    catch {
        $failureKind = if ($_.Exception -is [System.IO.InvalidDataException]) {
            "$($_.Exception.Message)"
        }
        else {
            "corrupt"
        }
        $reason = switch ($failureKind) {
            "schema" { "Coverage report schemaVersion is not supported." }
            "mode" { "Coverage report mode is not supported." }
            "complete" { "Coverage report completeness value is invalid." }
            "shape" { "Coverage report does not match schemaVersion 1.0." }
            default { "Coverage report JSON is corrupt or invalid." }
        }
        throw $reason
    }
}

function Resolve-NormalizedRepositoryCoverageSource {
    <#
    .SYNOPSIS
        Maps a coverage source to its normalized repository-relative identity.
    .PARAMETER SourcePath
        Source path emitted by AlTool.
    .PARAMETER RepositoryRoot
        Absolute repository root used for source validation.
    .PARAMETER NormalizedRoots
        Validated source-root records returned by Get-NormalizedCoverageSourceRoots.
    #>
    Param(
        [AllowEmptyString()][string] $SourcePath,
        [AllowEmptyString()][string] $RepositoryRoot,
        [object[]] $NormalizedRoots
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return @{ Included = $false }
    }
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return @{ Included = $false }
    }
    try {
        $normalizedSource = $SourcePath.Trim().Replace('\', '/')

        if ([System.IO.Path]::IsPathRooted($SourcePath)) {
            $fullSource = [System.IO.Path]::GetFullPath($SourcePath)
            for ($rootIndex = 0; $rootIndex -lt $NormalizedRoots.Count; $rootIndex++) {
                $sourceRoot = $NormalizedRoots[$rootIndex]
                if ($sourceRoot.Valid -and
                    (Test-PathInsideRoot -Path $fullSource -Root $sourceRoot.FullPath)) {
                    $resolved = Resolve-ExistingCoverageSource -Candidate $fullSource `
                        -RepositoryRoot $RepositoryRoot -SourceRoot $sourceRoot.FullPath
                    if ($resolved) {
                        $resolved.SourceRootIndex = $rootIndex
                        return $resolved
                    }
                }
            }
            $rootIndexes = if ($NormalizedRoots.Count -gt 0) {
                @(0..($NormalizedRoots.Count - 1) |
                    Sort-Object { $NormalizedRoots[$_].Relative.Length } -Descending)
            }
            else {
                @()
            }
            foreach ($rootIndex in $rootIndexes) {
                $sourceRoot = $NormalizedRoots[$rootIndex]
                $marker = "/$($sourceRoot.Relative)/"
                $markerIndex = $normalizedSource.IndexOf(
                    $marker, [System.StringComparison]::OrdinalIgnoreCase)
                if ($sourceRoot.Valid -and $markerIndex -ge 0) {
                    $relative = $normalizedSource.Substring($markerIndex + $marker.Length)
                    $candidate = Join-Path $sourceRoot.FullPath `
                        $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                    $resolved = Resolve-ExistingCoverageSource -Candidate $candidate `
                        -RepositoryRoot $RepositoryRoot -SourceRoot $sourceRoot.FullPath
                    if ($resolved) {
                        $resolved.SourceRootIndex = $rootIndex
                        return $resolved
                    }
                    return @{ Included = $false }
                }
            }
            return @{ Included = $false }
        }

        $relativeSource = $normalizedSource.TrimStart('/')
        if ($relativeSource -match '(^|/)\.\.(/|$)') {
            return @{ Included = $false }
        }
        if ($relativeSource -match '^external-([0-9]+)/(.+)$') {
            $rootIndex = [int]$matches[1]
            $externalPath = $matches[2]
            if ($rootIndex -le 0 -or $rootIndex -ge $NormalizedRoots.Count) {
                return @{ Included = $false }
            }
            $separatorIndex = $externalPath.IndexOf('/')
            if ($separatorIndex -le 0 -or $separatorIndex -eq $externalPath.Length - 1) {
                return @{ Included = $false }
            }
            $rootName = $externalPath.Substring(0, $separatorIndex)
            $rootRelativePath = $externalPath.Substring($separatorIndex + 1)
            $sourceRoot = $NormalizedRoots[$rootIndex]
            if (-not $sourceRoot.Valid -or
                -not $rootName.Equals(
                    $sourceRoot.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return @{ Included = $false }
            }
            $candidate = Join-Path $sourceRoot.FullPath `
                $rootRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $resolved = Resolve-ExistingCoverageSource -Candidate $candidate `
                -RepositoryRoot $RepositoryRoot -SourceRoot $sourceRoot.FullPath
            if ($resolved) {
                $resolved.SourceRootIndex = $rootIndex
                return $resolved
            }
            return @{ Included = $false }
        }

        if ($NormalizedRoots.Count -eq 0) {
            return @{ Included = $false }
        }
        $primaryRoot = $NormalizedRoots[0]
        if (-not $primaryRoot.Valid) {
            return @{ Included = $false }
        }
        $candidate = Join-Path $primaryRoot.FullPath `
            $relativeSource.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $resolved = Resolve-ExistingCoverageSource -Candidate $candidate `
            -RepositoryRoot $RepositoryRoot -SourceRoot $primaryRoot.FullPath
        if ($resolved) {
            $resolved.SourceRootIndex = 0
            return $resolved
        }
        return @{ Included = $false }
    }
    catch {
        return @{ Included = $false }
    }
}

Export-ModuleMember -Function Get-CoverageArray,
    Test-PathInsideRoot, Get-NormalizedCoverageSourceRoots,
    Resolve-ExistingCoverageSource, Resolve-NormalizedRepositoryCoverageSource,
    Read-BcCoverageReport
