$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Get-CoverageArray {
    <#
    .SYNOPSIS
        Normalizes a coverage value to an array.
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

function ConvertTo-CoverageSourceIdentity {
    <#
    .SYNOPSIS
        Normalizes a report source path for semantic keys within one project.
    #>
    Param(
        [AllowEmptyString()]
        [string] $SourcePath
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return ""
    }
    $normalized = $SourcePath.Trim().Replace('\', '/')
    while ($normalized.Contains("//")) {
        $normalized = $normalized.Replace("//", "/")
    }
    while ($normalized.StartsWith("./", [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized.ToLowerInvariant()
}

function Test-PathInsideRoot {
    <#
    .SYNOPSIS
        Tests whether a path is contained by a root path.
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

function Resolve-CoverageSourceRootDetail {
    <#
    .SYNOPSIS
        Resolves the source-root detail that owns a coverage source.
    #>
    Param(
        [string] $SourceIdentity,
        [object[]] $SourceRootDetails
    )

    $source = "$SourceIdentity".Replace('\', '/').Trim('/').ToLowerInvariant()
    $matchingDetails = @()
    foreach ($detail in $SourceRootDetails) {
        $root = "$($detail.Identity)"
        if ($root -eq "." -or $source -eq $root -or $source.StartsWith(
                "$root/", [System.StringComparison]::OrdinalIgnoreCase)) {
            $matchingDetails += $detail
        }
    }
    if ($matchingDetails.Count -eq 0) {
        return $null
    }
    $ordered = @($matchingDetails |
        Sort-Object @{ Expression = { "$($_.Identity)".Length }; Descending = $true })
    if ($ordered.Count -gt 1 -and
        "$($ordered[0].Identity)".Length -eq "$($ordered[1].Identity)".Length) {
        return $null
    }
    return $ordered[0]
}

function Resolve-ExistingCoverageSource {
    <#
    .SYNOPSIS
        Resolves an existing source file beneath the repository and source root.
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
        Reason = ""
        LocalMappingFailed = $false
    }
}

function Read-BcCoverageReport {
    <#
    .SYNOPSIS
        Parses and validates a Business Central coverage schema 1.0 report.
    #>
    Param(
        [string] $Path,
        [hashtable] $Model = $null,
        [AllowEmptyString()][string] $RequestedMode = "",
        [AllowEmptyString()][string] $RepositoryRoot = "",
        [hashtable] $SemanticLineUnion = $null,
        [System.Collections.Generic.List[string]] $SemanticRootOrder = $null,
        [System.Collections.Generic.Dictionary[string,object]] $SourceMappingCache = $null
    )

    $file = Get-Item -LiteralPath $Path
    $readerType = [type]::GetType("Newtonsoft.Json.JsonTextReader, Newtonsoft.Json", $false)
    if (-not $readerType) {
        $readerType = [AppDomain]::CurrentDomain.GetAssemblies() |
            ForEach-Object { $_.GetType("Newtonsoft.Json.JsonTextReader", $false) } |
            Where-Object { $_ } |
            Select-Object -First 1
    }
    $readerName = "Newtonsoft.Json"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outcome = "failed"
    $extractedLineCount = 0
    $acceptedLineCount = 0
    $newLineCount = 0
    $scope = @{ ApplicationLines = @{} }
    $sourceCache = if ($null -ne $SourceMappingCache) {
        $SourceMappingCache
    }
    else {
        [System.Collections.Generic.Dictionary[string,object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }
    $collectApplicationLines = $RequestedMode -eq "line" -and $null -ne $Model
    $normalizedRepositoryRoot = ""
    $normalizedSourceRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot) -and $null -ne $Model) {
        try {
            $normalizedRepositoryRoot = [System.IO.Path]::GetFullPath(
                (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
            ).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar)
            $normalizedSourceRoots = @(
                Get-NormalizedCoverageSourceRoots -RepositoryRoot $normalizedRepositoryRoot `
                    -SourceRoots $Model.SourceRoots
            )
        }
        catch {
            $normalizedRepositoryRoot = ""
            $normalizedSourceRoots = @()
        }
    }
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
        if (-not $readerType) {
            throw [System.IO.InvalidDataException]::new("reader")
        }
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
                        throw [System.IO.InvalidDataException]::new("duplicate:$propertyName")
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
                                    $rawIdentity = ConvertTo-CoverageSourceIdentity $sourcePath
                                    $source = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
                                        @{
                                            Included = -not [string]::IsNullOrWhiteSpace($sourcePath)
                                            Identity = $rawIdentity
                                            LocalMappingFailed = $false
                                        }
                                    }
                                    else {
                                        Resolve-NormalizedRepositoryCoverageSource `
                                            -SourcePath $sourcePath `
                                            -RepositoryRoot $normalizedRepositoryRoot `
                                            -NormalizedRoots $normalizedSourceRoots
                                    }
                                    $source.AppRootIdentity = ""
                                    if ($collectApplicationLines -and $source.Included) {
                                        $detail = $null
                                        if ($source.Contains("SourceRootIndex") -and
                                            [int]$source.SourceRootIndex -ge 0 -and
                                            [int]$source.SourceRootIndex -lt $Model.SourceRootDetails.Count) {
                                            $detail = $Model.SourceRootDetails[[int]$source.SourceRootIndex]
                                        }
                                        else {
                                            $detail = Resolve-CoverageSourceRootDetail `
                                                -SourceIdentity $source.Identity `
                                                -SourceRootDetails $Model.SourceRootDetails
                                        }
                                        if ($detail -and "$($detail.Kind)" -eq "app") {
                                            $source.AppRootIdentity = "$($detail.Identity)"
                                        }
                                    }
                                    $sourceCache[$sourcePath] = $source
                                }
                                if ($source.Included) {
                                    $rootIdentity = "$($source.AppRootIdentity)"
                                    if ($collectApplicationLines -and
                                        -not [string]::IsNullOrWhiteSpace($rootIdentity)) {
                                        $factKey = "$($source.Identity)|$objectType|$objectId|$lineNumber"
                                        if ($null -ne $SemanticLineUnion) {
                                            if (-not $SemanticLineUnion.ContainsKey($rootIdentity)) {
                                                $SemanticLineUnion[$rootIdentity] =
                                                    [System.Collections.Generic.Dictionary[string,bool]]::new(
                                                        [System.StringComparer]::Ordinal)
                                                if ($null -ne $SemanticRootOrder) {
                                                    $SemanticRootOrder.Add($rootIdentity)
                                                }
                                            }
                                            $rootLines = $SemanticLineUnion[$rootIdentity]
                                            if (-not $rootLines.ContainsKey($factKey)) {
                                                $acceptedLineCount++
                                                $newLineCount++
                                                $rootLines.Add($factKey, $hitCount -gt 0)
                                            }
                                            elseif ($hitCount -gt 0) {
                                                $rootLines[$factKey] = $true
                                            }
                                        }
                                        else {
                                            if (-not $scope.ApplicationLines.ContainsKey($rootIdentity)) {
                                                $scope.ApplicationLines[$rootIdentity] =
                                                    [System.Collections.Generic.Dictionary[string,bool]]::new(
                                                        [System.StringComparer]::Ordinal)
                                            }
                                            if (-not $scope.ApplicationLines[$rootIdentity].ContainsKey($factKey)) {
                                                $acceptedLineCount++
                                                $scope.ApplicationLines[$rootIdentity].Add(
                                                    $factKey, $hitCount -gt 0)
                                            }
                                            elseif ($hitCount -gt 0) {
                                                $scope.ApplicationLines[$rootIdentity][$factKey] = $true
                                            }
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

        $outcome = "passed"
        return @{
            Valid = $true
            Data = $reportData
            Scope = $scope
            Reader = $readerName
            ExtractedLineCount = $extractedLineCount
            AcceptedLineCount = $acceptedLineCount
            NewLineCount = $newLineCount
            FailureDetail = ""
            Reason = ""
        }
    }
    catch {
        $failureDetail = if ($_.Exception -is [System.IO.InvalidDataException]) {
            "$($_.Exception.Message)"
        }
        else {
            "corrupt"
        }
        $failureKind = if ($failureDetail.StartsWith(
                "duplicate:", [System.StringComparison]::Ordinal)) {
            "shape"
        }
        else {
            $failureDetail
        }
        $reason = switch ($failureKind) {
            "schema" { "Coverage report schemaVersion is not supported." }
            "mode" { "Coverage report mode is not supported." }
            "complete" { "Coverage report completeness value is invalid." }
            "shape" { "Coverage report does not match schemaVersion 1.0." }
            "reader" { "The Newtonsoft JSON streaming reader is unavailable." }
            default { "Coverage report JSON is corrupt or invalid." }
        }
        return @{
            Valid = $false
            Data = $null
            Scope = $null
            Reader = $readerName
            ExtractedLineCount = $extractedLineCount
            AcceptedLineCount = $acceptedLineCount
            NewLineCount = $newLineCount
            FailureDetail = $failureDetail
            Reason = $reason
        }
    }
    finally {
        $stopwatch.Stop()
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        Write-Host ("BC JSON analysis: reader={0}, size={1} MiB, elapsed={2}s, extractedLines={3}, acceptedLines={4}, outcome={5}." -f
            $readerName,
            ($file.Length / 1MB).ToString("0.0", $culture),
            $stopwatch.Elapsed.TotalSeconds.ToString("0.000", $culture),
            $extractedLineCount,
            $acceptedLineCount,
            $outcome)
    }
}

function Resolve-NormalizedRepositoryCoverageSource {
    <#
    .SYNOPSIS
        Maps a coverage source to its normalized repository-relative identity.
    #>
    Param(
        [AllowEmptyString()][string] $SourcePath,
        [AllowEmptyString()][string] $RepositoryRoot,
        [object[]] $NormalizedRoots
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return @{ Included = $false; Identity = ""; Reason = "blank source path"; LocalMappingFailed = $false }
    }
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return @{ Included = $false; Identity = ""; Reason = "source path is invalid"; LocalMappingFailed = $true }
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
                    return @{ Included = $false; Identity = ""; Reason = "source path could not be validated"; LocalMappingFailed = $true }
                }
            }
            return @{ Included = $false; Identity = ""; Reason = "source path is external"; LocalMappingFailed = $false }
        }

        $relativeSource = $normalizedSource.TrimStart('/')
        if ($relativeSource -match '(^|/)\.\.(/|$)') {
            return @{ Included = $false; Identity = ""; Reason = "source path is invalid"; LocalMappingFailed = $true }
        }
        if ($relativeSource -match '^external-([0-9]+)/(.+)$') {
            $rootIndex = [int]$matches[1]
            $externalPath = $matches[2]
            if ($rootIndex -le 0 -or $rootIndex -ge $NormalizedRoots.Count) {
                return @{ Included = $false; Identity = ""; Reason = "external source-root index is invalid"; LocalMappingFailed = $true }
            }
            $separatorIndex = $externalPath.IndexOf('/')
            if ($separatorIndex -le 0 -or $separatorIndex -eq $externalPath.Length - 1) {
                return @{ Included = $false; Identity = ""; Reason = "external source path is invalid"; LocalMappingFailed = $true }
            }
            $rootName = $externalPath.Substring(0, $separatorIndex)
            $rootRelativePath = $externalPath.Substring($separatorIndex + 1)
            $sourceRoot = $NormalizedRoots[$rootIndex]
            if (-not $sourceRoot.Valid -or
                -not $rootName.Equals(
                    $sourceRoot.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return @{ Included = $false; Identity = ""; Reason = "external source-root name is invalid"; LocalMappingFailed = $true }
            }
            $candidate = Join-Path $sourceRoot.FullPath `
                $rootRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $resolved = Resolve-ExistingCoverageSource -Candidate $candidate `
                -RepositoryRoot $RepositoryRoot -SourceRoot $sourceRoot.FullPath
            if ($resolved) {
                $resolved.SourceRootIndex = $rootIndex
                return $resolved
            }
            return @{ Included = $false; Identity = ""; Reason = "external source path could not be validated"; LocalMappingFailed = $true }
        }

        if ($NormalizedRoots.Count -eq 0) {
            return @{ Included = $false; Identity = ""; Reason = "no source roots were recorded"; LocalMappingFailed = $false }
        }
        $primaryRoot = $NormalizedRoots[0]
        if (-not $primaryRoot.Valid) {
            return @{ Included = $false; Identity = ""; Reason = "primary source root is invalid"; LocalMappingFailed = $true }
        }
        $candidate = Join-Path $primaryRoot.FullPath `
            $relativeSource.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $resolved = Resolve-ExistingCoverageSource -Candidate $candidate `
            -RepositoryRoot $RepositoryRoot -SourceRoot $primaryRoot.FullPath
        if ($resolved) {
            $resolved.SourceRootIndex = 0
            return $resolved
        }
        return @{ Included = $false; Identity = ""; Reason = "primary source path could not be validated"; LocalMappingFailed = $true }
    }
    catch {
        return @{ Included = $false; Identity = ""; Reason = "source path is invalid"; LocalMappingFailed = $true }
    }
}

function Resolve-RepositoryCoverageSource {
    <#
    .SYNOPSIS
        Maps a report source path to an existing repository file using the recorded source roots.
    .DESCRIPTION
        Exporter paths are decoded from the exact recorded source-root order. Other absolute or
        repository-relative paths are matched against the most-specific recorded source root.
    #>
    Param(
        [AllowEmptyString()][string] $SourcePath,
        [string] $RepositoryRoot,
        [string[]] $SourceRoots = @()
    )

    try {
        $fullRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
        $normalizedRoots = @(Get-NormalizedCoverageSourceRoots -RepositoryRoot $fullRoot -SourceRoots $SourceRoots)
        return Resolve-NormalizedRepositoryCoverageSource -SourcePath $SourcePath `
            -RepositoryRoot $fullRoot -NormalizedRoots $normalizedRoots
    }
    catch {
        return @{ Included = $false; Identity = ""; Reason = "source path is invalid"; LocalMappingFailed = $true }
    }
}

Export-ModuleMember -Function Get-CoverageArray,
    ConvertTo-CoverageSourceIdentity, Test-PathInsideRoot, Get-NormalizedCoverageSourceRoots,
    Resolve-CoverageSourceRootDetail, Resolve-ExistingCoverageSource,
    Resolve-NormalizedRepositoryCoverageSource, Resolve-RepositoryCoverageSource,
    Read-BcCoverageReport
