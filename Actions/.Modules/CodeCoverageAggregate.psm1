$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "CodeCoverageAggregateFormat.psm1" -Resolve) -DisableNameChecking

function Invoke-CodeCoverageAggregateWorker {
    <#
    .SYNOPSIS
        Consumes streamed raw report descriptors and publishes their semantic line union.
    #>
    Param(
        [System.IO.TextReader] $inputReader,
        [string] $readerModulePath,
        [string] $repositoryRoot,
        [hashtable] $metadata,
        [string] $temporaryPath,
        [string] $publishedPath
    )

    Import-Module $readerModulePath -Force -DisableNameChecking
    $model = @{
        SourceRoots = @($metadata.SourceRoots)
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
    $semanticLines = @{}
    $semanticRootOrder = [System.Collections.Generic.List[string]]::new()
    $semanticLineCount = 0
    $runDiagnostics = [System.Collections.Generic.List[object]]::new()
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
            if ([string]::IsNullOrWhiteSpace($descriptorJson)) {
                continue
            }
            $descriptor = $descriptorJson | ConvertFrom-Json -AsHashtable
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $file = Get-Item -LiteralPath "$($descriptor.ReportPath)"
            $reportResult = Read-BcCoverageReport -Path $file.FullName -Model $model `
                -RequestedMode "$($metadata.Mode)" -RepositoryRoot $repositoryRoot `
                -SemanticLineUnion $semanticLines -SemanticRootOrder $semanticRootOrder `
                -SourceMappingCache $sourceMappingCache
            if (-not $reportResult.Valid) {
                throw "Compaction rejected '$($file.FullName)'. $($reportResult.Reason)"
            }
            if ("$($reportResult.Data.coverageMode)".ToLowerInvariant() -ne "$($metadata.Mode)") {
                throw "Compaction report mode does not match the session mode."
            }
            if ([bool]$reportResult.Data.complete -ne [bool]$descriptor.Complete) {
                throw "Compaction report completeness does not match the runner result."
            }
            $runDiagnostics.Add([PSCustomObject]@{
                    Diagnostics = @(
                        Get-CoverageArray $reportResult.Data.diagnostics |
                            ForEach-Object { "$_" }
                    )
                })
            $stopwatch.Stop()
            $totalParseMilliseconds += $stopwatch.Elapsed.TotalMilliseconds
            $semanticLineCount += [int]$reportResult.NewLineCount
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            Write-Host ("Code coverage compactor report {0}: size={1} MiB, parse={2}s, extracted={3}, accepted={4}, new={5}, aggregate={6}." -f
                $runDiagnostics.Count,
                ($file.Length / 1MB).ToString("0.0", $culture),
                ($stopwatch.Elapsed.TotalMilliseconds / 1000).ToString("0.000", $culture),
                [int]$reportResult.ExtractedLineCount,
                [int]$reportResult.AcceptedLineCount,
                [int]$reportResult.NewLineCount,
                $semanticLineCount)
        }

        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        Write-CodeCoverageAggregateFile -path $temporaryPath -lines $semanticLines `
            -rootOrder $semanticRootOrder
        [System.IO.File]::Move($temporaryPath, $publishedPath, $true)
        $publishedFile = Get-Item -LiteralPath $publishedPath
        return @{
            Aggregate = @{
                LineCount = $semanticLineCount
                SizeBytes = [long]$publishedFile.Length
                TotalParseMilliseconds = $totalParseMilliseconds
            }
            RunDiagnostics = @($runDiagnostics)
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
            RunDiagnostics = @($workerResult.RunDiagnostics)
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

function Get-CodeCoveragePwshPath {
    Param([string] $pwshPath)

    if (-not [string]::IsNullOrWhiteSpace($pwshPath)) {
        return $pwshPath
    }
    $pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $pwshCommand) {
        throw "PowerShell 7 (pwsh) is required for code coverage compaction."
    }
    return "$($pwshCommand.Source)"
}

function Start-CodeCoverageAggregateWorker {
    <#
    .SYNOPSIS
        Starts the persistent PowerShell 7 coverage compactor for a test session.
    #>
    Param(
        [string] $readerModulePath,
        [string] $repositoryRoot,
        [hashtable] $metadata,
        [string] $temporaryPath,
        [string] $publishedPath,
        [string] $pwshPath = ""
    )

    $pwshPath = Get-CodeCoveragePwshPath -pwshPath $pwshPath
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
        $aggregate["RunDiagnostics"] = @($result.RunDiagnostics)
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
