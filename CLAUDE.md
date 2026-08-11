# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AL-Go for GitHub is a set of GitHub Actions and reusable YAML workflow templates for building, testing, and deploying Business Central (AL) extensions. It consists of PowerShell actions (`Actions/`), workflow templates for two repo types (`Templates/`), and Pester-based unit tests (`Tests/`) plus end-to-end tests (`e2eTests/`).

This repo is the **source** for AL-Go. On every release it is deployed into three downstream repos that users actually consume:

- `microsoft/AL-Go-PTE` — template repo for Per Tenant Extensions (deployed from `Templates/Per Tenant Extension`)
- `microsoft/AL-Go-AppSource` — template repo for AppSource apps (deployed from `Templates/AppSource App`)
- `microsoft/AL-Go-Actions` — contains the composite actions from `Actions/`

Changes here don't take effect for end users until a release/deploy; when reasoning about "what a user's workflow does," follow the templates under `Templates/`, which reference actions via `microsoft/AL-Go-Actions@<ref>`.

## Commands

### Unit tests (PowerShell/Pester)

```powershell
# Run all unit tests
pwsh -File Tests/runtests.ps1 -Path Tests

# Run a single test file directly (from repo root)
Invoke-Pester -Path Tests/ReadSettings.Test.ps1

# Or open Tests/runtests.ps1 in VS Code and select "Run"
```

Tests run on both Windows (PowerShell 5) and Linux (PowerShell 7) in CI — avoid PS7-only syntax in shared modules. Test files follow `*.Test.ps1`, one per action/module, using `Describe`/`It`/`Mock`/`InModuleScope`.

### Pre-commit / linting

```bash
pre-commit run --all-files
```

Hooks: `mdformat` (with `--end-of-line=keep`), standard pre-commit-hooks (JSON/YAML/XML validation, large file/merge-conflict/private-key checks, EOF/whitespace fixers), and `gitleaks` for secret scanning.

### End-to-end tests

Live in `e2eTests/`, require a GitHub org with self-hosted runners and specific secrets/variables (see `Scenarios/Contribute.md`). Three kinds:

- `Test-AL-Go.ps1` — full E2E scenario, run in `E2E.yaml` across Public/Private × Windows/Linux × Single/Multi-project × PTE/AppSource
- `Test-AL-Go-Upgrade.ps1` — upgrade scenario, tests upgrading from every prior AL-Go release
- `e2eTests/scenarios/*/runtests.ps1` — targeted scenario tests (e.g. `UseProjectDependencies`, `GitHubPackages`, `SpecialCharacters`)

Not runnable without the org/secrets setup above; don't attempt to run these locally without that context.

## Architecture

### Actions are composite actions, driven by shared PowerShell modules

Each folder under `Actions/` is a GitHub composite action (`action.yaml` + a `.ps1` entry point). Shared logic lives in `Actions/.Modules/` (`ReadSettings.psm1`, `CompileFromWorkspace.psm1`, `CheckForWarningsUtils.psm1`, `WorkflowPostProcessHelper.psm1`, `DebugLogHelper.psm1`) and in root-level helpers: `Actions/AL-Go-Helper.ps1` (core shared functions, ~2500 lines), `Actions/Github-Helper.psm1` (GitHub API interactions), `Actions/TelemetryHelper.psm1`, `Actions/MarkDownHelper.psm1`. Actions import these via `Join-Path $PSScriptRoot`.

### Settings are layered, not flat

Settings are resolved (in `ReadSettings.psm1`) from multiple files merged in this precedence order:

1. `.github/AL-Go-Settings.json` — repository settings
1. `<project>/.AL-Go/settings.json` — project settings
1. `.github/<workflowName>.settings.json` — workflow settings
1. `<project>/.AL-Go/<workflowName>.settings.json` — project + workflow settings
1. `<project>/.AL-Go/<userName>.settings.json` — per-user settings

Later entries override earlier ones. The schema for all settings lives in `Actions/.Modules/settings.schema.json`, and every setting is documented in `Scenarios/settings.md`. **These two must be kept in sync** — new/changed settings need matching `description`/`type`/`enum`/`default`/`required` in both places, plus deprecation notes in `DEPRECATIONS.md` when replacing an old setting.

Known deprecated settings (see `DEPRECATIONS.md` for full list/replacements): `unusedALGoSystemFiles` → `customALGoFiles.filesToExclude`, `alwaysBuildAllProjects` → `incrementalBuilds.onPull_Request`, `<workflow>Schedule` → `workflowSchedule`, `cleanModePreprocessorSymbols` → `preprocessorSymbols`.

### Two templates, one workflow shape

`Templates/Per Tenant Extension` and `Templates/AppSource App` each contain a full `.github/workflows/` set (CICD, CreateRelease, CreateApp, IncrementVersionNumber, Troubleshooting, UpdateGitHubGoSystemFiles, etc.), plus `_BuildALGoProject.yaml` and `_BuildPowerPlatformSolution.yaml` as reusable/callable sub-workflows. These YAML files are the actual entry points a downstream user's repo runs — they call back into the composite actions in `Actions/` (referenced as `microsoft/AL-Go-Actions@<ref>` once deployed).

### PowerShell conventions (enforced across this codebase)

- Every action script starts with: `$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0`
- Use `try/catch/finally`; check `$LASTEXITCODE` after external commands
- `Write-Host "::Error::<message>"` / `"::Warning::"` for GitHub Actions annotations; `::Notice::` when conditionally skipping steps
- After `ConvertFrom-Json`, always pipe through `ConvertTo-HashTable -recurse` for consistent nested access
- Always specify `-Encoding UTF8` on JSON file read/write
- PascalCase functions, camelCase variables
- Re-imports use `-Force -DisableNameChecking`

### Security patterns

- Mask secrets immediately with `Write-Host "::add-mask::$secret"`; never log raw secrets or full URLs containing them (use `${{ secretName }}` placeholders, URL-encode secret values)
- Never hardcode credentials — use GitHub secrets or Azure KeyVault
- Sanitize filenames via `[System.IO.Path]::GetInvalidFileNameChars()`; check path traversal (`Test-PathWithinWorkspace` or equivalent); sanitize container names with `-replace "[^a-z0-9\-]"`

### Cross-platform

- Use `[System.IO.Path]::DirectorySeparatorChar`, not hardcoded separators
- Use `Replace('\', '/')` when normalizing paths for URLs/artifact names
- Account for PS5 vs PS7 differences (encoding params, `$IsWindows`) since Windows/PS5 and Linux/PS7 both run in CI

### YAML workflow conventions

- Declare minimal `permissions` (e.g. `contents: read`, `actions: read`)
- `defaults.run.shell: pwsh` for cross-platform steps
- Prefix internal env vars with `_` to distinguish from GitHub context vars
- Cross-job data via `${{ needs.JobName.outputs.key }}`

## Documentation requirements when changing behavior

- New/modified settings: update `Scenarios/settings.md` **and** `Actions/.Modules/settings.schema.json` together
- New public functions (`.ps1`/`.psm1` entry points): comment-based help with at least `.SYNOPSIS`
- New user-facing workflows/behaviors: update the relevant `Scenarios/*.md` or `README.md`
- Breaking changes / notable new capabilities: call out in `RELEASENOTES.md`
- New functions/bug fixes: add or update Pester tests in `Tests/`

## This is Stefan's fork of `microsoft/AL-Go` — three rules govern everything here

This repo (`StefanMaron/AL-Go`) is a fork used to add fleet-wide features — currently the **Linux fast lane** (`Scenarios/LinuxFastLane.md`, a `linuxFastLane` setting that runs builds against a Linux BC container instead of the full Windows pipeline, wired into both `PullRequestHandler.yaml` and `CICD.yaml` so it applies to PR builds and to regular push/manual CI/CD builds) — for a fleet of managed AL repos (ABC customers and others). Any change here, or any change to how a downstream repo consumes this fork, must satisfy all three:

1. **Drop-in, non-invasive for downstream repos.** New fork behavior must be opt-in-settings-only (e.g. `linuxFastLane` + `ConditionalSettings`), never a required restructure. `main` in a downstream repo never opts in — only PRs and non-production/test branches do.
1. **Stay cleanly mergeable from `microsoft/AL-Go`.** Never rebase/rewrite already-pushed history on this fork's `main` — only append fork commits on top, and keep them additive (new files, or new job/step blocks gated by an `if:`) rather than rewriting existing upstream logic in place. This is what keeps `git merge upstream/main` conflict-free going forward.
1. **Trivially revertible per downstream repo.** A repo goes back to stock Microsoft AL-Go by repointing `templateUrl` to `microsoft/AL-Go-PTE@main` (or `AppSource@main`) and rerunning "Update AL-Go System Files." Leftover fork-only setting keys are harmless — root `settings.schema.json` has no `additionalProperties: false`, and `ValidateSettings` (`Actions/.Modules/ReadSettings.psm1`) only warns on schema mismatch, never fails a build.

**Deploy mechanics**: `Deploy.yaml` + `Internal/Deploy.ps1` push `Templates/*` to `<owner>/AL-Go-PTE` and `<owner>/AL-Go-AppSource` (auto-created via `gh repo create` if missing, though the `stefanmaronapp` GitHub App used for auth here lacks account-level "Administration" permission and can't actually create repos — pre-create them manually first if needed). For any non-`microsoft` repo owner, Actions references in the deployed workflows are rewritten to point directly at this fork's own SHA/branch — there is no separate Actions-repo deploy target for a fork.

**Status (2026-08-07): live.** `StefanMaron/AL-Go-PTE` and `AL-Go-AppSource` are deployed at merge commit `7f21177b`. First onboarded repo: `Stefan-Maron-Consulting/Pageworks`.

**Deploy auto-runs on `main`.** `Deploy.yaml` has a `push` trigger (paths: `Templates/**`, `Actions/**`) in addition to `workflow_dispatch`, so every merge to `main` that touches those paths redeploys to `AL-Go-PTE`/`AppSource` with **no review gate** (`directCommit=true` on the auto-triggered path — Stefan's explicit choice, 2026-08-07). This means: **merging a PR to `main` is the real release step on this fork** — there's no separate "are you sure" before it goes live on the template repos. Treat PR review on `main` accordingly. It does NOT touch any downstream repo that consumes the templates (Pageworks, future onboarded repos) — those only update when *they* run their own "Update AL-Go System Files" (manually, or on whatever `workflowSchedule`/org-level cron they have configured — see `Scenarios/settings.md#workflowschedule`).

Full onboarding/revert/fork-sync runbook lives in `.claude/skills/linux-fast-lane-onboarding/SKILL.md` **in this repo** — it's a Claude Code skill, checked in so anyone working from a checkout of this fork gets it for free (Claude Code auto-discovers project-scoped skills), not just Stefan's local machine (his `~/.claude/skills/linux-fast-lane-onboarding` is a symlink to this file). Point a fresh/cloud agent at this file instead of rediscovering this from scratch. Before trusting any "is X deployed/onboarded" claim from it, verify against the actual repos (`gh repo view <owner>/AL-Go-PTE`, check the target repo's `templateUrl`) — this state changes as deploys/onboardings happen.
