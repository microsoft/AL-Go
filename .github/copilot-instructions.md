# Copilot Instructions for AL-Go

## Project Overview

AL-Go for GitHub is a set of GitHub Actions and Templates for building, testing, and deploying Business Central extensions using GitHub workflows. It consists of PowerShell actions, reusable YAML workflows, and Pester-based unit tests.

## PowerShell Conventions

### Error Handling

- Every action script must start with the standard header:
  ```powershell
  $errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
  ```
- Use `try/catch/finally` with structured error propagation.
- Check `$LASTEXITCODE` after running external commands.
- Use `Write-Host "::Error::<message>"` for GitHub Actions error annotations.
- Use `Write-Host "::Warning::<message>"` for non-blocking warnings.

### JSON Processing

- Always use `ConvertTo-HashTable -recurse` after `ConvertFrom-Json` to ensure nested objects and arrays are converted to hashtables for consistent access.
- Always specify `-Encoding UTF8` when reading or writing JSON files.

### Function Declarations

- Use PascalCase for function names and camelCase for variables.

### Module Loading

- Import modules with explicit paths: `Join-Path $PSScriptRoot` pattern.
- Use `-Force -DisableNameChecking` for re-imports.

## Security Patterns

### Secret Handling

- Mask secrets with `Write-Host "::add-mask::$secret"` before any output.
- Never log raw secrets; use clean/placeholder URLs in error messages.
- Be aware that secrets in URLs use `${{ secretName }}` syntax — replacement is done before use.
- URL-encode secret values when injecting into URLs.

### Input Sanitization

- Sanitize filenames using `[System.IO.Path]::GetInvalidFileNameChars()`.
- Check for path traversal using `Test-PathWithinWorkspace` or equivalent.
- Sanitize container names with `-replace "[^a-z0-9\-]"`.

### Authentication

- Never hardcode credentials or tokens in source code.
- Use GitHub secrets or Azure KeyVault for credential storage.

## YAML Workflow Conventions

- Declare minimal required permissions (e.g., `contents: read`, `actions: read`).
- Use `defaults.run.shell: pwsh` for cross-platform compatibility.
- Prefix internal environment variables with `_` to distinguish from GitHub context.
- Use `${{ needs.JobName.outputs.key }}` for cross-job communication.
- Add `::Notice::` steps when conditionally skipping workflow steps.

## Testing Requirements

- All new functions must have Pester unit tests in the `Tests/` folder.
- Test files follow the naming convention `*.Test.ps1`.
- Use `Describe`/`It` blocks with descriptive names.
- Mock external dependencies to isolate units under test.
- Tests must pass on both Windows (PowerShell 5) and Linux (PowerShell 7).
- Use `InModuleScope` for testing private module functions.

## Documentation Requirements

- All new or modified AL-Go settings must be:
  - Documented in `Scenarios/settings.md` with a clear description, type, default/required status, valid values (e.g., enum), and which templates/workflows honor the setting.
  - Added or updated in the settings schema (`Actions/.Modules/settings.schema.json`) with aligned `description`, `type`, `enum`, `default`, and `required` metadata.
  - Marked as deprecated in both `Scenarios/settings.md` and the schema description when applicable, with guidance on the replacement setting, and listed in `DEPRECATIONS.md`.
- New public functions (in `.ps1` / `.psm1` files, or used as entry points from workflows) should include comment-based help with at least `.SYNOPSIS` and, when appropriate, `.DESCRIPTION`, `.PARAMETER`, and `.EXAMPLE` blocks. Parameter names and descriptions in the help should stay in sync with the function signature.
- When adding new user-facing behaviors, workflows, or commands:
  - Update the relevant scenario(s) under `Scenarios/` or the appropriate `README.md` so users can discover and understand the change.
  - Call out breaking changes and notable new capabilities in `RELEASENOTES.md`.

## Deprecated Features

Before using or accepting settings, check `DEPRECATIONS.md` for deprecated settings:

- `unusedALGoSystemFiles` → use `customALGoFiles.filesToExclude`
- `alwaysBuildAllProjects` → use `incrementalBuilds.onPull_Request`
- `<workflow>Schedule` → use `workflowSchedule` with conditional settings
- `cleanModePreprocessorSymbols` → use `preprocessorSymbols` with conditional settings

## Cross-Platform Considerations

- Use `[System.IO.Path]::DirectorySeparatorChar` instead of hardcoded separators.
- Account for PowerShell 5 vs 7 differences (e.g., encoding parameters, `$IsWindows`).
- Use `Replace('\', '/')` for path normalization in URLs and artifact names.

## Pull Request Checklist

When reviewing PRs, verify:

- [ ] Standard error handling header is present in new scripts
- [ ] Secrets are masked before any output
- [ ] JSON is converted with `ConvertTo-HashTable -recurse`
- [ ] File encoding is explicitly specified
- [ ] Unit tests are added or updated
- [ ] RELEASENOTES.md is updated for user-facing changes
- [ ] No deprecated settings are introduced
- [ ] YAML workflows declare minimal permissions
- [ ] Cross-platform compatibility is maintained
- [ ] New or changed settings are documented in `Scenarios/settings.md` and reflected in `Actions/.Modules/settings.schema.json` with consistent metadata
- [ ] New public functions have appropriate comment-based help and any new workflows/user-facing behaviors are documented in scenarios/READMEs
