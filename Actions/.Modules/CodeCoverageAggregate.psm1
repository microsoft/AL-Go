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
                $path = "$(Get-CodeCoverageAggregateProperty -value $detail -name 'path')".Replace('\', '/').Trim('/')
                @{
                    Path = $path
                    Identity = $path.ToLowerInvariant()
                    Kind = "$(Get-CodeCoverageAggregateProperty -value $detail -name 'kind')".ToLowerInvariant()
                    AppId = "$(Get-CodeCoverageAggregateProperty -value $detail -name 'appId')"
                    AppName = "$(Get-CodeCoverageAggregateProperty -value $detail -name 'appName')"
                }
            }
        )
    }
    $semanticLines = @{}
    $semanticRootOrder = [System.Collections.Generic.List[string]]::new()
    $semanticLineCount = 0
    $runAssessments = [System.Collections.Generic.List[object]]::new()
    $telemetry = [System.Collections.Generic.List[object]]::new()
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
            $parseStartedAt = [DateTime]::UtcNow
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $memoryBefore = [System.Diagnostics.Process]::GetCurrentProcess().PrivateMemorySize64
            $file = Get-Item -LiteralPath "$($descriptor.ReportPath)"
            $reportResult = Read-BcCoverageReport -Path $file.FullName -Model $model `
                -RequestedMode "$($metadata.Mode)" -RepositoryRoot $repositoryRoot `
                -SemanticLineUnion $semanticLines -SemanticRootOrder $semanticRootOrder
            if (-not $reportResult.Valid) {
                throw "Compaction rejected '$($file.FullName)'. $($reportResult.Reason)"
            }
            if ("$($reportResult.Data.coverageMode)".ToLowerInvariant() -ne "$($metadata.Mode)") {
                throw "Compaction report mode does not match the session mode."
            }
            if ([bool]$reportResult.Data.complete -ne [bool]$descriptor.Complete) {
                throw "Compaction report completeness does not match the validated run."
            }
            $assessment = Get-CoverageDiagnosticAssessment -Report $reportResult.Data `
                -Scope $reportResult.Scope
            $runAssessments.Add([PSCustomObject]@{
                    Sequence = [int]$descriptor.Sequence
                    AppId = "$($descriptor.AppId)"
                    AppName = "$($descriptor.AppName)"
                    State = if ([bool]$descriptor.Complete) { "complete" } else { "incomplete" }
                    Complete = [bool]$descriptor.Complete
                    LineReasons = @($assessment.LineReasons)
                    Notices = @($assessment.Notices)
                    LineGlobalUnsafe = [bool]$assessment.LineGlobalUnsafe
                    LineAffectedSources = @($assessment.LineAffectedSources)
                    ExcludedLineFacts = [int]$reportResult.Scope.ExcludedLineFacts
                })
            $stopwatch.Stop()
            $parseEndedAt = [DateTime]::UtcNow
            $totalParseMilliseconds += $stopwatch.Elapsed.TotalMilliseconds
            $semanticLineCount += [int]$reportResult.NewLineCount
            $memoryAfter = [System.Diagnostics.Process]::GetCurrentProcess().PrivateMemorySize64
            $reportTelemetry = [PSCustomObject]@{
                Type = "report"
                AppId = "$($descriptor.AppId)"
                Bytes = [long]$file.Length
                QueueWaitMilliseconds = ($parseStartedAt - [DateTime]$descriptor.EnqueuedAtUtc).TotalMilliseconds
                QueueDepthAtEnqueue = [int]$descriptor.QueueDepthAtEnqueue
                ParseMilliseconds = $stopwatch.Elapsed.TotalMilliseconds
                ParseStartedAtUtc = $parseStartedAt
                ParseEndedAtUtc = $parseEndedAt
                ExtractedLineCount = [int]$reportResult.ExtractedLineCount
                AcceptedLineCount = [int]$reportResult.AcceptedLineCount
                NewLineCount = [int]$reportResult.NewLineCount
                AggregateLineCount = $semanticLineCount
                MemoryBeforeBytes = [long]$memoryBefore
                MemoryAfterBytes = [long]$memoryAfter
            }
            $telemetry.Add($reportTelemetry)
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            Write-Host ("Code coverage compactor report {0}: size={1} MiB, queueWait={2}s, queueDepth={3}, parse={4}s, extracted={5}, accepted={6}, new={7}, aggregate={8}, memoryBefore={9} MiB, memoryAfter={10} MiB." -f
                $reportTelemetry.AppId,
                ($reportTelemetry.Bytes / 1MB).ToString("0.0", $culture),
                ($reportTelemetry.QueueWaitMilliseconds / 1000).ToString("0.000", $culture),
                $reportTelemetry.QueueDepthAtEnqueue,
                ($reportTelemetry.ParseMilliseconds / 1000).ToString("0.000", $culture),
                $reportTelemetry.ExtractedLineCount,
                $reportTelemetry.AcceptedLineCount,
                $reportTelemetry.NewLineCount,
                $reportTelemetry.AggregateLineCount,
                ($reportTelemetry.MemoryBeforeBytes / 1MB).ToString("0.0", $culture),
                ($reportTelemetry.MemoryAfterBytes / 1MB).ToString("0.0", $culture))
        }

        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        Write-CodeCoverageAggregateFile -path $temporaryPath -metadata $metadata `
            -runs @($runAssessments) -lines $semanticLines -rootOrder $semanticRootOrder
        $sha256 = Get-CodeCoverageFileSha256 -path $temporaryPath
        $validation = Read-CodeCoverageAggregate -path $temporaryPath `
            -expectedSha256 $sha256 `
            -expectedSourceRootFingerprint "$($metadata.SourceRootFingerprint)" `
            -ValidateOnly
        if (-not $validation.Valid -or $validation.LineCount -ne $semanticLineCount -or
            $validation.Runs.Count -ne $runAssessments.Count) {
            throw "The generated code coverage aggregate failed validation. $($validation.Reason)"
        }
        [System.IO.File]::Move($temporaryPath, $publishedPath, $true)
        $publishedFile = Get-Item -LiteralPath $publishedPath
        return @{
            Aggregate = @{
                Format = "al-go-line-union-binary-gzip"
                ContractVersion = 1
                Path = [System.IO.Path]::GetFileName($publishedPath)
                Sha256 = $sha256
                SourceRootFingerprint = "$($metadata.SourceRootFingerprint)"
                RunCount = $runAssessments.Count
                LineCount = $semanticLineCount
                SizeBytes = [long]$publishedFile.Length
                TotalParseMilliseconds = $totalParseMilliseconds
            }
            Telemetry = @($telemetry)
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
            Telemetry = @($workerResult.Telemetry)
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
            EnqueuedCount = 0
            Telemetry = @()
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
    $descriptor.EnqueuedAtUtc = [DateTime]::UtcNow
    $descriptor.QueueDepthAtEnqueue = [int]$worker.EnqueuedCount
    $descriptorJson = $descriptor | ConvertTo-Json -Depth 10 -Compress
    try {
        $worker.Input.WriteLine($descriptorJson)
        $worker.EnqueuedCount = [int]$worker.EnqueuedCount + 1
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
        $worker.Telemetry = @($result.Telemetry)
        $aggregate = @{}
        foreach ($property in @($result.Aggregate.PSObject.Properties)) {
            $aggregate[$property.Name] = $property.Value
        }
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
