# Error Handling & Logging Review Checklist

When reviewing AL-Go code changes, check for proper error handling and logging practices.

## Error Handling Patterns

### try/catch/finally

- Long-running operations, API calls, file I/O, and external tool invocations should be wrapped
  in `try`/`catch` blocks
- Use `finally` for cleanup (temp files, `Pop-Location`, container removal) — ensures cleanup runs
  even on failure
- `catch` blocks should provide actionable error messages, not just re-throw silently
- When catching and re-throwing, preserve the original error context:
  ```powershell
  catch {
      throw "Failed to download dependency from $cleanUrl. Error: $($_.Exception.Message)"
  }
  ```
- Avoid empty `catch` blocks — at minimum log a warning or debug message explaining why the error
  is suppressed

### Error messages

- Error messages should help the user diagnose the problem — include what was being attempted,
  what failed, and ideally what to do about it
- Never include secrets or sensitive URLs in error messages — use a "clean" version of the URL
  (e.g., with `${{ }}` placeholders intact instead of resolved secret values)
- Use `OutputError` for errors that should appear as GitHub annotations on the workflow run
- Use `throw` for fatal errors that should stop execution

### Graceful degradation

- Non-critical operations should warn and continue rather than failing the entire workflow
- Use `OutputWarning` for recoverable issues, `OutputError` for blocking issues
- Consider whether a failure should stop the entire pipeline or just skip one step

### Resource cleanup

- Temp folders, containers, downloaded files — ensure cleanup in `finally` blocks
- `Push-Location` must always have a matching `Pop-Location` in a `finally` block
- If creating containers or VMs, ensure they are cleaned up even on failure

## Logging & Observability

### Log levels — use the right helper function

AL-Go has specific output helper functions. Use them consistently:

| Function | Purpose | GitHub effect |
|----------|---------|---------------|
| `Write-Host` | General informational logging | Visible in logs |
| `OutputDebug` | Detailed diagnostic info (only visible when debug logging is enabled) | Debug log |
| `OutputWarning` | Recoverable issues the user should know about | ⚠️ Warning annotation |
| `OutputError` | Blocking issues | ❌ Error annotation |
| `OutputNotice` | Informational notices | ℹ️ Notice annotation |
| `Trace-Information` | Telemetry events sent to Application Insights | Not visible in logs |

- **Do NOT use `Write-Output`** — it pollutes the pipeline and can cause unexpected behavior
- **Do NOT use `Write-Warning` or `Write-Error`** directly — use the AL-Go wrapper functions
  (`OutputWarning`, `OutputError`) which handle formatting consistently
- Annotation keywords must be **lowercase** — `::warning::` not `::Warning::`

### Log grouping

- Use `::group::` and `::endgroup::` to organize log output into collapsible sections:
  ```powershell
  Write-Host "::group::Downloading dependencies"
  # ... download logic ...
  Write-Host "::endgroup::"
  ```
- Each major phase of an action should be wrapped in a group for readability
- Keep group names descriptive and concise

### Telemetry

- Significant action milestones should emit `Trace-Information` events for Application Insights
- `Invoke-AlGoAction.ps1` automatically traces action start — add telemetry for important
  decision points or completion events within the action
- Use `Add-TelemetryProperty` to attach structured data to telemetry events
- Never include secrets or PII in telemetry data

### What to log

- Log the **inputs** at the start of an action (settings, parameters, environment)
- Log **decisions** — when code takes a branch based on a condition, log which branch and why
- Log **outcomes** — what was downloaded, built, deployed, skipped
- Don't log **secrets**, **full file contents**, or **large JSON blobs** — use `OutputDebug` for
  verbose data that's only needed when troubleshooting
