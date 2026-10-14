# ---------------------------------------------------------------------------
# Run Copilot CLI
# ---------------------------------------------------------------------------
function Invoke-CopilotCli {
    param([string] $Prompt)

    # -p / --prompt puts the CLI in non-interactive prompt mode and emits
    # only the model's final response to stdout (no interactive TUI markers
    # like '● Read foo' or '└ N lines read'). Sending the prompt via stdin
    # instead leaves the CLI in interactive mode, which renders the live
    # tool-call UI to stdout and breaks downstream JSON parsing.
    # The reviewer gets only native read tools plus a path-scoped write grant
    # for its structured report. The original repository is never mounted.
    $copilotArgs = @(
        '--no-custom-instructions',
        '--no-color',
        '--log-level', $CopilotLogLevel,
        '--add-dir', $ReviewDataRoot,
        '--add-dir', $ReviewOutputDir,
        '-p', $Prompt
    )
    $copilotArgs = @(
        Get-CopilotSecurityArguments -WritablePath (Join-Path $AgentWorkDir $ReportFileName)
    ) + $copilotArgs
    # On GitHub Enterprise the CLI must be pointed at the host that issued the
    # token; github.com stays the CLI default and gets no flag.
    if (Test-GitHubEnterpriseHost -ServerUrl $GitHubServerUrl) {
        $copilotArgs = @('--host', $GitHubServerUrl) + $copilotArgs
    }
    $copilotArgs = @('--plugin-dir', $BCQualityRoot, '--add-dir', $BCQualityRoot) + $copilotArgs
    if ($CopilotModel) { $copilotArgs += "--model=$CopilotModel" }

    # Pass only a safe allowlist of environment variables to the subprocess.
    $cleanEnv = New-CopilotChildEnvironment `
        -ReviewSource $ReviewSource `
        -CopilotToken $CopilotToken `
        -CopilotGithubToken $CopilotGithubToken `
        -CiValue ([System.Environment]::GetEnvironmentVariable('CI')) `
        -GitHubServerUrl $GitHubServerUrl
    $cleanEnv['COPILOT_OTEL_ENABLED'] = 'true'
    $cleanEnv['COPILOT_OTEL_EXPORTER_TYPE'] = 'file'
    $cleanEnv['COPILOT_OTEL_FILE_EXPORTER_PATH'] = $CopilotOtelPath
    $cleanEnv['OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT'] = 'false'

    $transcriptBuilder = [System.Text.StringBuilder]::new()
    $process   = $null
    $processStarted = $false
    $startedAt = [DateTime]::UtcNow
    $script:CurrentCopilotInvocationStartedAt = $startedAt

    try {
        if (-not $script:CopilotExecutable) {
            throw 'Copilot CLI compatibility was not initialized before starting root consolidation.'
        }

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName               = $script:CopilotExecutable
        $startInfo.UseShellExecute        = $false
        $startInfo.CreateNoWindow         = $true
        $startInfo.RedirectStandardInput  = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError  = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        if (-not (Test-Path -LiteralPath $AgentWorkDir)) { $null = New-Item -ItemType Directory -Path $AgentWorkDir -Force }
        $startInfo.WorkingDirectory       = $AgentWorkDir

        foreach ($arg in $copilotArgs) { $startInfo.ArgumentList.Add($arg) }

        $startInfo.EnvironmentVariables.Clear()
        foreach ($kv in $cleanEnv.GetEnumerator()) {
            $startInfo.EnvironmentVariables[$kv.Key] = $kv.Value
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        # Read stdout/stderr via async Task readers rather than
        # OutputDataReceived. Previous Register-ObjectEvent + -Action handlers
        # queued callbacks on a PowerShell pipeline thread that WaitForExit()
        # does not synchronize with, so the StringBuilders could be (and
        # were) read while the final batch of stdout lines was still
        # pending -- the agent's JSON response then arrived AFTER we had
        # already parsed an empty builder, and the parser failed on the
        # noisy TUI prefix.
        #
        # Direct add_OutputDataReceived doesn't work either: PowerShell
        # scriptblocks need a Runspace and .NET fires those events on
        # threadpool threads that don't have one.
        #
        # ReadToEndAsync() returns Tasks that complete only when the OS pipe
        # is closed (i.e. the child has exited and flushed). Waiting on
        # them after WaitForExit() guarantees we have the full output.
        $null = $process.Start()
        $processStarted = $true
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($CopilotCliTimeoutMinutes -eq 0) {
            $process.WaitForExit()
            $completed = $true
        }
        else {
            $timeoutMs = $CopilotCliTimeoutMinutes * 60 * 1000
            $completed = $process.WaitForExit($timeoutMs)
        }
        if (-not $completed) {
            throw "Copilot CLI timed out after $CopilotCliTimeoutMinutes minutes."
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        # Echo the full captured output now that the child has exited and
        # both streams are fully drained. The CLI does not actually stream
        # incrementally in non-interactive mode -- everything lands in one
        # final burst at exit -- so dumping it here loses no liveness.
        foreach ($line in ($stdout -split "`r?`n")) {
            if ($line) {
                [void]$transcriptBuilder.AppendLine("out: $line")
                [Console]::Out.WriteLine($line)
            }
        }
        foreach ($line in ($stderr -split "`r?`n")) {
            if ($line) {
                [void]$transcriptBuilder.AppendLine("err: $line")
                [Console]::Out.WriteLine("[copilot-err] $line")
            }
        }

        $elapsed = [DateTime]::UtcNow - $startedAt
        Write-LogPhaseDetail "Copilot CLI exited with code $($process.ExitCode) after $(Format-Duration $elapsed)."

        $script:AgentTranscript += $transcriptBuilder.ToString()

        if ($process.ExitCode -ne 0) {
            Write-LogErr 'Copilot CLI failed' "Copilot CLI exited with code $($process.ExitCode)"
            throw "Copilot CLI exited with code $($process.ExitCode)"
        }

        $output = if ($stdout.Trim()) { $stdout } else { $stderr }
        if (-not $output.Trim()) {
            Write-Warning 'Copilot CLI returned no output'
            return '{}'
        }

        return $output
    }
    finally {
        Complete-CopilotProcess `
            -Process $process `
            -ProcessStarted $processStarted `
            -HarvestAction { Save-CurrentCopilotRunMetrics }
    }
}
