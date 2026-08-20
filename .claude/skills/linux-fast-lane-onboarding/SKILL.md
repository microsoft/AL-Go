---
name: linux-fast-lane-onboarding
description: Onboard, audit, or revert the "Linux fast lane" (bc-linux-based fast PR builds) on any AL-Go-managed repo Stefan manages. Also covers keeping the StefanMaron/AL-Go fork in sync with microsoft/AL-Go and deploying it to StefanMaron/AL-Go-PTE and AL-Go-AppSource. Use when Stefan says "onboard the fast lane", "add the Linux fast lane to <repo>", "revert <repo> to Microsoft AL-Go", or "sync/deploy the AL-Go fork".
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
- At least one repo has been onboarded successfully, including a non-trivial case (an AppSource-type repo with a third-party `appDependencyProbingPaths` dependency) — a workflow-scoped settings file (`.github/<workflow name>.settings.json`) rather than `ConditionalSettings` is a proven pattern for scoping `linuxFastLane` to one workflow.
- `StefanMaron/AL-Go`'s `main` can drift behind `microsoft/AL-Go`'s `main` (routine upstream fixes) while carrying its own fork-only commits ahead. That's expected and not a blocker — an onboarding can proceed against the fork's current (unsynced) state; do the upstream merge separately per "Keeping the fork mergeable from upstream" below when there's a reason to (e.g. a downstream repo needs one of the upstream fixes). Check current drift with `git log --oneline main..upstream/main` / `git log --oneline upstream/main..main` before relying on any specific count.
- Most real managed repos are still on stock `templateUrl: https://github.com/microsoft/AL-Go-PTE@main` — check `.github/AL-Go-Settings.json`'s `templateUrl` in a given repo before assuming it's onboarded.
- `StefanMaron/AL-Go-Actions` remains a stale, unrelated fork — confirmed irrelevant to this flow (`Internal/Deploy.ps1` never targets a separate Actions repo for a non-`microsoft` owner).

## Redeploy after future upstream syncs or fork changes — now automatic (as of PR #2, 2026-08-07)

`Deploy.yaml` has a `push` trigger on `main` scoped to `Templates/**`/`Actions/**` paths, with `directCommit=true` on the auto-triggered path (no review PR on the template repos — merging to `main` on `StefanMaron/AL-Go` **is** the release gate now, review the PR to `main` accordingly). So the normal flow is just:

1. Merge changes into `main` on `StefanMaron/AL-Go` via a PR (open PR, wait for CI green, merge — don't push straight to `main` blind). If the diff touches `Templates/**` or `Actions/**`, `AL-Go-PTE`/`AL-Go-AppSource` update automatically within a minute or two of the merge — no further action needed.
2. Spot-check the auto-deploy run succeeded: `gh run list -R StefanMaron/AL-Go --workflow=Deploy.yaml --limit 1`, and that the template repos picked it up: `gh api repos/StefanMaron/AL-Go-PTE/commits/main --jq .commit.message` should reference the new source SHA.

Manual `workflow_dispatch` is still needed for: a repo that doesn't exist yet (`gh repo create <owner>/<repo> --public` first, see auth note above — `directCommit` still defaults to `false`/PR-reviewed for manual runs), a release-branch deploy with `copyToMain: true`, or re-running after a failed auto-deploy.

Either way, once deployed: check Actions references resolved to `StefanMaron/AL-Go/Actions/<Name>@<sha>` (not `microsoft/...`) and that expected new files are present, e.g.: `gh pr diff <n> -R StefanMaron/AL-Go-PTE | grep -c microsoft/AL-Go-Actions` should show 0 live `uses:` hits (a `$schema` doc example string is a known harmless false positive) — for a `directCommit=true` auto-deploy there's no PR to diff, so instead diff the pushed commit directly: `gh api repos/StefanMaron/AL-Go-PTE/commits/main | jq -r '.files[].filename'`.

**This never reaches downstream repos automatically.** An onboarded repo only picks up the new template content when *it* runs its own "Update AL-Go System Files" — manually, or on whatever `workflowSchedule`/org-level cron it has configured, and even then via a PR it still has to merge (not silent). Bumping something in `Templates/`/`Actions/` on this fork's `main` does NOT mean it's live for consumers yet.

## To onboard an existing managed repo to the fast lane

The template repos are live — this is directly actionable now. Concrete runbook:

1. Trigger the repo's "Update AL-Go System Files" workflow (`UpdateGitHubGoSystemFiles.yaml`) via `workflow_dispatch`, passing the new `templateUrl` directly as an input rather than hand-editing `AL-Go-Settings.json` — the workflow does both the settings update and the file sync in one PR:
   ```bash
   gh workflow run "UpdateGitHubGoSystemFiles.yaml" -R <owner>/<repo> \
     -f templateUrl="https://github.com/StefanMaron/AL-Go-PTE@main" \
     -f downloadLatest=true -f directCommit=false
   ```
   (Use `AL-Go-AppSource@main` for an AppSource-type repo — check `.github/AL-Go-Settings.json`'s `type` field first.) `directCommit=false` opens a review PR instead of pushing straight to the target branch — always use this for a first onboarding.
2. This PR pulls in `_BuildALGoProjectLinux.yaml` and rewrites all Actions references to `StefanMaron/AL-Go/Actions/<Name>@<sha>` — purely additive, `main`'s existing `Build`/`CICD` path is untouched. Sanity-check: `gh pr diff <n> -R <owner>/<repo> | grep -A3 templateUrl`.
3. Add the opt-in setting as a second commit on that same PR branch (fetch the auto-generated `update-al-go-system-files/...` branch, add the file, push back onto it — keeps onboarding as one reviewable PR). **Prefer a workflow-scoped settings file over `ConditionalSettings`** when you only need to scope to one workflow — it's simpler:
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

### If a repo has both fast-lane-eligible and compile-only projects

`linuxFastLane` is correctly skipped for a project with `useCompilerFolder`/`doNotPublishApps` set (nothing for the fast lane to publish or test) — but that means it silently falls back to the **classic** compiler-folder path, which still downloads the full BC artifact (~2GB) even though it isn't spinning up a container. On a multi-project repo this shows up as "the fast-lane project finished in minutes, the compile-only project is still running" — easy to mistake for a hang. It usually isn't one; it's just the slow path.

The actual fast path for a compile-only project is a **separate** opt-in, not `linuxFastLane`:
```json
"workspaceCompilation": { "enabled": true },
"symbolsSource": "nuGet"
```
`symbolsSource: nuGet` resolves only the dependency symbols + AL compiler from NuGet/MSSymbols instead of downloading the BC artifact — this is what actually removes the slow part. Requires `workspaceCompilation.enabled: true`, and per the settings schema is **not supported for apps targeting OnPrem or Internal, or with a `vsixFile` download URL** — check every app's `app.json` `target` field (absent = defaults to Cloud, which is fine) before setting this. Not yet verified end-to-end on a real managed repo — confirm the build time actually drops before treating this as proven guidance elsewhere.

**This can't be defaulted org-wide the way `linuxFastLane` often is.** An org-level `ALGoOrgSettings` GitHub Actions variable (optionally scoped with `ConditionalSettings` to specific branches/workflows) is a reasonable way to default `linuxFastLane` across every repo in an org, since it's a no-op wherever a project isn't fast-lane-eligible. `workspaceCompilation`/`symbolsSource: nuGet` can't be defaulted the same way — set it in the specific compile-only project's `<project>/.AL-Go/settings.json` inside its repo. Compile-only-ness is a per-project property (a multi-project repo will often have some projects that are fast-lane-eligible and others that are compile-only), so this one has to be scoped per project, not per org or per repo.

### Re-triggering "Update AL-Go System Files" after a failed/stuck run

If the workflow genuinely fails (not just "a compile-only project is slow," see above) on the first `workflow_dispatch` against the repo's default branch, the fix is **not** to re-run it against that branch again — re-trigger it a second time with `--ref` pointed at the branch the *first* invocation created (`update-al-go-system-files/<base>/<timestamp>`), and this time pass `directCommit=true`:
```bash
gh workflow run "UpdateGitHubGoSystemFiles.yaml" -R <owner>/<repo> \
  --ref update-al-go-system-files/main/<timestamp> \
  -f templateUrl="https://github.com/StefanMaron/AL-Go-PTE@main" \
  -f downloadLatest=true -f directCommit=true
```
Getting `directCommit` wrong here is the actual failure mode to watch for: leaving it `false` (the correct value for the *first*, PR-opening invocation) makes this second run open **yet another** new branch/PR instead of fixing the existing one — `directCommit=true` is what makes it commit straight onto the branch you named in `--ref`. Sanity-check after: `git ls-remote --heads <repo> | grep update-al-go-system-files` should show no unexpected extra branch, and the existing PR should have a new commit, not a sibling PR next to it.

### Multi-branch dispatches are independent — never cross-merge

If the repo's `workflowSchedule`/multi-run config includes both `main` and `test` (or any other branch), a single `workflow_dispatch` produces **one PR per branch**, each on its own `update-al-go-system-files/<branch>/<timestamp>` branch. Treat these as fully separate onboardings sharing nothing but the trigger: never merge the `main`-targeted branch into `test` (or vice versa) to "save a step" — a repo's test-branch-contamination guard is liable to reject that merge direction anyway, and even where it wouldn't, it defeats the point of the two independent PRs. If a fix (like the compile-only `workspaceCompilation` setting above) is needed on both, apply it to both branches separately.

## To revert a repo to stock Microsoft AL-Go

1. Set `templateUrl` back to `https://github.com/microsoft/AL-Go-PTE@main` (or `AppSource@main`).
2. Rerun "Update AL-Go System Files".
3. Leave `linuxFastLane`/`ConditionalSettings` keys in settings.json alone — they're inert once the Linux-fast-lane-aware workflow files are gone, no cleanup required.

## Keeping the fork mergeable from upstream (ongoing discipline, not a one-time task)

- Never rebase or rewrite already-pushed history on `StefanMaron/AL-Go`'s `main` — only fast-forward/merge upstream in, append fork commits on top. Rebasing published history is exactly what would break future fast-forwards.
- New fork-only behavior should be additive and gated (new files, or new job/step blocks guarded by an `if:` on a project-level setting) rather than rewriting existing upstream logic in place — this is what keeps `git merge upstream/main` conflict-free. The actual `feat/linux-fast-lane` diff follows this pattern already (see `Templates/Per Tenant Extension/.github/workflows/PullRequestHandler.yaml`: new `BuildLinux` job gated on `buildDimensionsLinuxCount > 0`, existing `Build` job's `if:` condition only picked up a renamed count variable).
- Periodically (Stefan hasn't committed to automating this yet — ask before building a cron for it): `git fetch upstream (microsoft/AL-Go) main`, check `git merge-base --is-ancestor main upstream/main` isn't already true, and if the merge is conflict-free, fast-forward/merge and redeploy via step 2 of "make the fast lane deployable" above so `StefanMaron/AL-Go-PTE`/`AppSource` pick up Microsoft's upstream changes too.

### Fork patches to Microsoft-owned files (perf/bug fixes, not new features)

Sometimes the right fix isn't a new additive file/job — it's a small change inside a file Microsoft still owns (e.g. deleting an unnecessary line in an `Actions/*.ps1`). That doesn't need the opt-in-setting treatment from constraint 1 above (it's not new user-facing behavior), but it does carry merge risk constraint 2 is about, so treat these differently from `linuxFastLane`-style features:

- Keep the diff to the smallest possible surgical change (ideally one line), with a comment marking it as an AL-Go fork patch and explaining why, so a future 3-way merge conflict on that line is trivial to re-resolve instead of confusing.
- Back it with a Pester test in `Tests/` that asserts the patch is still in place (e.g. greps the action script for the removed call) — this runs in this repo's existing CI on every PR, including the PR that merges `upstream/main` in, so a merge that silently reintroduces the old behavior fails CI instead of shipping unnoticed. This is the "pipeline" that keeps the patch applied: normal `git merge` already carries a committed patch forward automatically (that's what merge does), the test's only job is to catch the case where upstream touches the same lines and the merge needs a human to reconcile it.
- A guard test must actually exercise the code path the patch touches, not just grep the source for the removed line — a textual assertion proves the patch is still applied, not that applying it is safe. That distinction is what the reverted entry below got wrong.
- Log each one here so a fork-sync pass knows what to specifically re-verify after `git merge upstream/main`:

| Patch | File | Why | Guard test |
|---|---|---|---|
| ~~Skip `DownloadAndImportBcContainerHelper` in DetermineProjectsToBuild~~ **REVERTED 2026-08-11** | `Actions/DetermineProjectsToBuild/DetermineProjectsToBuild.Action.ps1` | Premise was wrong: `AnalyzeProjectDependencies` (`AL-Go-Helper.ps1`) calls `Sort-AppFoldersByDependencies`, a BcContainerHelper cmdlet, so the import IS needed. The guard test only grepped the source for the removed call — it never ran `Get-ProjectsToBuild` in a session without BcContainerHelper already loaded, so it never caught that this action actually needs it. Broke every Linux fast lane build on `main` until reverted. | (removed — see note above) |

See also: `[[al-go-fork-strategy]]` (project memory, AL-Go repo) for the fuller verification trail behind this skill.
