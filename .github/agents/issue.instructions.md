# Instructions for Cloud Agents Working on AL-Go Issues

You are an AI agent assigned to an issue in the **AL-Go for GitHub** repository. Your job is to understand the issue, implement a solution, and open a pull request. Follow these instructions carefully.

---

## 1. Before You Start

1. **Read the issue thoroughly.** Understand the problem or feature request, including any linked issues, discussions, or referenced files.
2. **Read `.github/copilot-instructions.md`** — it contains project-wide coding conventions (PowerShell style, error handling, JSON processing, security, YAML, testing, and documentation requirements). Everything in that file applies to your work.
3. **Check `DEPRECATIONS.md`** before using or introducing any settings. Do not use deprecated settings.
4. **Explore the relevant area of the codebase** before writing code. Understand how similar features are implemented.

---

## 2. Required Checklist for Every PR

Before opening your pull request, verify each of the following:

### Release Notes

- [ ] If your changes affect AL-Go actions, templates, reusable workflows, or supporting PowerShell scripts, **update `RELEASENOTES.md`** at the top of the file with a concise description of the change.
- [ ] If the change is a bug fix for a reported issue, add it under the `### Issues` section in the format: `- Issue <number> - <description>`.
- [ ] If the change introduces a new capability, add a new section heading with a description.

### Tests

- [ ] **Add or update Pester unit tests** in the `Tests/` folder for any new or changed PowerShell functions.
- [ ] Test file names must follow the pattern `*.Test.ps1` (e.g., `MyAction.Test.ps1` or `MyAction.Action.Test.ps1`).
- [ ] Use `Describe`/`It` blocks with descriptive names. Mock external dependencies.
- [ ] Ensure tests pass on **both Windows (PowerShell 5) and Linux (PowerShell 7)**. Avoid hardcoded path separators (`\`); use `[System.IO.Path]::DirectorySeparatorChar` or forward slashes where appropriate.
- [ ] If you add a new action, check whether an existing `TestActionsHelper.psm1` pattern applies (see existing test files for examples).

### Documentation

- [ ] If you add or modify a setting, document it in **`Scenarios/settings.md`** (description, type, default, valid values, which templates honor it) and update the schema in **`Actions/.Modules/settings.schema.json`**.
- [ ] If you add a new user-facing workflow, scenario, or behavior, add or update the relevant scenario document under `Scenarios/` or the appropriate `README.md`.
- [ ] New public functions should include PowerShell comment-based help (`.SYNOPSIS` at minimum).

### Code Quality

- [ ] Every new PowerShell script must start with the standard header:
  ```powershell
  $errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
  ```
- [ ] Mask secrets with `Write-Host "::add-mask::$secret"` before any output.
- [ ] Use `ConvertTo-HashTable -recurse` after `ConvertFrom-Json`.
- [ ] Specify `-Encoding UTF8` when reading or writing files.
- [ ] YAML workflows must declare minimal permissions and use `defaults.run.shell: pwsh`.

### PR Hygiene

- [ ] Reference the issue number in the PR description (e.g., `Fixes #1234` or `Related to issue: #1234`).
- [ ] Follow the PR template in `.github/pull_request_template.md`.
- [ ] Keep changes focused — one logical change per PR.

---

## 3. Repository Architecture

Understanding the repository layout is essential for making correct changes.

### Top-Level Structure

```
AL-Go/
├── Actions/              # GitHub composite actions (PowerShell + action.yaml)
├── Templates/            # Workflow templates for consumer repositories
│   ├── Per Tenant Extension/   # PTE template
│   └── AppSource App/          # AppSource template
├── Tests/                # Pester unit tests
├── e2eTests/             # End-to-end tests (run in CI, not locally)
├── Scenarios/            # User-facing documentation for settings and scenarios
├── RELEASENOTES.md       # Release notes (update for user-facing changes)
├── DEPRECATIONS.md       # Deprecated features and migration guidance
└── .github/
    ├── workflows/        # CI and repo-management workflows
    ├── copilot-instructions.md  # Coding conventions
    └── pull_request_template.md
```

### Actions (`Actions/`)

Each action lives in its own subfolder and follows this structure:

```
Actions/
├── <ActionName>/
│   ├── action.yaml       # GitHub Action definition (composite action)
│   ├── <ActionName>.ps1  # Main PowerShell script for the action
│   └── README.md         # (optional) Action documentation
├── Invoke-AlGoAction.ps1 # Shared entry point that wraps action execution with telemetry
├── AL-Go-Helper.ps1      # Shared helper functions loaded by all actions
├── Github-Helper.psm1    # GitHub API helper module
├── TelemetryHelper.psm1  # Telemetry module
├── .Modules/             # Shared modules used across actions
│   ├── ReadSettings.psm1
│   ├── CompileFromWorkspace.psm1
│   ├── DebugLogHelper.psm1
│   ├── WorkflowPostProcessHelper.psm1
│   └── settings.schema.json  # JSON schema for AL-Go settings
└── MarkDownHelper.psm1   # Markdown generation helper
```

**Action anatomy:**
- `action.yaml` defines inputs, outputs, and a composite `runs` block.
- The `runs` block calls `Invoke-AlGoAction.ps1`, which wraps the action script with error handling and telemetry.
- Input parameters are passed via environment variables (prefixed with `_`) to avoid injection.
- The action script (`.ps1`) dot-sources `AL-Go-Helper.ps1` for shared functions.

### Templates (`Templates/`)

Templates contain the workflow files that get deployed to consumer repositories. There are two variants:

- **Per Tenant Extension** — for PTE apps (includes Power Platform workflows).
- **AppSource App** — for AppSource apps (includes `PublishToAppSource` workflow).

Both templates share most workflows. Key workflows include:
- `CICD.yaml` — main CI/CD pipeline triggered on push.
- `PullRequestHandler.yaml` — PR validation pipeline.
- `_BuildALGoProject.yaml` — reusable build workflow (called by CICD and PR workflows).
- `CreateRelease.yaml`, `PublishToEnvironment.yaml`, etc. — release and deployment workflows.

**Important:** When you change a reusable workflow or template workflow, the change must be consistent across both template variants. Check whether the same workflow file exists in both `Per Tenant Extension` and `AppSource App` and update both if needed.

### Tests (`Tests/`)

- Unit tests use **Pester** and follow the naming convention `*.Test.ps1`.
- `TestActionsHelper.psm1` provides utilities for testing action scripts.
- Tests run on both `windows-latest` (PowerShell 5) and `ubuntu-latest` (PowerShell 7) via `.github/workflows/CI.yaml`.
- `WorkflowSanitation/` contains tests that validate workflow YAML files.
- `MarkdownLinks/` contains tests that validate documentation links.

### Shared Modules (`Actions/.Modules/`)

Reusable PowerShell modules shared across multiple actions:
- `ReadSettings.psm1` — reads and merges settings from multiple sources.
- `settings.schema.json` — JSON Schema for all AL-Go settings; keep this in sync with `Scenarios/settings.md`.

---

## 4. How to Add a New Feature

This section describes the typical steps for implementing a full feature in AL-Go.

### 4.1 Adding or Modifying a Setting

1. **Define the setting** in `Actions/.Modules/ReadSettings.psm1` (add to the defaults hashtable if it needs a default value).
2. **Add the setting to the JSON schema** in `Actions/.Modules/settings.schema.json` with proper `type`, `description`, `default`, and `enum` (if applicable).
3. **Document the setting** in `Scenarios/settings.md` with a description, type, default value, and which workflows/templates use it.
4. **Read the setting** in the relevant action script using the `$settings` hashtable (populated by `ReadSettings`).
5. **Add tests** in `Tests/ReadSettings.Test.ps1` or the relevant action test file to verify the setting is read and applied correctly.

### 4.2 Adding a New Action

1. **Create the action folder** under `Actions/<ActionName>/`.
2. **Create `action.yaml`** following the composite action pattern (see existing actions for reference). Use environment variables (prefixed with `_`) for inputs.
3. **Create `<ActionName>.ps1`** — the main script. Dot-source `AL-Go-Helper.ps1` at the top. Use the `Invoke-AlGoAction.ps1` wrapper in `action.yaml`.
4. **Add unit tests** in `Tests/<ActionName>.Test.ps1` or `Tests/<ActionName>.Action.Test.ps1`.
5. **Update the relevant template workflows** if the action needs to be called from a workflow.
6. **Update `RELEASENOTES.md`** with a description of the new action.

### 4.3 Adding or Modifying a Workflow

1. **Identify which template(s) need the workflow** — PTE, AppSource, or both.
2. **Create or edit the workflow YAML** in `Templates/<template>/.github/workflows/`.
3. **Follow YAML conventions:** declare minimal permissions, use `defaults.run.shell: powershell` (the default for AL-Go template workflows), prefix internal env vars with `_`.
4. **If the workflow is reusable** (starts with `_`), ensure it has proper `workflow_call` inputs/outputs.
5. **Add sanitation tests** if the workflow has structural requirements (see `Tests/WorkflowSanitation/`).
6. **Ensure consistency** — if a workflow exists in both templates, update both.

### 4.4 Modifying Shared Helpers

When modifying `AL-Go-Helper.ps1`, `Github-Helper.psm1`, or modules in `.Modules/`:
1. **Check all callers** — these files are used by many actions. Search for usages before changing function signatures.
2. **Maintain backward compatibility** — use optional parameters with defaults.
3. **Add tests** for new or changed functions.

---

## 5. Common Pitfalls

- **Forgetting to update both templates.** If a workflow or configuration file exists in both `Per Tenant Extension` and `AppSource App`, you must update both.
- **Hardcoded path separators.** Use `[System.IO.Path]::DirectorySeparatorChar` or normalize paths with `Replace('\', '/')`. Tests run on both Windows and Linux.
- **PowerShell 5 vs 7 differences.** Test on both. Common issues: `-AsHashtable` is not available in PS5 (use `ConvertTo-HashTable` instead), `$IsWindows` is only defined in PS7.
- **Missing `-Encoding UTF8`.** Always specify encoding when reading/writing files.
- **Not masking secrets.** Any value that could be a secret must be masked with `::add-mask::` before it appears in output.
- **Introducing deprecated settings.** Always check `DEPRECATIONS.md` before using settings.
- **Not updating the schema.** If you add a setting to code but not to `settings.schema.json`, schema validation tests will fail.

---

## 6. Running Tests Locally

You can run the Pester unit tests locally:

```powershell
# Run all unit tests
. ./Tests/runtests.ps1 -Path "Tests"

# Run workflow sanitation tests
. ./Tests/runtests.ps1 -Path "Tests/WorkflowSanitation"

# Run markdown link tests
. ./Tests/runtests.ps1 -Path "Tests/MarkdownLinks"
```

Tests must pass on both PowerShell 5 (Windows) and PowerShell 7 (cross-platform).

---

## 7. Summary

When working on an issue:
1. Understand the issue and explore the relevant code.
2. Make focused, minimal changes that fully address the issue.
3. Add or update tests.
4. Update documentation (`RELEASENOTES.md`, `Scenarios/settings.md`, schema, scenarios).
5. Follow all conventions in `.github/copilot-instructions.md`.
6. Reference the issue in your PR.
