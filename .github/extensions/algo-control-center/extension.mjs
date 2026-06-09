// AL-Go Control Center — Copilot CLI canvas extension.
//
// Declares the `algo-control-center` canvas to the runtime via joinSession.
// The canvas iframe is served from a loopback HTTP server in this process.

import path from "node:path";
import fs from "node:fs/promises";
import os from "node:os";
import { fileURLToPath } from "node:url";

import { CanvasError, createCanvas, joinSession } from "@github/copilot-sdk/extension";
import { listUserOrgs, gatherFleet, triggerWorkflow, rerunFailedLatest, fetchMoreRunsForRepo, getRunDetail, getJobLogTail, getRepoSettingsBundle, getFleetDeprecations } from "./lib/fleet.mjs";
import { startServer } from "./lib/server.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = path.join(__dirname, "web");

function copilotHome() {
  return process.env.COPILOT_HOME || path.join(os.homedir(), ".copilot");
}

function prefsPath() {
  return path.join(copilotHome(), "extensions", "algo-control-center", "artifacts", "preferences.json");
}

async function loadPreferences() {
  try {
    const raw = await fs.readFile(prefsPath(), "utf8");
    return JSON.parse(raw);
  } catch {
    return { selectedOrg: null };
  }
}

async function savePreferences(prefs) {
  const file = prefsPath();
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, JSON.stringify(prefs, null, 2), "utf8");
  return prefs;
}

const fleetCache = new Map();
const FLEET_TTL_MS = 60_000;

// Default time window for the cross-org Runs view. Recent activity is what
// matters for a control center — anything older is a click away in the
// repo's Actions tab.
const RUNS_WINDOW_DAYS = 7;
const RUNS_PER_PAGE = 100;

// Tracks pagination state for the cross-org Runs view, keyed by `org::mode`.
// Each entry: { runs: Map<runId, normalized>, pages: Map<repoName, { next, exhausted }>, hasMore, since, loadedAt }.
const runsCache = new Map();

function runsCacheFor(cacheKey) {
  let entry = runsCache.get(cacheKey);
  if (!entry) {
    entry = { runs: new Map(), pages: new Map(), hasMore: true, since: null, loadedAt: 0 };
    runsCache.set(cacheKey, entry);
  }
  return entry;
}

function sortedRuns(entry) {
  return [...entry.runs.values()].sort(
    (a, b) => new Date(b.updatedAt) - new Date(a.updatedAt),
  );
}

function windowSince(days) {
  return new Date(Date.now() - days * 86_400_000).toISOString();
}

async function loadRunsWindow(org, mode, hub, { windowDays = RUNS_WINDOW_DAYS, force = false } = {}) {
  const cacheKey = `${org}::${mode || "auto"}`;
  const fleet = fleetCache.get(cacheKey);
  if (!fleet) throw new Error("fleet not loaded for this org");
  const entry = runsCacheFor(cacheKey);
  const since = windowSince(windowDays);
  // Reuse the existing windowed cache if the window hasn't changed and the
  // data is fresh (within the fleet TTL). Otherwise reset and refetch.
  if (!force && entry.since === since && Date.now() - entry.loadedAt < FLEET_TTL_MS) {
    return { runs: sortedRuns(entry), hasMore: entry.hasMore, windowDays, since };
  }
  entry.runs.clear();
  entry.pages.clear();
  entry.since = since;
  await Promise.all(fleet.repos.map(async (repo, i) => {
    const { runs, exhausted } = await fetchMoreRunsForRepo(org, repo.name, 1, RUNS_PER_PAGE, since);
    for (const run of runs) {
      entry.runs.set(run.runId, { ...run, repo: repo.name, repoHtmlUrl: repo.htmlUrl });
    }
    entry.pages.set(repo.name, { next: 2, exhausted });
    hub && hub.publish("runs:progress", { repo: repo.name, page: 1, added: runs.length, done: i + 1, total: fleet.repos.length });
  }));
  entry.hasMore = [...entry.pages.values()].some((p) => !p.exhausted);
  entry.loadedAt = Date.now();
  return { runs: sortedRuns(entry), hasMore: entry.hasMore, windowDays, since };
}

async function loadMoreRuns(org, mode, hub, opts = {}) {
  const cacheKey = `${org}::${mode || "auto"}`;
  const fleet = fleetCache.get(cacheKey);
  if (!fleet) throw new Error("fleet not loaded for this org");
  const entry = runsCacheFor(cacheKey);
  const since = entry.since;
  let candidates;
  if (opts.repo) {
    const r = fleet.repos.find((x) => x.name === opts.repo);
    if (!r) return { runs: sortedRuns(entry), hasMore: entry.hasMore, added: 0 };
    const p = entry.pages.get(r.name);
    candidates = (!p || !p.exhausted) ? [r] : [];
  } else {
    if (!entry.hasMore) return { runs: sortedRuns(entry), hasMore: false, added: 0 };
    candidates = fleet.repos.filter((r) => {
      const p = entry.pages.get(r.name);
      return !p || !p.exhausted;
    });
  }
  if (candidates.length === 0) {
    if (!opts.repo) entry.hasMore = false;
    return { runs: sortedRuns(entry), hasMore: entry.hasMore, added: 0 };
  }
  let added = 0;
  await Promise.all(candidates.map(async (repo, i) => {
    const state = entry.pages.get(repo.name) || { next: 2 };
    const { runs, exhausted } = await fetchMoreRunsForRepo(org, repo.name, state.next, RUNS_PER_PAGE, since);
    for (const run of runs) {
      const decorated = { ...run, repo: repo.name, repoHtmlUrl: repo.htmlUrl };
      if (!entry.runs.has(run.runId)) added++;
      entry.runs.set(run.runId, decorated);
    }
    entry.pages.set(repo.name, { next: state.next + 1, exhausted });
    hub && hub.publish("runs:progress", { repo: repo.name, page: state.next, added: runs.length, done: i + 1, total: candidates.length });
  }));
  entry.hasMore = [...entry.pages.values()].some((p) => !p.exhausted);
  return { runs: sortedRuns(entry), hasMore: entry.hasMore, added };
}

async function getFleet(org, { force, mode, hub } = {}) {
  const cacheKey = `${org}::${mode || "auto"}`;
  const cached = fleetCache.get(cacheKey);
  if (cached && !force && Date.now() - cached.fetchedAt < FLEET_TTL_MS) return cached;
  hub && hub.publish("fleet:loading", { org });
  const { repos, discoveryMode, totalOrgRepos } = await gatherFleet(org, {
    mode,
    onProgress: (p) => hub && hub.publish("fleet:progress", { org, ...p }),
  });
  const result = { org, repos, discoveryMode, totalOrgRepos, fetchedAt: Date.now() };
  fleetCache.set(cacheKey, result);
  // The fleet-load already fetched a small page of recent runs for each repo
  // (used by the CI status badge). Seed those into the Runs cache so the
  // Runs view is non-empty immediately, even before the user clicks the tab.
  // The Runs tab itself triggers loadRunsWindow() to replace this with a
  // proper 7-day windowed dataset.
  const entry = runsCacheFor(cacheKey);
  entry.runs.clear();
  entry.pages.clear();
  entry.since = null;
  entry.loadedAt = 0;
  for (const repo of repos) {
    for (const run of (repo.runs && repo.runs.all) || []) {
      entry.runs.set(run.runId, { ...run, repo: repo.name, repoHtmlUrl: repo.htmlUrl });
    }
    entry.pages.set(repo.name, { next: 2, exhausted: false });
  }
  entry.hasMore = true;
  hub && hub.publish("fleet:ready", { org, count: repos.length, discoveryMode, totalOrgRepos });
  return result;
}

async function bulkUpdateAlgoSystemFiles({ org, repos }, hub) {
  if (!org || !Array.isArray(repos) || repos.length === 0) {
    throw new CanvasError("invalid_input", "org and non-empty repos[] are required");
  }
  const fleet = await getFleet(org, { hub });
  const results = [];
  for (const repoName of repos) {
    const repo = fleet.repos.find((r) => r.name === repoName);
    const ref = (repo && repo.defaultBranch) || "main";
    try {
      // directCommit is a boolean input in UpdateGitHubGoSystemFiles.yaml;
      // "false" => open a PR instead of committing straight to the branch.
      await triggerWorkflow(org, repoName, "UpdateGitHubGoSystemFiles.yaml", ref, { directCommit: "false" });
      results.push({ repo: repoName, ok: true });
    } catch (err) {
      results.push({ repo: repoName, ok: false, error: err.message });
    }
    hub && hub.publish("bulk:progress", { action: "update-algo", repo: repoName, done: results.length, total: repos.length });
  }
  return { action: "update-algo", results };
}

async function bulkRerunFailed({ org, repos }, hub) {
  if (!org || !Array.isArray(repos) || repos.length === 0) {
    throw new CanvasError("invalid_input", "org and non-empty repos[] are required");
  }
  const results = [];
  for (const repoName of repos) {
    try {
      const r = await rerunFailedLatest(org, repoName);
      results.push({ repo: repoName, ...r });
    } catch (err) {
      results.push({ repo: repoName, ok: false, error: err.message });
    }
    hub && hub.publish("bulk:progress", { action: "rerun-failed", repo: repoName, done: results.length, total: repos.length });
  }
  return { action: "rerun-failed", results };
}

async function bulkTriggerWorkflow({ org, repos, workflow, ref, inputs }, hub) {
  if (!org || !Array.isArray(repos) || repos.length === 0 || !workflow) {
    throw new CanvasError("invalid_input", "org, repos[], and workflow are required");
  }
  const fleet = await getFleet(org, { hub });
  const results = [];
  for (const repoName of repos) {
    const repo = fleet.repos.find((r) => r.name === repoName);
    const useRef = ref || (repo && repo.defaultBranch) || "main";
    try {
      await triggerWorkflow(org, repoName, workflow, useRef, inputs);
      results.push({ repo: repoName, ok: true });
    } catch (err) {
      results.push({ repo: repoName, ok: false, error: err.message });
    }
    hub && hub.publish("bulk:progress", { action: "trigger", workflow, repo: repoName, done: results.length, total: repos.length });
  }
  return { action: "trigger", workflow, results };
}

// --- Delegation helpers ------------------------------------------------

let copilotSession = null; // set after joinSession; used to inject prompts

function buildDelegationPrompt(card) {
  const lines = [
    `Please investigate this failing AL-Go workflow.`,
    ``,
    `Repository: ${card.repo} (${card.repoHtmlUrl})`,
    `Workflow:   ${card.workflow}${card.workflowPath ? ` — ${card.workflowPath}` : ""}`,
    `Failed run: ${card.runHtmlUrl}`,
    card.headBranch ? `Branch:     ${card.headBranch}` : null,
    card.headSha ? `Commit:     ${card.headSha}` : null,
    card.displayTitle ? `Run title:  ${card.displayTitle}` : null,
    ``,
    `Please:`,
    `  1. Fetch the failed run's logs (use the gh CLI: \`gh run view ${card.runId} -R ${card.repo} --log-failed\`).`,
    `  2. Identify the root cause and summarize it.`,
    `  3. If the fix is in this repo, propose changes. Otherwise, explain what action needs to be taken.`,
  ].filter(Boolean);
  return lines.join("\n");
}

async function delegateRunInvestigation({ org, repo, runId, workflow, workflowPath, htmlUrl, headBranch, headSha, displayTitle } = {}) {
  if (!org || !repo || !runId) throw new CanvasError("invalid_input", "org, repo, runId required");
  if (!copilotSession) throw new CanvasError("no_session", "Copilot session not connected");
  const prompt = buildDelegationPrompt({
    repo: `${org}/${repo}`,
    repoHtmlUrl: `https://github.com/${org}/${repo}`,
    workflow,
    workflowPath,
    runHtmlUrl: htmlUrl,
    runId,
    headBranch,
    headSha,
    displayTitle,
  });
  copilotSession.send(prompt).catch((err) => {
    console.error("[algo-control-center] delegateRunInvestigation send failed:", err);
  });
  return { ok: true, org, repo, runId, prompted: true };
}

function buildDeprecationDelegationPrompt({ org, key, sunset, replacement, anchor, repos }) {
  const docsUrl = `https://github.com/microsoft/AL-Go/blob/main/DEPRECATIONS.md${anchor ? `#${anchor}` : ""}`;
  const repoLines = repos.map((r) => {
    const scopes = (r.scopes && r.scopes.length) ? ` — found in: ${r.scopes.join(", ")}` : "";
    return `  - ${org}/${r.repo}${scopes}`;
  }).join("\n");
  const lines = [
    `Please help migrate the deprecated AL-Go setting \`${key}\` to its replacement across the following ${repos.length === 1 ? "repo" : `${repos.length} repos`}:`,
    ``,
    repoLines,
    ``,
    `Deprecation details:`,
    `  - Deprecated key: \`${key}\``,
    replacement ? `  - Replacement:    \`${replacement}\`` : `  - Replacement:    (see docs)`,
    sunset ? `  - Sunset:         ${sunset}` : null,
    `  - Docs:           ${docsUrl}`,
    ``,
    `For each repo, please:`,
    `  1. Read the relevant AL-Go settings file(s) to confirm where \`${key}\` is currently set.`,
    `  2. Open a PR (via \`gh\` CLI) that removes the deprecated key and sets the replacement key with semantically equivalent values. Consult DEPRECATIONS.md for the exact mapping rules — value shape may differ.`,
    `  3. In the PR description, link to the deprecation docs and mention this is part of an AL-Go settings cleanup.`,
    ``,
    `You can fan out across repos in parallel if it helps.`,
  ].filter(Boolean);
  return lines.join("\n");
}

async function delegateDeprecation({ org, key, repos: repoFilter } = {}) {
  if (!org || !key) throw new CanvasError("invalid_input", "org and key are required");
  if (!copilotSession) throw new CanvasError("no_session", "Copilot session not connected");
  // Resolve from any cached fleet for this org, else compute fresh.
  const fleet = fleetCache.get(`${org}::auto`)
             || fleetCache.get(`${org}::search`)
             || fleetCache.get(`${org}::deep`)
             || (await getFleet(org));
  const names = fleet.repos.map((r) => r.name);
  const deps = await getFleetDeprecations(org, names, {});
  const finding = (deps.keys || []).find((k) => k.key === key);
  if (!finding) throw new CanvasError("not_found", `No deprecation finding for key: ${key}`);
  let repos = finding.repos;
  if (Array.isArray(repoFilter) && repoFilter.length) {
    const want = new Set(repoFilter);
    repos = repos.filter((r) => want.has(r.repo));
    if (repos.length === 0) throw new CanvasError("not_found", `None of the requested repos have ${key}`);
  }
  const prompt = buildDeprecationDelegationPrompt({
    org, key, sunset: finding.sunset, replacement: finding.replacement,
    anchor: finding.anchor, repos,
  });
  copilotSession.send(prompt).catch((err) => {
    console.error("[algo-control-center] delegateDeprecation send failed:", err);
  });
  return { ok: true, key, repos: repos.map((r) => r.repo), prompted: true };
}

const { port } = await startServer({
  webRoot: WEB_ROOT,
  handlers: {
    listOrgs: listUserOrgs,
    getFleet,
    loadMoreRuns,
    loadRunsWindow,
    getRunDetail,
    getJobLogTail,
    getRepoSettingsBundle,
    getFleetDeprecations: async (org, opts = {}) => {
      const fleet = fleetCache.get(`${org}::auto`)
                 || fleetCache.get(`${org}::search`)
                 || fleetCache.get(`${org}::deep`)
                 || (await getFleet(org));
      const names = fleet.repos.map((r) => r.name);
      return getFleetDeprecations(org, names, {
        force: !!opts.force,
        onProgress: (p) => opts.hub && opts.hub.publish("fleet-deps:progress", { org, ...p }),
      });
    },
    getPreferences: loadPreferences,
    savePreferences,
    bulkUpdateAlgoSystemFiles,
    bulkRerunFailed,
    bulkTriggerWorkflow,
    delegateDeprecation,
    delegateRunInvestigation,
  },
});
const iframeUrl = `http://127.0.0.1:${port}/`;

const canvas = createCanvas({
  id: "algo-control-center",
  displayName: "AL-Go Control Center",
  description: "Fleet overview for AL-Go repositories in a GitHub org: workflow health, settings, and bulk actions like 'Update AL-Go System Files' across many repos.",
  inputSchema: {
    type: "object",
    properties: {
      org: { type: "string", description: "GitHub org login to focus on. If omitted, the user picks one in-canvas." },
    },
    additionalProperties: false,
  },
  actions: [
    {
      name: "refresh_fleet",
      description: "Re-scan the selected org for AL-Go repositories and refresh their status.",
      inputSchema: {
        type: "object",
        properties: {
          org: { type: "string" },
          mode: { type: "string", enum: ["auto", "search", "deep"] },
        },
        required: ["org"],
        additionalProperties: false,
      },
      async handler({ input }) {
        const data = await getFleet(input.org, { force: true, mode: input.mode });
        return { org: data.org, repoCount: data.repos.length, discoveryMode: data.discoveryMode, totalOrgRepos: data.totalOrgRepos, fetchedAt: data.fetchedAt };
      },
    },
    {
      name: "select_org",
      description: "Persist the org the user wants to focus on in the control center.",
      inputSchema: {
        type: "object",
        properties: { org: { type: "string" } },
        required: ["org"],
        additionalProperties: false,
      },
      async handler({ input }) {
        const prefs = await loadPreferences();
        prefs.selectedOrg = input.org;
        await savePreferences(prefs);
        return prefs;
      },
    },
    {
      name: "bulk_update_algo_system_files",
      description: "Trigger the 'Update AL-Go System Files' workflow on each of the selected repos in the org.",
      inputSchema: {
        type: "object",
        properties: {
          org: { type: "string" },
          repos: { type: "array", items: { type: "string" }, minItems: 1 },
        },
        required: ["org", "repos"],
        additionalProperties: false,
      },
      async handler({ input }) { return bulkUpdateAlgoSystemFiles(input); },
    },
    {
      name: "bulk_rerun_failed_runs",
      description: "For each selected repo, re-run the failed jobs of the most recent failed workflow run.",
      inputSchema: {
        type: "object",
        properties: {
          org: { type: "string" },
          repos: { type: "array", items: { type: "string" }, minItems: 1 },
        },
        required: ["org", "repos"],
        additionalProperties: false,
      },
      async handler({ input }) { return bulkRerunFailed(input); },
    },
    {
      name: "bulk_trigger_workflow",
      description: "Trigger an arbitrary workflow (by file name, e.g. 'CICD.yaml') on each selected repo.",
      inputSchema: {
        type: "object",
        properties: {
          org: { type: "string" },
          repos: { type: "array", items: { type: "string" }, minItems: 1 },
          workflow: { type: "string" },
          ref: { type: "string" },
          inputs: { type: "object", additionalProperties: { type: "string" } },
        },
        required: ["org", "repos", "workflow"],
        additionalProperties: false,
      },
      async handler({ input }) { return bulkTriggerWorkflow(input); },
    },
  ],
  async open({ input }) {
    // Honour caller-supplied org by writing it into preferences so the iframe
    // picks it up on first load. Idempotent across reopen/rehydrate.
    if (input && input.org) {
      const prefs = await loadPreferences();
      if (prefs.selectedOrg !== input.org) {
        prefs.selectedOrg = input.org;
        await savePreferences(prefs);
      }
    }
    return { url: iframeUrl, title: "AL-Go Control Center", status: "ready" };
  },
});

await joinSession({ canvases: [canvas] }).then((session) => {
  copilotSession = session;
});
