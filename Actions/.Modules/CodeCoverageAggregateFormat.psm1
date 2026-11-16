$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Get-CodeCoverageBinaryStringLength {
    Param([string] $value)

    $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($value)
    $prefixLength = 1
    for ($remaining = $byteCount; $remaining -ge 128; $remaining = $remaining -shr 7) {
        $prefixLength++
    }
    return [long]$byteCount + $prefixLength
}

function Write-CodeCoverageAggregateFile {
    <#
    .SYNOPSIS
        Writes the versioned compressed AL-Go coverage line union.
    #>
    Param(
        [string] $path,
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

        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("ALGOCOV1"))
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
        Reads and validates a published AL-Go coverage line union.
    #>
    Param([string] $path)

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{ Valid = $false; Reason = "The code coverage aggregate is missing." }
    }
    try {
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
            $applicationLines = @{}
            $lineCount = $reader.ReadInt64()
            if ($lineCount -lt 0) {
                throw [System.IO.InvalidDataException]::new("count")
            }
            $uncompressedLength = [long]16
            for ([long]$lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++) {
                $root = $reader.ReadString()
                $key = $reader.ReadString()
                $covered = $reader.ReadBoolean()
                if ([string]::IsNullOrWhiteSpace($root) -or
                    [string]::IsNullOrWhiteSpace($key)) {
                    throw [System.IO.InvalidDataException]::new("shape")
                }
                if (-not $applicationLines.ContainsKey($root)) {
                    $applicationLines[$root] = @{}
                }
                if ($applicationLines[$root].ContainsKey($key)) {
                    throw [System.IO.InvalidDataException]::new("shape")
                }
                $applicationLines[$root][$key] = $covered
                $uncompressedLength += Get-CodeCoverageBinaryStringLength -value $root
                $uncompressedLength += Get-CodeCoverageBinaryStringLength -value $key
                $uncompressedLength++
            }
            if ($gzipStream.ReadByte() -ne -1) {
                throw [System.IO.InvalidDataException]::new("shape")
            }
            if ($fileStream.Length -lt 4) {
                throw [System.IO.InvalidDataException]::new("length")
            }
            $null = $fileStream.Seek(-4, [System.IO.SeekOrigin]::End)
            $lengthBytes = [byte[]]::new(4)
            if ($fileStream.Read($lengthBytes, 0, 4) -ne 4) {
                throw [System.IO.InvalidDataException]::new("length")
            }
            if (-not [System.BitConverter]::IsLittleEndian) {
                [System.Array]::Reverse($lengthBytes)
            }
            $declaredLength = [System.BitConverter]::ToUInt32($lengthBytes, 0)
            if ($declaredLength -ne [uint32]($uncompressedLength % 4294967296)) {
                throw [System.IO.InvalidDataException]::new("length")
            }
            return @{
                Valid = $true
                Reason = ""
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

Export-ModuleMember -Function Read-CodeCoverageAggregate, Write-CodeCoverageAggregateFile
