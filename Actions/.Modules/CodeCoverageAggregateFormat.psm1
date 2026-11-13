$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Get-CodeCoverageAggregateProperty {
    Param(
        [object] $value,
        [string] $name
    )

    if ($value -is [System.Collections.IDictionary]) {
        if ($value.Contains($name)) {
            return $value[$name]
        }
        return $null
    }
    $property = $value.PSObject.Properties[$name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Get-CodeCoverageSourceRootFingerprint {
    <#
    .SYNOPSIS
        Computes the stable fingerprint for ordered coverage source-root metadata.
    #>
    Param(
        [string[]] $sourceRoots,
        [object[]] $sourceRootDetails
    )

    if ($sourceRoots.Count -ne $sourceRootDetails.Count) {
        throw "Code coverage source roots and details do not align."
    }
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $sourceRoots.Count; $index++) {
        $detail = $sourceRootDetails[$index]
        foreach ($value in @(
                "$($sourceRoots[$index])".Replace('\', '/').Trim('/'),
                "$(Get-CodeCoverageAggregateProperty -value $detail -name 'path')".Replace('\', '/').Trim('/'),
                "$(Get-CodeCoverageAggregateProperty -value $detail -name 'kind')".ToLowerInvariant(),
                "$(Get-CodeCoverageAggregateProperty -value $detail -name 'appId')".ToLowerInvariant(),
                "$(Get-CodeCoverageAggregateProperty -value $detail -name 'appName')"
            )) {
            [void]$builder.Append($value.Length)
            [void]$builder.Append(':')
            [void]$builder.Append($value)
            [void]$builder.Append('|')
        }
        [void]$builder.AppendLine()
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-CodeCoverageFileSha256 {
    Param([string] $path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($path)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
        $sha256.Dispose()
    }
}

function Write-CodeCoverageAggregateFile {
    <#
    .SYNOPSIS
        Writes the versioned compressed AL-Go coverage aggregate.
    #>
    Param(
        [string] $path,
        [hashtable] $metadata,
        [object[]] $runs,
        [System.Collections.IDictionary] $lines,
        [string[]] $rootOrder = @()
    )

    $fileStream = $null
    $gzipStream = $null
    $writer = $null
    try {
        $fileStream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            65536,
            [System.IO.FileOptions]::SequentialScan)
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $fileStream,
            [System.IO.Compression.CompressionLevel]::Fastest,
            $false)
        $writer = [System.IO.BinaryWriter]::new(
            $gzipStream,
            [System.Text.UTF8Encoding]::new($false),
            $false)

        $header = [ordered]@{
            contract = "al-go-code-coverage-aggregate"
            contractVersion = 1
            project = "$($metadata.Project)"
            projectName = "$($metadata.ProjectName)"
            buildMode = "$($metadata.BuildMode)"
            mode = "$($metadata.Mode)"
            formats = @($metadata.Formats)
            sourceRoots = @($metadata.SourceRoots)
            sourceRootDetails = @($metadata.SourceRootDetails)
            sourceRootFingerprint = "$($metadata.SourceRootFingerprint)"
        }
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("ALGOCOV1"))
        $writer.Write((ConvertTo-Json -InputObject $header -Depth 12 -Compress))

        $orderedRuns = @($runs | Sort-Object Sequence)
        $writer.Write([int]$orderedRuns.Count)
        foreach ($run in $orderedRuns) {
            $writer.Write((ConvertTo-Json -InputObject ([ordered]@{
                        sequence = [int]$run.Sequence
                        appId = "$($run.AppId)"
                        appName = "$($run.AppName)"
                        state = "$($run.State)"
                        complete = [bool]$run.Complete
                        lineReasons = @($run.LineReasons)
                        notices = @($run.Notices)
                        lineGlobalUnsafe = [bool]$run.LineGlobalUnsafe
                        lineAffectedSources = @($run.LineAffectedSources | Sort-Object)
                        excludedLineFacts = [int]$run.ExcludedLineFacts
                    }) -Depth 12 -Compress))
        }

        [string[]]$orderedRoots = @(
            if ($rootOrder.Count -gt 0) {
                if ($rootOrder.Count -ne $lines.Count) {
                    throw "Code coverage aggregate root order does not match its semantic lines."
                }
                $rootOrder
            }
            else {
                $roots = [string[]]@($lines.Keys)
                [System.Array]::Sort($roots, [System.StringComparer]::Ordinal)
                $roots
            }
        )
        $lineCount = [long]0
        foreach ($root in $orderedRoots) {
            if ([string]::IsNullOrWhiteSpace($root) -or
                $lines[$root] -isnot [System.Collections.IDictionary]) {
                throw "Code coverage aggregate contains an invalid semantic line root."
            }
            $lineCount += $lines[$root].Count
        }
        $writer.Write($lineCount)

        foreach ($root in $orderedRoots) {
            foreach ($key in $lines[$root].Keys) {
                $writer.Write($root)
                $writer.Write("$key")
                $writer.Write([bool]$lines[$root][$key])
            }
        }

        $writer.Write($lineCount)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("ENDCOV1!"))
        $writer.Flush()
    }
    finally {
        if ($writer) {
            $writer.Dispose()
        }
        elseif ($gzipStream) {
            $gzipStream.Dispose()
        }
        elseif ($fileStream) {
            $fileStream.Dispose()
        }
    }
}

function Read-CodeCoverageAggregate {
    <#
    .SYNOPSIS
        Reads and validates a published AL-Go coverage aggregate.
    #>
    Param(
        [string] $path,
        [AllowEmptyString()][string] $expectedSha256 = "",
        [AllowEmptyString()][string] $expectedSourceRootFingerprint = "",
        [switch] $ValidateOnly
    )

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{ Valid = $false; Reason = "The code coverage aggregate is missing." }
    }
    try {
        if (-not [string]::IsNullOrWhiteSpace($expectedSha256)) {
            $actualSha256 = Get-CodeCoverageFileSha256 -path $path
            if ($actualSha256 -cne $expectedSha256.ToLowerInvariant()) {
                throw [System.IO.InvalidDataException]::new("checksum")
            }
        }
        elseif ($ValidateOnly) {
            throw [System.IO.InvalidDataException]::new("checksum")
        }

        $fileStream = $null
        $gzipStream = $null
        $reader = $null
        try {
            $fileStream = [System.IO.File]::OpenRead($path)
            $gzipStream = [System.IO.Compression.GZipStream]::new(
                $fileStream,
                [System.IO.Compression.CompressionMode]::Decompress,
                $false)
            $reader = [System.IO.BinaryReader]::new(
                $gzipStream,
                [System.Text.Encoding]::UTF8,
                $false)

            $magic = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(8))
            if ($magic -cne "ALGOCOV1") {
                throw [System.IO.InvalidDataException]::new("version")
            }
            $header = $reader.ReadString() | ConvertFrom-Json -ErrorAction Stop
            if ("$(Get-CodeCoverageAggregateProperty -value $header -name 'contract')" -cne
                "al-go-code-coverage-aggregate" -or
                [int](Get-CodeCoverageAggregateProperty -value $header -name 'contractVersion') -ne 1) {
                throw [System.IO.InvalidDataException]::new("version")
            }
            $fingerprint = "$(Get-CodeCoverageAggregateProperty -value $header -name 'sourceRootFingerprint')"
            if (-not [string]::IsNullOrWhiteSpace($expectedSourceRootFingerprint) -and
                $fingerprint -cne $expectedSourceRootFingerprint) {
                throw [System.IO.InvalidDataException]::new("fingerprint")
            }

            $runs = @{}
            $runOrder = @()
            $applicationLines = @{}
            $runCount = $reader.ReadInt32()
            if ($runCount -lt 0) {
                throw [System.IO.InvalidDataException]::new("count")
            }
            for ($runIndex = 0; $runIndex -lt $runCount; $runIndex++) {
                $run = $reader.ReadString() | ConvertFrom-Json -ErrorAction Stop
                $appId = "$(Get-CodeCoverageAggregateProperty -value $run -name 'appId')"
                if ([string]::IsNullOrWhiteSpace($appId) -or $runs.ContainsKey($appId)) {
                    throw [System.IO.InvalidDataException]::new("shape")
                }
                $runs[$appId] = $run
                $runOrder += $appId
            }

            $lineCount = $reader.ReadInt64()
            if ($lineCount -lt 0) {
                throw [System.IO.InvalidDataException]::new("count")
            }
            for ([long]$lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++) {
                $root = $reader.ReadString()
                $key = $reader.ReadString()
                $covered = $reader.ReadBoolean()
                if ([string]::IsNullOrWhiteSpace($root) -or
                    [string]::IsNullOrWhiteSpace($key)) {
                    throw [System.IO.InvalidDataException]::new("shape")
                }
                if (-not $ValidateOnly) {
                    if (-not $applicationLines.ContainsKey($root)) {
                        $applicationLines[$root] = @{}
                    }
                    if ($applicationLines[$root].ContainsKey($key)) {
                        throw [System.IO.InvalidDataException]::new("shape")
                    }
                    $applicationLines[$root][$key] = $covered
                }
            }

            if ($reader.ReadInt64() -ne $lineCount -or
                [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(8)) -cne
                    "ENDCOV1!" -or
                $gzipStream.ReadByte() -ne -1) {
                throw [System.IO.InvalidDataException]::new("count")
            }
            return @{
                Valid = $true
                Reason = ""
                Header = $header
                Runs = $runs
                RunOrder = @($runOrder)
                ApplicationLines = $applicationLines
                LineCount = $lineCount
            }
        }
        finally {
            if ($reader) {
                $reader.Dispose()
            }
            elseif ($gzipStream) {
                $gzipStream.Dispose()
            }
            elseif ($fileStream) {
                $fileStream.Dispose()
            }
        }
    }
    catch {
        return @{
            Valid = $false
            Reason = "The code coverage aggregate is corrupt, incomplete, or incompatible. $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Get-CodeCoverageAggregateProperty, Get-CodeCoverageSourceRootFingerprint,
    Get-CodeCoverageFileSha256, Read-CodeCoverageAggregate, Write-CodeCoverageAggregateFile
