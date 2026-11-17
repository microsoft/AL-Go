$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "CodeCoverageAggregateFormat.psm1" -Resolve) -DisableNameChecking

function Invoke-CodeCoverageAggregateWorker {
    <#
    .SYNOPSIS
        Consumes streamed raw report descriptors and publishes their semantic line union.
    .PARAMETER inputReader
        Reader that supplies one JSON report descriptor per line.
    .PARAMETER readerModulePath
        Path to the coverage report reader module loaded by the worker.
    .PARAMETER repositoryRoot
        Absolute repository root used to resolve covered source files.
    .PARAMETER metadata
        Source-root and application ID-range metadata for the aggregate.
    .PARAMETER temporaryPath
        Temporary path used while writing the aggregate.
    .PARAMETER publishedPath
        Final path for the atomically published aggregate.
    #>
    Param(
        [System.IO.TextReader] $inputReader,
        [string] $readerModulePath,
        [string] $repositoryRoot,
        [hashtable] $metadata,
        [string] $temporaryPath,
        [string] $publishedPath
    )

    Import-Module $readerModulePath -DisableNameChecking
    $model = @{
        SourceRootDetails = @(
            foreach ($detail in @($metadata.SourceRootDetails)) {
                $path = "$($detail.path)".Replace('\', '/').Trim('/')
                @{
                    Path = $path
                    Identity = $path.ToLowerInvariant()
                    Kind = "$($detail.kind)".ToLowerInvariant()
                    AppId = "$($detail.appId)"
                    AppName = "$($detail.appName)"
                }
            }
        )
    }
    $model.SourceRoots = @($model.SourceRootDetails | ForEach-Object { $_.Path })
    $applicationObjectIdRanges = if ($metadata.ContainsKey("ApplicationObjectIdRanges")) {
        @($metadata.ApplicationObjectIdRanges)
    }
    else {
        @()
    }
    $isExternalMissingSourceDiagnostic = {
        Param([string] $diagnostic)

        $validRanges = @($applicationObjectIdRanges | Where-Object { $null -ne $_ })
        if ($validRanges.Count -eq 0 -or
            $diagnostic -notmatch '^\s*No source file was found for AL object \d+:(?<ObjectId>\d+)\.\s*$') {
            return $false
        }
        $objectId = [int]$Matches.ObjectId
        foreach ($idRange in $validRanges) {
            if ($objectId -ge [int]$idRange["From"] -and $objectId -le [int]$idRange["To"]) {
                return $false
            }
        }
        return $true
    }
    $semanticLines = @{}
    $semanticLineCount = 0
    $runDiagnostics = @{}
    $runCompleteness = @{}
    $sourceMappingCache = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $totalParseMilliseconds = [double]0

    try {
        while ($true) {
            $descriptorJson = $inputReader.ReadLine()
            if ($null -eq $descriptorJson) {
                break
            }
            $descriptorJson = $descriptorJson.TrimStart([char]0xFEFF)
            if ([string]::IsNullOrWhiteSpace($descriptorJson)) {
                continue
            }
            $descriptor = $descriptorJson | ConvertFrom-Json -AsHashtable
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $file = Get-Item -LiteralPath "$($descriptor.ReportPath)"
            try {
                $reportResult = Read-BcCoverageReport -Path $file.FullName -Model $model `
                    -RepositoryRoot $repositoryRoot -SemanticLineUnion $semanticLines `
                    -SourceMappingCache $sourceMappingCache
            }
            catch {
                throw "Compaction rejected '$($file.FullName)'. $($_.Exception.Message)"
            }
            if ([bool]$reportResult.Data.complete -ne [bool]$descriptor.Complete) {
                throw "Compaction report completeness does not match the runner result."
            }
            $rawDiagnostics = @(
                Get-CoverageArray $reportResult.Data.diagnostics |
                    ForEach-Object { "$_" }
            )
            $filteredDiagnostics = @(
                $rawDiagnostics | Where-Object {
                    -not (& $isExternalMissingSourceDiagnostic "$_")
                }
            )
            $runDiagnostics["$($descriptor.AppId)"] = @($filteredDiagnostics)
            $runCompleteness["$($descriptor.AppId)"] = [bool](
                [bool]$reportResult.Data.complete -or
                ($rawDiagnostics.Count -gt 0 -and $filteredDiagnostics.Count -eq 0)
            )
            $stopwatch.Stop()
            $totalParseMilliseconds += $stopwatch.Elapsed.TotalMilliseconds
            $semanticLineCount += [int]$reportResult.NewLineCount
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            Write-Host ("Code coverage compactor report {0}: size={1} MiB, parse={2}s, extracted={3}, new={4}, aggregate={5}." -f
                $runDiagnostics.Count,
                ($file.Length / 1MB).ToString("0.0", $culture),
                ($stopwatch.Elapsed.TotalMilliseconds / 1000).ToString("0.000", $culture),
                [int]$reportResult.ExtractedLineCount,
                [int]$reportResult.NewLineCount,
                $semanticLineCount)
        }

        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        Write-CodeCoverageAggregateFile -path $temporaryPath -lines $semanticLines
        [System.IO.File]::Move($temporaryPath, $publishedPath, $true)
        $publishedFile = Get-Item -LiteralPath $publishedPath
        return @{
            Aggregate = @{
                LineCount = $semanticLineCount
                SizeBytes = [long]$publishedFile.Length
                TotalParseMilliseconds = $totalParseMilliseconds
            }
            RunDiagnostics = $runDiagnostics
            RunCompleteness = $runCompleteness
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-CodeCoverageAggregateProcess {
    <#
    .SYNOPSIS
        Runs the child-process compactor protocol and writes its machine-readable result.
    .DESCRIPTION
        Reads aggregate configuration and newline-delimited report descriptors, writes
        the aggregate and result files, and returns a nonzero exit code on failure.
    .PARAMETER configPath
        Path to the JSON configuration file created by the parent process.
    .PARAMETER resultPath
        Path where the child process writes its final JSON result.
    #>
    Param(
        [string] $configPath,
        [string] $resultPath
    )

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable
        $workerResult = Invoke-CodeCoverageAggregateWorker -inputReader ([Console]::In) `
            -readerModulePath "$($config.ReaderModulePath)" `
            -repositoryRoot "$($config.RepositoryRoot)" -metadata $config.Metadata `
            -temporaryPath "$($config.TemporaryPath)" -publishedPath "$($config.PublishedPath)"
        @{
            Succeeded = $true
            Aggregate = $workerResult.Aggregate
            RunDiagnostics = $workerResult.RunDiagnostics
            RunCompleteness = $workerResult.RunCompleteness
        } | ConvertTo-Json -Depth 20 -Compress |
            Set-Content -LiteralPath $resultPath -Encoding UTF8
    }
    catch {
        @{
            Succeeded = $false
            Error = "$($_.Exception.Message)"
        } | ConvertTo-Json -Depth 5 -Compress |
            Set-Content -LiteralPath $resultPath -Encoding UTF8
        throw
    }
}

function Start-CodeCoverageAggregateWorker {
    <#
    .SYNOPSIS
        Starts the persistent PowerShell 7 coverage compactor for a test session.
    .PARAMETER readerModulePath
        Path to the coverage report reader module loaded by the worker.
    .PARAMETER repositoryRoot
        Absolute repository root used to resolve covered source files.
    .PARAMETER metadata
        Source-root and application ID-range metadata for the aggregate.
    .PARAMETER temporaryPath
        Temporary path used while writing the aggregate.
    .PARAMETER publishedPath
        Final path for the atomically published aggregate.
    .PARAMETER pwshPath
        Path to the PowerShell 7 executable that hosts the worker.
    #>
    Param(
        [string] $readerModulePath,
        [string] $repositoryRoot,
        [hashtable] $metadata,
        [string] $temporaryPath,
        [string] $publishedPath,
        [string] $pwshPath
    )

    $workerId = [Guid]::NewGuid().ToString("N")
    $workerDirectory = Split-Path -Path $temporaryPath -Parent
    $configPath = Join-Path $workerDirectory ".coverage-worker-$workerId.config.json"
    $resultPath = Join-Path $workerDirectory ".coverage-worker-$workerId.result.json"
    @{
        ReaderModulePath = $readerModulePath
        RepositoryRoot = $repositoryRoot
        Metadata = $metadata
        TemporaryPath = $temporaryPath
        PublishedPath = $publishedPath
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $configPath -Encoding UTF8

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pwshPath
        $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -Command "& $env:ALGO_COVERAGE_WORKER_SCRIPT"'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $false
        $startInfo.CreateNoWindow = $false
        $startInfo.EnvironmentVariables["ALGO_COVERAGE_WORKER_SCRIPT"] = (
            Join-Path $PSScriptRoot "CodeCoverageAggregateWorker.ps1" -Resolve
        )
        $startInfo.EnvironmentVariables["ALGO_COVERAGE_WORKER_MODULE"] = $PSCommandPath
        $startInfo.EnvironmentVariables["ALGO_COVERAGE_WORKER_CONFIG"] = $configPath
        $startInfo.EnvironmentVariables["ALGO_COVERAGE_WORKER_RESULT"] = $resultPath
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "The PowerShell 7 code coverage aggregate worker did not start."
        }
        $process.StandardInput.AutoFlush = $true
        return @{
            Process = $process
            Input = $process.StandardInput
            ConfigPath = $configPath
            ResultPath = $resultPath
        }
    }
    catch {
        if ($process) {
            $process.Dispose()
        }
        Remove-Item -LiteralPath $configPath, $resultPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Add-CodeCoverageAggregateWorkItem {
    <#
    .SYNOPSIS
        Streams one immutable validated report descriptor to the compactor.
    .PARAMETER worker
        Worker state returned by Start-CodeCoverageAggregateWorker.
    .PARAMETER descriptor
        Report descriptor containing the app ID, report path, and completeness value.
    #>
    Param(
        [hashtable] $worker,
        [hashtable] $descriptor
    )

    if (-not $worker -or $worker.Process.HasExited) {
        throw "The code coverage aggregate worker is not accepting reports."
    }
    $descriptorJson = $descriptor | ConvertTo-Json -Depth 10 -Compress
    try {
        $worker.Input.WriteLine($descriptorJson)
    }
    catch {
        throw "The code coverage aggregate worker stopped accepting reports. $($_.Exception.Message)"
    }
}

function Complete-CodeCoverageAggregateWorker {
    <#
    .SYNOPSIS
        Closes, waits for, and disposes the child-process compactor.
    .PARAMETER worker
        Worker state returned by Start-CodeCoverageAggregateWorker.
    #>
    Param([hashtable] $worker)

    if (-not $worker) {
        return $null
    }
    try {
        $worker.Input.Close()
        $worker.Process.WaitForExit()
        if (-not (Test-Path -LiteralPath $worker.ResultPath -PathType Leaf)) {
            throw "Code coverage aggregate worker exited with code $($worker.Process.ExitCode) without a result."
        }
        $result = Get-Content -LiteralPath $worker.ResultPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ($worker.Process.ExitCode -ne 0 -or -not [bool]$result.Succeeded) {
            $workerError = "$($result.Error)"
            if ([string]::IsNullOrWhiteSpace($workerError)) {
                $workerError = "The worker exited with code $($worker.Process.ExitCode)."
            }
            throw "Code coverage aggregate worker failed. $workerError"
        }
        if (-not $result.Aggregate) {
            throw "Code coverage aggregate worker returned an invalid result."
        }
        $aggregate = @{}
        foreach ($property in @($result.Aggregate.PSObject.Properties)) {
            $aggregate[$property.Name] = $property.Value
        }
        $runDiagnostics = @{}
        foreach ($property in @($result.RunDiagnostics.PSObject.Properties)) {
            $runDiagnostics[$property.Name] = @($property.Value | ForEach-Object { "$_" })
        }
        $aggregate["RunDiagnostics"] = $runDiagnostics
        $runCompleteness = @{}
        foreach ($property in @($result.RunCompleteness.PSObject.Properties)) {
            $runCompleteness[$property.Name] = [bool]$property.Value
        }
        $aggregate["RunCompleteness"] = $runCompleteness
        return $aggregate
    }
    finally {
        $worker.Input.Dispose()
        $worker.Process.Dispose()
        Remove-Item -LiteralPath $worker.ConfigPath, $worker.ResultPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Start-CodeCoverageAggregateWorker, Add-CodeCoverageAggregateWorkItem,
    Complete-CodeCoverageAggregateWorker, Invoke-CodeCoverageAggregateWorker,
    Invoke-CodeCoverageAggregateProcess
