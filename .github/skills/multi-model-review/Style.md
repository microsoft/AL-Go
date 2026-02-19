# PowerShell & AL-Go Style Guide

When reviewing AL-Go code changes, check for these conventions:

## Action Structure

- Each action lives in its own directory under `Actions/` (e.g. `Actions/DetermineArtifactUrl/`)
- Required files in every action directory:
  - `action.yaml` — GitHub Action metadata (inputs, outputs, runs configuration)
  - `[ActionName].ps1` — Main entry PowerShell script (name must match directory name)
  - `README.md` — Documentation for the action
- Optional files:
  - `[ActionName].psm1` — Reusable PowerShell module for complex/shared logic
  - Supporting directories for templates or resources
- Flag new actions that are missing any of the required files
- **Actions must call `Invoke-AlGoAction.ps1`** — the `action.yaml` should invoke
  `Invoke-AlGoAction.ps1 -ActionName "[ActionName]" -Action { ... }` rather than calling the
  PowerShell script directly. This wrapper provides telemetry, error handling, and consistent
  setup. Avoid inline PowerShell logic in `action.yaml` — keep it minimal and delegate to the
  `.ps1` script

## Script Structure

- Use `[Parameter(Mandatory = $true)]` for required parameters

## Function Design

- Write functions. Extract logic into well-named functions rather than long inline scripts
- If a function exceeds ~100 lines, consider splitting it into smaller, focused functions
- Each function should do one thing. If you find yourself writing a comment like
  "now do the second part", that's a signal to extract a function
- Complex logic should live in `.psm1` modules, not in the `.ps1` entry script
- Prefer extracting reusable functions into modules over duplicating logic across files

## Naming

- PascalCase for functions and parameters
- camelCase for local/loop variables
- Use approved PowerShell verbs: `Get-`, `Set-`, `New-`, `Test-`, `Invoke-` (not `Validate-`, `Check-`, etc.)

## Code Quality

- Use full cmdlet names, not aliases (`ForEach-Object` not `%`, `Where-Object` not `?`)
- Use `Join-Path` for all file paths — never concatenate with `\` or `/`
- Use `Write-Host` for logging, not `Write-Output`
- DateTime parsing must use `[System.Globalization.CultureInfo]::InvariantCulture`
- Prefer hashtable splatting for calls with 3+ parameters

## Cross-File Consistency

- Changes to `RunPipeline.ps1` may need mirroring in `AL-Go-Helper.ps1` (and vice versa)
- Template changes in `Per Tenant Extension` usually need mirroring in `AppSource App` (and vice versa)
- Settings defaults in `ReadSettings.psm1` must match `settings.schema.json`

## Settings System

- New settings need defaults in `ReadSettings.psm1`
- New settings need a schema entry in `settings.schema.json`
- New settings need documentation in `Scenarios/settings.md`

## Documentation & Release Notes

- If a PR adds new features, settings, or changes behavior, check that `RELEASENOTES.md` is updated
- When referencing workflows in release notes, use the display name (e.g., "Update AL-Go System
  Files") not the filename (e.g., "UpdateGitHubGoSystemFiles")
- New or changed settings must be documented in `Scenarios/settings.md` with a proper anchor ID
  matching the camelCase setting name
- New actions need a `README.md` in their action directory
- Flag PRs that add user-facing changes without corresponding documentation updates

## Workflows

- Workflow files need explicit least-privilege `permissions` — no `read-all` or `write-all`
- No hardcoded repository names or org-specific values in template workflows

## PR Description Quality

A good PR description is essential for reviewers and future maintainers. Flag PRs with missing
or low-quality descriptions. A PR description should include:

- **What** — a clear summary of what the PR does and why
- **How** — brief explanation of the approach taken, especially for non-obvious design decisions
- **Testing** — how the changes were tested (manual steps, new/updated tests, scenarios covered)
- **Breaking changes** — if the PR changes behavior, APIs, settings, or workflow inputs, call it
  out explicitly so downstream users know what to expect
- If the PR is linked to a GitHub issue, the description should reference it (e.g., `Fixes #123`)
