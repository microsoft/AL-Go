---
name: linux-fast-lane-onboarding
description: Onboard, audit, or revert the "Linux fast lane" (bc-linux-based fast PR builds) on any AL-Go-managed repo Stefan manages (ABC customers, WorldMax, personal projects). Also covers keeping the StefanMaron/AL-Go fork in sync with microsoft/AL-Go and deploying it to StefanMaron/AL-Go-PTE and AL-Go-AppSource. Use when Stefan says "onboard the fast lane", "add the Linux fast lane to <repo>", "revert <repo> to Microsoft AL-Go", or "sync/deploy the AL-Go fork".
---

# Linux Fast Lane — Onboarding, Fork Sync, and Revert

The Linux fast lane is a fork feature on `StefanMaron/AL-Go` (source: `github.com/StefanMaron/AL-Go`, branch `feat/linux-fast-lane` as of 2026-08-07). It runs pull-request builds against a Linux BC container ([bc-linux](https://github.com/StefanMaron/MsDyn365Bc.On.Linux)) instead of the full Windows pipeline — fast/cheap CI gate for PRs and test branches, never a replacement for `main`'s pipeline. Feature docs: `Scenarios/LinuxFastLane.md` in that repo.

Three non-negotiable constraints (Stefan's words, 2026-08-07) govern every change here:

1. **Drop-in, non-invasive.** Onboarding a repo must never require restructuring it — only an opt-in setting change. PRs and non-production/test branches get the fast lane; `main` never does.
2. **The fork must stay easily mergeable from upstream.** `StefanMaron/AL-Go`'s `main` must be able to absorb `microsoft/AL-Go`'s `main` cleanly (ideally an actual fast-forward, otherwise a conflict-free merge) so Microsoft's upstream fixes/features keep flowing to every repo built on this fork.
3. **Reverting to stock Microsoft AL-Go must be trivial.** Just repoint `templateUrl` back to `microsoft/AL-Go-PTE@main` (or `AppSource`) and rerun "Update AL-Go System Files" — leftover `linuxFastLane`/`ConditionalSettings` keys are harmless (AL-Go's settings schema has no root `additionalProperties: false`, and `ValidateSettings` only ever emits a warning, never fails the build).

## This skill lives in the fork — not just in Stefan's local Claude config

Canonical copy: `.claude/skills/linux-fast-lane-onboarding/SKILL.md` in `StefanMaron/AL-Go` (this file). Stefan's local `~/.claude/skills/linux-fast-lane-onboarding` is a symlink to this file, so any Claude Code session anywhere on his machine sees it automatically. Anyone else working on a repo that already tracks this fork (i.e. has this file checked out under `.claude/skills/`) gets it for free too — Claude Code auto-discovers project-scoped skills. Point a fresh/cloud agent with no local access at this file's raw GitHub URL or its content directly if it can't see the local filesystem. **Edit this file, not a copy** — if you're working from the local symlink, you're already editing the canonical source; if you're on a checkout without the symlink, edit here and remember the change needs to reach `main` via a PR like any other change to this repo (see the mergeable-fork discipline below — this file is subject to the exact same rules).

## Current state (verified 2026-08-07 — reverify before trusting on reuse)

- **Deployed and live.** `feat/linux-fast-lane` merged into `StefanMaron/AL-Go` `main` (PR #1, merge commit `7f21177b`). `StefanMaron/AL-Go-PTE` and `StefanMaron/AL-Go-AppSource` exist and are populated (as of `7f21177b`) — Actions references in their workflows correctly resolve to `StefanMaron/AL-Go/Actions/<Name>@7f21177b`, and both contain `_BuildALGoProjectLinux.yaml`.
- Deploy auth is wired on `StefanMaron/AL-Go`: repo variable `APP_ID=1203592` + secret `PRIVATE_KEY`, sourced from the `GitHub App stefanmaronapp` 1Password item (vault `claude`). This lets `Deploy.yaml` push to the two template repos, but the app installation does **not** have "Administration: Read & write" account permission, so it **cannot create new repos** — if a repo needs (re)creating, do it manually first (`gh repo create <owner>/<repo> --public`) then rerun Deploy.
- **First onboarded repo: `Stefan-Maron-Consulting/Pageworks`** (merged 2026-08-07, PR #33) — an AppSource product repo with a third-party `appDependencyProbingPaths` dependency, so it's a good reference example for a non-trivial onboarding. `linuxFastLane` is scoped there via `.github/Pull Request Build.settings.json`, not `ConditionalSettings`. All other real managed repos checked (ABC fleet) are still on stock `templateUrl: https://github.com/microsoft/AL-Go-PTE@main` as of this writing.
- `StefanMaron/AL-Go-Actions` remains a stale, unrelated fork — confirmed irrelevant to this flow (`Internal/Deploy.ps1` never targets a separate Actions repo for a non-`microsoft` owner).

## Redeploy after future upstream syncs or fork changes — now automatic (as of PR #2, 2026-08-07)

`Deploy.yaml` has a `push` trigger on `main` scoped to `Templates/**`/`Actions/**` paths, with `directCommit=true` on the auto-triggered path (no review PR on the template repos — merging to `main` on `StefanMaron/AL-Go` **is** the release gate now, review the PR to `main` accordingly). So the normal flow is just:

1. Merge changes into `main` on `StefanMaron/AL-Go` via a PR (open PR, wait for CI green, merge — don't push straight to `main` blind). If the diff touches `Templates/**` or `Actions/**`, `AL-Go-PTE`/`AL-Go-AppSource` update automatically within a minute or two of the merge — no further action needed.
2. Spot-check the auto-deploy run succeeded: `gh run list -R StefanMaron/AL-Go --workflow=Deploy.yaml --limit 1`, and that the template repos picked it up: `gh api repos/StefanMaron/AL-Go-PTE/commits/main --jq .commit.message` should reference the new source SHA.

Manual `workflow_dispatch` is still needed for: a repo that doesn't exist yet (`gh repo create <owner>/<repo> --public` first, see auth note above — `directCommit` still defaults to `false`/PR-reviewed for manual runs), a release-branch deploy with `copyToMain: true`, or re-running after a failed auto-deploy.

Either way, once deployed: check Actions references resolved to `StefanMaron/AL-Go/Actions/<Name>@<sha>` (not `microsoft/...`) and that expected new files are present, e.g.: `gh pr diff <n> -R StefanMaron/AL-Go-PTE | grep -c microsoft/AL-Go-Actions` should show 0 live `uses:` hits (a `$schema` doc example string is a known harmless false positive) — for a `directCommit=true` auto-deploy there's no PR to diff, so instead diff the pushed commit directly: `gh api repos/StefanMaron/AL-Go-PTE/commits/main | jq -r '.files[].filename'`.

**This never reaches downstream repos automatically.** Pageworks (or any other onboarded repo) only picks up the new template content when *it* runs its own "Update AL-Go System Files" — manually, or on whatever `workflowSchedule`/org-level cron it has configured, and even then via a PR it still has to merge (not silent). Bumping something in `Templates/`/`Actions/` on this fork's `main` does NOT mean it's live for consumers yet.

## To onboard an existing managed repo to the fast lane

The template repos are live — this is directly actionable now. Concrete runbook (as executed on the `Stefan-Maron-Consulting/Pageworks` pilot, 2026-08-07):

1. Trigger the repo's "Update AL-Go System Files" workflow (`UpdateGitHubGoSystemFiles.yaml`) via `workflow_dispatch`, passing the new `templateUrl` directly as an input rather than hand-editing `AL-Go-Settings.json` — the workflow does both the settings update and the file sync in one PR:
   ```bash
   gh workflow run "UpdateGitHubGoSystemFiles.yaml" -R <owner>/<repo> \
     -f templateUrl="https://github.com/StefanMaron/AL-Go-PTE@main" \
     -f downloadLatest=true -f directCommit=false
   ```
   (Use `AL-Go-AppSource@main` for an AppSource-type repo — check `.github/AL-Go-Settings.json`'s `type` field first.) `directCommit=false` opens a review PR instead of pushing straight to the target branch — always use this for a first onboarding.
2. This PR pulls in `_BuildALGoProjectLinux.yaml` and rewrites all Actions references to `StefanMaron/AL-Go/Actions/<Name>@<sha>` — purely additive, `main`'s existing `Build`/`CICD` path is untouched. Sanity-check: `gh pr diff <n> -R <owner>/<repo> | grep -A3 templateUrl`.
3. Add the opt-in setting as a second commit on that same PR branch (fetch the auto-generated `update-al-go-system-files/...` branch, add the file, push back onto it — keeps onboarding as one reviewable PR). **Prefer a workflow-scoped settings file over `ConditionalSettings`** when you only need to scope to one workflow — it's simpler and is the pattern already used on Pageworks' `test/linux-fast-lane-build` branch:
   ```
   .github/Pull Request Build.settings.json   (filename = the target workflow's `name:` field, not its filename)
   ```
   ```json
   { "linuxFastLane": true }
   ```
   Use `ConditionalSettings` instead only when scoping needs branch + workflow combinations (e.g. also enabling it on a non-production `test`/`test/*` branch's CICD run):
   ```json
   "ConditionalSettings": [
     { "branches": ["test", "test/*"], "workflows": ["CICD"], "settings": { "linuxFastLane": true } }
   ]
   ```
4. Confirm the project's `application`/`platform` in `app.json` (or `artifact` setting) is pinned to a concrete BC version, not `latest` — needed for predictable fast-lane results, see `Scenarios/LinuxFastLane.md`.
5. Let the PR's own CI run (`Pull Request Build`/`PullRequestHandler` workflow) — this is the real validation, no separate throwaway PR needed since the onboarding PR itself triggers it. Confirm the new `BuildLinux` job actually appears and passes before merging. If it fails, check whether the failure is fast-lane-specific (e.g. a known Linux-BC test limitation, see `Scenarios/LinuxFastLane.md`) vs. a real regression before troubleshooting further.

## To revert a repo to stock Microsoft AL-Go

1. Set `templateUrl` back to `https://github.com/microsoft/AL-Go-PTE@main` (or `AppSource@main`).
2. Rerun "Update AL-Go System Files".
3. Leave `linuxFastLane`/`ConditionalSettings` keys in settings.json alone — they're inert once the Linux-fast-lane-aware workflow files are gone, no cleanup required.

## Keeping the fork mergeable from upstream (ongoing discipline, not a one-time task)

- Never rebase or rewrite already-pushed history on `StefanMaron/AL-Go`'s `main` — only fast-forward/merge upstream in, append fork commits on top. Rebasing published history is exactly what would break future fast-forwards.
- New fork-only behavior should be additive and gated (new files, or new job/step blocks guarded by an `if:` on a project-level setting) rather than rewriting existing upstream logic in place — this is what keeps `git merge upstream/main` conflict-free. The actual `feat/linux-fast-lane` diff follows this pattern already (see `Templates/Per Tenant Extension/.github/workflows/PullRequestHandler.yaml`: new `BuildLinux` job gated on `buildDimensionsLinuxCount > 0`, existing `Build` job's `if:` condition only picked up a renamed count variable).
- Periodically (Stefan hasn't committed to automating this yet — ask before building a cron for it): `git fetch upstream (microsoft/AL-Go) main`, check `git merge-base --is-ancestor main upstream/main` isn't already true, and if the merge is conflict-free, fast-forward/merge and redeploy via step 2 of "make the fast lane deployable" above so `StefanMaron/AL-Go-PTE`/`AppSource` pick up Microsoft's upstream changes too.

See also: `[[al-go-fork-strategy]]` (project memory, AL-Go repo) for the fuller verification trail behind this skill.
