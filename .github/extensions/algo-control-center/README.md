# AL-Go Control Center

A Copilot CLI canvas extension that gives partners a single dashboard for managing many AL-Go repositories in a GitHub org.

## What it does

- **Fleet** view (primary): every AL-Go repository in the selected org with AL-Go template version, country, type, latest CI status, recent activity, and open PR count. Multi-select rows to enable bulk actions in the sticky action bar above the table. Activity log expands below to show per-repo results.
- **Runs** view: cross-repo feed of workflow runs across the whole org's AL-Go fleet, styled like a single repo's Actions page. Filter by workflow, conclusion, repository, and free text. Scroll to the bottom and more pages are loaded automatically per repo (server-side pagination, deduped by run ID). Failing CI / Next Major badges in the Fleet table reveal a 🤖 button on hover that delegates an investigation prompt into the current chat.
- **Settings** view: only the repos with failing workflows, with links to the failing runs, plus a fleet-wide deprecations rollup. Each finding has a "Delegate to agent" button that hands the migration to the current chat.
- **Bulk actions** (sticky toolbar on the Fleet tab, lights up when ≥ 1 repo is selected):
  - Update AL-Go System Files (triggers `UpdateGitHubGoSystemFiles.yaml`, opens PRs).
  - Re-run failed workflow runs.
  - Trigger any workflow by file name.
- **Org switcher**: toggle between any GitHub org the user is a member of. Last-chosen org persists per user.

## How discovery works

For each org, the canvas picks a discovery strategy:

- **Auto** (default): peeks the org's total repo count via GraphQL. If ≤ 250 it does a **deep scan** (lists every repo); otherwise it uses **search**.
- **Search**: GitHub code search for `filename:AL-Go-Settings.json` scoped to the org. One request returns every indexed AL-Go repo. Fast on huge orgs but misses freshly created repos that aren't indexed yet.
- **Deep**: lists every repo via REST. Reliable on small orgs but expensive on large ones.

For whichever set of candidate repos is selected, a single **batched GraphQL query** (40 repos per batch) fetches AL-Go-Settings.json contents, default branch, open PR count, visibility, and pushed-at timestamps. A second per-repo REST call fetches the latest workflow runs (no GraphQL equivalent), parallel-limited to 8.

The UI surfaces a yellow banner when search-based discovery is in use, with a one-click "Switch to deep scan" toggle for partners whose just-created repos aren't showing up yet.

## Agent-facing actions

The canvas exposes these actions for the agent to invoke through `invoke_canvas_action`:

| Action | Purpose |
| ------ | ------- |
| `refresh_fleet` | Re-scan the org for AL-Go repositories. Accepts `mode: "auto" | "search" | "deep"`. |
| `select_org` | Persist a focus org. |
| `bulk_update_algo_system_files` | Trigger `UpdateGitHubGoSystemFiles.yaml` on the supplied repos. |
| `bulk_rerun_failed_runs` | Re-run failed jobs of the latest failed run for each repo. |
| `bulk_trigger_workflow` | Trigger any workflow file on selected repos. |

## Requirements

- `gh` CLI logged in (`gh auth status`) with `repo`, `read:org`, and `workflow` scopes.
- Node.js 18+ (the Copilot CLI ships its own runtime).

## State

- User preferences (last-selected org) are stored under `$COPILOT_HOME/extensions/algo-control-center/artifacts/preferences.json`.
- Fleet data is cached in memory for 60 seconds per org.
