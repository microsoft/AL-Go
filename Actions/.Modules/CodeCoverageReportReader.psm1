$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

$script:SupportedCoverageModes = @("all", "line", "procedure")

function Get-CoverageArray {
    Param($Value)

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Expected an array."
    }
    return @($Value)
}

function ConvertTo-CoverageInteger {
    Param($Value)

    $converted = 0
    if ($null -eq $Value -or -not [int]::TryParse("$Value", [ref] $converted)) {
        throw "Expected an integer."
    }
    return $converted
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

function Test-CoverageMode {
    Param([AllowEmptyString()][string] $Mode)
    return $Mode -in $script:SupportedCoverageModes
}

function Test-PathInsideRoot {
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

function Test-CoveragePathWithoutReparsePoint {
    Param(
        [string] $Path,
        [string] $Root
    )

    $current = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    while ($true) {
        if (-not (Test-Path -LiteralPath $current)) {
            return $false
        }
        $attributes = [System.IO.File]::GetAttributes($current)
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $false
        }
        if ($current.Equals($rootPath, $comparison)) {
            return $true
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($current, $comparison)) {
            return $false
        }
        $current = $parent.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
    }
}

function Get-NormalizedCoverageSourceRoots {
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
                if ((Test-PathInsideRoot -Path $resolved -Root $repositoryPath) -and
                    (Test-CoveragePathWithoutReparsePoint -Path $resolved -Root $repositoryPath)) {
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
    if (-not (Test-CoveragePathWithoutReparsePoint -Path $resolved -Root $RepositoryRoot)) {
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
        [switch] $MetadataOnly
    )

    $file = Get-Item -LiteralPath $Path
    $readerType = $null
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $readerType = [type]::GetType("Newtonsoft.Json.JsonTextReader, Newtonsoft.Json", $false)
        if (-not $readerType) {
            $readerType = [AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { $_.GetType("Newtonsoft.Json.JsonTextReader", $false) } |
                Where-Object { $_ } |
                Select-Object -First 1
        }
    }
    $readerName = if ($readerType) { "Newtonsoft.Json" } else { "ConvertFrom-Json" }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outcome = "failed"
    $extractedLineCount = 0
    $acceptedLineCount = 0
    $newLineCount = 0
    $scope = @{
        IncludedLineObjects = @{}
        IncludedLineSources = @{}
        ExcludedLineObjects = @{}
        ApplicationLines = @{}
        LineReasons = @()
        ExcludedLineFacts = 0
    }
    $sourceCache = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $seenExcludedLines = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $collectApplicationLines = -not $MetadataOnly -and
        $RequestedMode -in @("line", "all") -and $null -ne $Model
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
    $requiredRootProperties = if ($MetadataOnly) {
        @("schemaVersion", "coverageMode", "complete")
    }
    else {
        @(
            "schemaVersion", "coverageMode", "complete", "diagnostics", "sources",
            "tests", "procedureEdges", "methods", "lines"
        )
    }
    $seenRootProperties = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )

    try {
        if ($readerType) {
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
                    if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                        throw [System.IO.InvalidDataException]::new("corrupt")
                    }
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
                    if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
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
                                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                                    throw [System.IO.InvalidDataException]::new("corrupt")
                                }
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
                                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                                    throw [System.IO.InvalidDataException]::new("corrupt")
                                }
                                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndArray) {
                                    break
                                }
                                if ($jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartObject) {
                                    throw [System.IO.InvalidDataException]::new("shape")
                                }
                                $line = [Newtonsoft.Json.Linq.JObject]::Load($jsonReader)
                                $objectTypeToken = $line["objectType"]
                                $objectIdToken = $line["objectId"]
                                $lineNumberToken = $line["lineNumber"]
                                $lineTypeToken = $line["lineType"]
                                $methodIdToken = $line["methodId"]
                                $hitCountToken = $line["hitCount"]
                                $statusToken = $line["status"]
                                $sourcePathToken = $line["sourcePath"]
                                if ($null -eq $objectTypeToken -or
                                    $null -eq $objectIdToken -or
                                    $null -eq $lineNumberToken -or
                                    $null -eq $lineTypeToken -or
                                    $null -eq $methodIdToken -or
                                    $null -eq $hitCountToken -or
                                    $null -eq $statusToken -or
                                    $null -eq $sourcePathToken -or
                                    ($objectTypeToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $objectTypeToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($objectIdToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $objectIdToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($lineNumberToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $lineNumberToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($lineTypeToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $lineTypeToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($methodIdToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $methodIdToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($hitCountToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $hitCountToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    ($statusToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::Integer -and
                                        $statusToken.Type -ne
                                        [Newtonsoft.Json.Linq.JTokenType]::String) -or
                                    $sourcePathToken.Type -in @(
                                        [Newtonsoft.Json.Linq.JTokenType]::Array,
                                        [Newtonsoft.Json.Linq.JTokenType]::Object)) {
                                    throw [System.IO.InvalidDataException]::new("shape")
                                }
                                try {
                                    $objectType = [int]$objectTypeToken
                                    $objectId = [int]$objectIdToken
                                    $lineNumber = [int]$lineNumberToken
                                    $lineType = [int]$lineTypeToken
                                    [void][int]$methodIdToken
                                    $hitCount = [int]$hitCountToken
                                    [void][int]$statusToken
                                    $sourcePath = [string]$sourcePathToken
                                }
                                catch {
                                    throw [System.IO.InvalidDataException]::new("shape")
                                }
                                $extractedLineCount++
                                if ($lineType -ne 3) {
                                    continue
                                }

                                $objectKey = "$objectType|$objectId"
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
                                    $source.RawIdentity = $rawIdentity
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
                                else {
                                    $rawIdentity = "$($source.RawIdentity)"
                                }
                                if ($source.Included) {
                                    if (-not $scope.IncludedLineObjects.ContainsKey($objectKey)) {
                                        $scope.IncludedLineObjects[$objectKey] = $true
                                        $scope.IncludedLineSources[$objectKey] = @{}
                                        $scope.IncludedLineSources[$objectKey][$source.Identity] = $true
                                    }
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
                                else {
                                    $scope.ExcludedLineObjects[$objectKey] = $true
                                    if ($collectApplicationLines -and
                                        $seenExcludedLines.Add(
                                            "$rawIdentity|$objectType|$objectId|$lineNumber")) {
                                        $scope.ExcludedLineFacts++
                                    }
                                    if ($collectApplicationLines -and
                                        $source.LocalMappingFailed) {
                                        $scope.LineReasons += "A repository source path could not be validated."
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
        }
        else {
            $report = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
            if ($report -isnot [System.Management.Automation.PSCustomObject]) {
                throw [System.IO.InvalidDataException]::new("corrupt")
            }
            foreach ($propertyName in $requiredRootProperties) {
                $properties = @($report.PSObject.Properties | Where-Object {
                        $_.Name -ceq $propertyName
                    })
                if ($properties.Count -ne 1) {
                    $failureKind = if ($propertyName -eq "schemaVersion") { "schema" }
                        elseif ($propertyName -eq "coverageMode") { "mode" }
                        elseif ($propertyName -eq "complete") { "complete" }
                        else { "shape" }
                    throw [System.IO.InvalidDataException]::new($failureKind)
                }
                $seenRootProperties.Add($propertyName) | Out-Null
            }
            if ($report.schemaVersion -isnot [string]) {
                throw [System.IO.InvalidDataException]::new("schema")
            }
            if ($report.coverageMode -isnot [string]) {
                throw [System.IO.InvalidDataException]::new("mode")
            }
            if ($report.complete -isnot [bool]) {
                throw [System.IO.InvalidDataException]::new("complete")
            }
            $reportData.schemaVersion = "$($report.schemaVersion)"
            $reportData.coverageMode = "$($report.coverageMode)"
            $reportData.complete = [bool]$report.complete
            if (-not $MetadataOnly) {
                try {
                    foreach ($propertyName in @(
                            "diagnostics", "sources", "tests", "procedureEdges", "methods", "lines")) {
                        [void](Get-CoverageArray $report.$propertyName)
                    }
                    $reportData.diagnostics = @(
                        Get-CoverageArray $report.diagnostics | ForEach-Object { "$_" }
                    )
                    foreach ($line in @(Get-CoverageArray $report.lines)) {
                    foreach ($propertyName in @(
                            "objectType", "objectId", "lineNumber", "lineType",
                            "methodId", "hitCount", "status", "sourcePath")) {
                        if ($null -eq $line.PSObject.Properties[$propertyName]) {
                            throw [System.IO.InvalidDataException]::new("shape")
                        }
                    }
                    $objectType = ConvertTo-CoverageInteger $line.objectType
                    $objectId = ConvertTo-CoverageInteger $line.objectId
                    $lineNumber = ConvertTo-CoverageInteger $line.lineNumber
                    $lineType = ConvertTo-CoverageInteger $line.lineType
                    [void](ConvertTo-CoverageInteger $line.methodId)
                    $hitCount = ConvertTo-CoverageInteger $line.hitCount
                    [void](ConvertTo-CoverageInteger $line.status)
                    $sourcePath = "$($line.sourcePath)"
                    $extractedLineCount++
                    if ($lineType -ne 3) {
                        continue
                    }

                    $objectKey = "$objectType|$objectId"
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
                        $source.RawIdentity = $rawIdentity
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
                    else {
                        $rawIdentity = "$($source.RawIdentity)"
                    }
                    if ($source.Included) {
                        if (-not $scope.IncludedLineObjects.ContainsKey($objectKey)) {
                            $scope.IncludedLineObjects[$objectKey] = $true
                            $scope.IncludedLineSources[$objectKey] = @{}
                            $scope.IncludedLineSources[$objectKey][$source.Identity] = $true
                        }
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
                                    $scope.ApplicationLines[$rootIdentity] = @{}
                                }
                                if (-not $scope.ApplicationLines[$rootIdentity].ContainsKey($factKey)) {
                                    $acceptedLineCount++
                                    $scope.ApplicationLines[$rootIdentity][$factKey] = $hitCount -gt 0
                                }
                                elseif ($hitCount -gt 0) {
                                    $scope.ApplicationLines[$rootIdentity][$factKey] = $true
                                }
                            }
                        }
                    }
                    else {
                        $scope.ExcludedLineObjects[$objectKey] = $true
                        if ($collectApplicationLines -and
                            $seenExcludedLines.Add(
                                "$rawIdentity|$objectType|$objectId|$lineNumber")) {
                            $scope.ExcludedLineFacts++
                        }
                        if ($collectApplicationLines -and $source.LocalMappingFailed) {
                            $scope.LineReasons +=
                                "A repository source path could not be validated."
                        }
                    }
                    }
                }
                catch {
                    if ($_.Exception -is [System.IO.InvalidDataException]) {
                        throw
                    }
                    throw [System.IO.InvalidDataException]::new("shape")
                }
            }
            $report = $null
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
        if (-not (Test-CoverageMode "$($reportData.coverageMode)")) {
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
        $operation = if ($MetadataOnly) { "metadata validation" } else { "analysis" }
        Write-Host ("BC JSON {0}: reader={1}, size={2} MiB, elapsed={3}s, extractedLines={4}, acceptedLines={5}, outcome={6}." -f
            $operation,
            $readerName,
            ($file.Length / 1MB).ToString("0.0", $culture),
            $stopwatch.Elapsed.TotalSeconds.ToString("0.000", $culture),
            $extractedLineCount,
            $acceptedLineCount,
            $outcome)
    }
}

function Get-CoverageDiagnosticAssessment {
    <#
    .SYNOPSIS
        Classifies coverage diagnostics against included and excluded sources.
    #>
    Param(
        [hashtable] $Report,
        [hashtable] $Scope
    )

    $lineReasons = @($Scope.LineReasons)
    $notices = @()
    $lineGlobalUnsafe = $Scope.LineReasons.Count -gt 0
    $lineAffectedSources = @{}
    $ignoredDiagnostics = 0
    $diagnostics = @(Get-CoverageArray $Report.diagnostics | ForEach-Object { "$_" })
    if (-not [bool]$Report.complete) {
        $notices += "The BC JSON report declares global enrichment incomplete."
    }

    foreach ($diagnostic in $diagnostics) {
        if ($diagnostic -match "^Coverage source root '.+' contains no AL source files\.$") {
            $ignoredDiagnostics++
            continue
        }

        if ($diagnostic -match '^AL object ([0-9]+):([0-9]+) is defined by multiple source files and was not enriched\.$') {
            $ignoredDiagnostics++
            continue
        }

        $objectKey = ""
        if ($diagnostic -match '^No source file was found for AL object ([0-9]+):([0-9]+)\.$') {
            $objectKey = "$($matches[1])|$($matches[2])"
        }
        if (-not [string]::IsNullOrWhiteSpace($objectKey)) {
            $hasIncludedLine = $Scope.IncludedLineObjects.ContainsKey($objectKey)
            $hasExcludedFact = $Scope.ExcludedLineObjects.ContainsKey($objectKey)
            if (-not $hasIncludedLine -and $hasExcludedFact) {
                $ignoredDiagnostics++
                continue
            }
            if ($hasIncludedLine) {
                if ($Scope.IncludedLineSources.ContainsKey($objectKey)) {
                    foreach ($sourceIdentity in $Scope.IncludedLineSources[$objectKey].Keys) {
                        $lineAffectedSources[$sourceIdentity] = $true
                    }
                }
                else {
                    $lineGlobalUnsafe = $true
                }
            }
            if (-not $hasIncludedLine) {
                $lineReasons += "A coverage source diagnostic could not be safely scoped."
                $lineGlobalUnsafe = $true
            }
            continue
        }

        if ($diagnostic -match '^[0-9]+ server coverage lines were not found in the supplied source\.$') {
            $lineReasons += "Server coverage lines could not be mapped to the supplied source."
            $lineGlobalUnsafe = $true
            continue
        }

        if ($diagnostic.StartsWith("Coverage method identity resolution failed for '",
                [System.StringComparison]::Ordinal)) {
            $ignoredDiagnostics++
            continue
        }

        $lineReasons += "A coverage diagnostic could not be safely scoped."
        $lineGlobalUnsafe = $true
    }

    if ($ignoredDiagnostics -gt 0) {
        $notices += "Ignored $ignoredDiagnostics diagnostics that do not affect repository-scoped line coverage."
    }

    return @{
        LineReasons = @($lineReasons | Select-Object -Unique)
        LineGlobalUnsafe = $lineGlobalUnsafe
        LineAffectedSources = @($lineAffectedSources.Keys)
        Notices = @($notices | Select-Object -Unique)
    }
}

function Resolve-NormalizedRepositoryCoverageSource {
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

Export-ModuleMember -Function Get-CoverageArray, ConvertTo-CoverageInteger,
    ConvertTo-CoverageSourceIdentity, Test-CoverageMode, Test-PathInsideRoot,
    Test-CoveragePathWithoutReparsePoint, Get-NormalizedCoverageSourceRoots,
    Resolve-CoverageSourceRootDetail, Resolve-ExistingCoverageSource,
    Resolve-NormalizedRepositoryCoverageSource, Resolve-RepositoryCoverageSource,
    Read-BcCoverageReport, Get-CoverageDiagnosticAssessment
