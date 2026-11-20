$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Write-CodeCoverageAggregateFile {
    <#
    .SYNOPSIS
        Writes the versioned compressed AL-Go coverage line union.
    .PARAMETER path
        Destination path for the compressed aggregate file.
    .PARAMETER lines
        Covered-state dictionaries grouped by application source-root identity.
    #>
    Param(
        [string] $path,
        [System.Collections.IDictionary] $lines
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
        [string[]]$orderedRoots = @($lines.Keys)
        [System.Array]::Sort($orderedRoots, [System.StringComparer]::Ordinal)
        $lineCount = [long]0
        foreach ($root in $orderedRoots) {
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
    .PARAMETER path
        Path to the compressed aggregate file.
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
            }
            if ($gzipStream.ReadByte() -ne -1) {
                throw [System.IO.InvalidDataException]::new("shape")
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
