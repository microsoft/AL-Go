// AL-Go repository discovery and bulk-action helpers.

import { ghApi, ghApiRaw, ghGraphql, runGh } from "./gh.mjs";

// Repo discovery via GitHub code search. Cheap on large orgs because it goes
// straight to repos that contain `.github/AL-Go-Settings.json` instead of
// scanning every repo. Returns deduped repo names.
async function searchAlGoRepos(org) {
  const args = [
    "search", "code",
    "filename:AL-Go-Settings.json",
    "--owner", org,
    "--limit", "1000",
    "--json", "repository,path",
  ];
  let raw;
  try { raw = await runGh(args, { preferKeyring: true }); }
  catch (err) {
    if (err.stdout && err.stdout.trim().startsWith("[")) raw = err.stdout;
    else throw err;
  }
  const hits = JSON.parse(raw || "[]");
  const names = new Set();
  for (const h of hits) {
    if (h.path === ".github/AL-Go-Settings.json" && h.repository && h.repository.nameWithOwner) {
      const [, name] = h.repository.nameWithOwner.split("/");
      if (name) names.add(name);
    }
  }
  return [...names];
}

function pLimit(n) {
  const queue = [];
  let active = 0;
  const next = () => {
    if (active >= n || queue.length === 0) return;
    active++;
    const { fn, resolve, reject } = queue.shift();
    fn().then(
      (v) => { active--; resolve(v); next(); },
      (e) => { active--; reject(e); next(); },
    );
  };
  return (fn) => new Promise((resolve, reject) => {
    queue.push({ fn, resolve, reject });
    next();
  });
}

export async function listUserOrgs() {
  const orgs = await ghApi("/user/orgs?per_page=100", { paginate: true });
  const flat = Array.isArray(orgs) ? orgs.flat() : [];
  return flat.map((o) => ({ login: o.login, avatarUrl: o.avatar_url }));
}

export async function listOrgRepos(org) {
  const pages = await ghApi(`/orgs/${encodeURIComponent(org)}/repos?per_page=100&type=all`, { paginate: true });
  const flat = Array.isArray(pages) ? pages.flat() : [];
  return flat
    .filter((r) => !r.archived)
    .map((r) => ({
      name: r.name,
      fullName: r.full_name,
      defaultBranch: r.default_branch,
      htmlUrl: r.html_url,
      pushedAt: r.pushed_at,
      visibility: r.visibility,
      openIssues: r.open_issues_count,
    }));
}

export async function fetchAlGoSettings(org, repo) {
  try {
    const data = await ghApi(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/contents/.github/AL-Go-Settings.json`);
    if (!data || !data.content) return null;
    const json = Buffer.from(data.content, "base64").toString("utf8");
    return JSON.parse(json);
  } catch (err) {
    if (/HTTP 404|Not Found/i.test(err.message)) return null;
    return null;
  }
}

// Batched GraphQL probe: returns Map<repoName, { settings, openPRs, defaultBranch }>
// for repos where AL-Go-Settings.json exists. Repos without the file are absent.
async function probeBatchGraphql(org, repoNames) {
  if (repoNames.length === 0) return new Map();
  const fragments = repoNames.map((name, i) => {
    return `
      r${i}: repository(owner: "${org}", name: ${JSON.stringify(name)}) {
        name
        url
        pushedAt
        visibility
        isArchived
        isTemplate
        defaultBranchRef { name }
        pullRequests(states: OPEN) { totalCount }
        settings: object(expression: "HEAD:.github/AL-Go-Settings.json") {
          ... on Blob { text isBinary }
        }
      }`;
  }).join("\n");
  const query = `query AlGoProbe { ${fragments} }`;
  const data = await ghGraphql(query);
  const out = new Map();
  repoNames.forEach((name, i) => {
    const node = data && data[`r${i}`];
    if (!node || node.isArchived || node.isTemplate) return;
    const blob = node.settings;
    if (!blob || blob.isBinary || !blob.text) return;
    let settings;
    try { settings = JSON.parse(blob.text); }
    catch { return; }
    out.set(node.name, {
      settings,
      openPRs: (node.pullRequests && node.pullRequests.totalCount) || 0,
      defaultBranch: (node.defaultBranchRef && node.defaultBranchRef.name) || "main",
      htmlUrl: node.url,
      pushedAt: node.pushedAt,
      visibility: (node.visibility || "").toLowerCase() || null,
    });
  });
  return out;
}

async function probeBatched(org, repoNames, { onProgress, total } = {}) {
  const BATCH = 40;
  const result = new Map();
  let done = 0;
  for (let i = 0; i < repoNames.length; i += BATCH) {
    const slice = repoNames.slice(i, i + BATCH);
    try {
      const partial = await probeBatchGraphql(org, slice);
      for (const [k, v] of partial) result.set(k, v);
    } catch (err) {
      // On a batch failure, halve and retry once; then fall back to skipping.
      if (slice.length > 1) {
        const mid = Math.floor(slice.length / 2);
        try {
          const a = await probeBatchGraphql(org, slice.slice(0, mid));
          const b = await probeBatchGraphql(org, slice.slice(mid));
          for (const [k, v] of a) result.set(k, v);
          for (const [k, v] of b) result.set(k, v);
        } catch {
          // give up on this slice
        }
      }
    }
    done += slice.length;
    if (onProgress) onProgress({ phase: "probe", done, total: total || repoNames.length });
  }
  return result;
}

async function latestRuns(org, repo, { page = 1, perPage = 30, since = null } = {}) {
  try {
    const sinceQs = since ? `&created=%3E%3D${encodeURIComponent(since)}` : "";
    const data = await ghApi(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions/runs?per_page=${perPage}&page=${page}${sinceQs}`);
    return {
      runs: (data && data.workflow_runs) || [],
      totalCount: (data && data.total_count) || 0,
    };
  } catch {
    return { runs: [], totalCount: 0 };
  }
}

// Fetch the latest run for a specific workflow file on the default branch
// directly. We need a targeted query because on very active repos (e.g.
// microsoft/BCApps) the latest N runs across all workflows can be entirely
// dominated by PR builds, labelers, validators, etc., so the workflow we care
// about never appears in a general listing — making the overview show
// "no runs" even though it ran today.
async function latestWorkflowRunOnBranch(org, repo, defaultBranch, workflowFile) {
  try {
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const data = await ghApi(
      `/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions/workflows/${encodeURIComponent(workflowFile)}/runs?branch=${encodeURIComponent(defaultBranch)}&per_page=1&created=%3E%3D${encodeURIComponent(since)}`
    );
    const runs = (data && data.workflow_runs) || [];
    return runs[0] || null;
  } catch {
    return null;
  }
}

// Normalize one raw workflow run from the REST API into the shape the
// Runs view consumes.
function normalizeRun(r) {
  return {
    runId: r.id,
    workflow: (r.name || "").trim(),
    workflowPath: r.path,       // e.g. .github/workflows/CICD.yaml
    htmlUrl: r.html_url,
    status: r.status,
    conclusion: r.conclusion,
    headBranch: r.head_branch,
    headSha: r.head_sha,
    actor: r.actor && { login: r.actor.login, avatarUrl: r.actor.avatar_url },
    event: r.event,
    runNumber: r.run_number,
    attempt: r.run_attempt,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    displayTitle: r.display_title,
  };
}

export async function fetchMoreRunsForRepo(org, repo, page, perPage = 30, since = null) {
  const { runs, totalCount } = await latestRuns(org, repo, { page, perPage, since });
  return {
    runs: runs.map(normalizeRun),
    exhausted: runs.length < perPage,
    totalCount,
  };
}

function summarizeRuns(rawRuns, { defaultBranch, ciRun, nextMajorRun } = {}) {
  const byWorkflow = new Map();
  for (const r of rawRuns) {
    if (!byWorkflow.has(r.name)) {
      byWorkflow.set(r.name, {
        name: r.name,
        status: r.status,
        conclusion: r.conclusion,
        htmlUrl: r.html_url,
        runId: r.id,
        updatedAt: r.updated_at,
        headBranch: r.head_branch,
        path: r.path,
      });
    }
  }
  // CI badge: prefer a direct hit on CICD.yaml@<defaultBranch> when available,
  // since the general-runs window can miss it entirely on busy repos. Fall back
  // to scanning recent runs on the default branch for repos using a different
  // workflow file (or older AL-Go versions).
  let ci = null;
  if (ciRun) {
    ci = {
      name: ciRun.name,
      status: ciRun.status,
      conclusion: ciRun.conclusion,
      htmlUrl: ciRun.html_url,
      runId: ciRun.id,
      updatedAt: ciRun.updated_at,
      headBranch: ciRun.head_branch,
      path: ciRun.path,
    };
  } else {
    const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
    const recentByWorkflow = new Map();
    for (const r of rawRuns) {
      if (defaultBranch && r.head_branch !== defaultBranch) continue;
      const updated = r.updated_at ? new Date(r.updated_at).getTime() : 0;
      if (updated < cutoff) continue;
      if (!recentByWorkflow.has(r.name)) {
        recentByWorkflow.set(r.name, {
          name: r.name,
          status: r.status,
          conclusion: r.conclusion,
          htmlUrl: r.html_url,
          runId: r.id,
          updatedAt: r.updated_at,
          headBranch: r.head_branch,
          path: r.path,
        });
      }
    }
    const ciNames = ["CI/CD", "Pull Request Build"];
    ci = ciNames
      .map((n) => recentByWorkflow.get(n))
      .find(Boolean) || [...recentByWorkflow.values()].find((w) => /CI|Build/i.test(w.name)) || null;
  }
  // Next Major badge: targeted fetch only — NextMajor.yaml is scheduled
  // weekly, so the general-runs window almost never includes it. If the repo
  // doesn't have the workflow at all, this stays null and the column renders
  // "no runs", which is the correct signal.
  const nextMajor = nextMajorRun
    ? {
        name: nextMajorRun.name,
        status: nextMajorRun.status,
        conclusion: nextMajorRun.conclusion,
        htmlUrl: nextMajorRun.html_url,
        runId: nextMajorRun.id,
        updatedAt: nextMajorRun.updated_at,
        headBranch: nextMajorRun.head_branch,
        path: nextMajorRun.path,
      }
    : null;
  return {
    ci,
    nextMajor,
    latest: [...byWorkflow.values()].slice(0, 5),
    anyFailing: ci ? ci.conclusion === "failure" : false,
    all: rawRuns.map(normalizeRun),
  };
}

function extractTemplateRef(url) {
  const m = /@([^/]+?)$/.exec(url);
  return m ? m[1] : "unknown";
}

async function orgRepoCount(org) {
  try {
    const q = `query OrgSize { organization(login: "${org}") { repositories(privacy: null) { totalCount } } }`;
    const d = await ghGraphql(q);
    return (d && d.organization && d.organization.repositories && d.organization.repositories.totalCount) || null;
  } catch {
    return null;
  }
}

export async function gatherFleet(org, { onProgress, mode } = {}) {
  let useSearch;
  let totalOrgRepos = null;
  if (mode === "search") useSearch = true;
  else if (mode === "deep") useSearch = false;
  else {
    totalOrgRepos = await orgRepoCount(org);
    useSearch = totalOrgRepos != null && totalOrgRepos > 250;
  }
  const discoveryMode = useSearch ? "search" : "deep";
  let candidateRepos;
  if (useSearch) {
    let names = [];
    try { names = await searchAlGoRepos(org); } catch { names = []; }
    candidateRepos = names.map((name) => ({ name, fullName: `${org}/${name}` }));
  } else {
    candidateRepos = await listOrgRepos(org);
  }
  if (onProgress) onProgress({ phase: "list", done: candidateRepos.length, total: candidateRepos.length });

  const probed = await probeBatched(org, candidateRepos.map((r) => r.name), {
    onProgress,
    total: candidateRepos.length,
  });
  const algoRepos = candidateRepos.filter((r) => probed.has(r.name));
  // Phase 2: per-repo workflow runs (REST — no GraphQL equivalent), parallel-limited.
  const limit = pLimit(8);
  const out = [];
  let runsDone = 0;
  await Promise.all(algoRepos.map((repo) => limit(async () => {
    const probe = probed.get(repo.name);
    const defaultBranch = probe.defaultBranch || "main";
    const [{ runs }, ciRun, nextMajorRun] = await Promise.all([
      latestRuns(org, repo.name),
      latestWorkflowRunOnBranch(org, repo.name, defaultBranch, "CICD.yaml"),
      latestWorkflowRunOnBranch(org, repo.name, defaultBranch, "NextMajor.yaml"),
    ]);
    runsDone++;
    if (onProgress) onProgress({ phase: "runs", done: runsDone, total: algoRepos.length });
    const runSummary = summarizeRuns(runs, { defaultBranch, ciRun, nextMajorRun });
    const s = probe.settings;
    out.push({
      name: repo.name,
      fullName: `${org}/${repo.name}`,
      htmlUrl: probe.htmlUrl || `https://github.com/${org}/${repo.name}`,
      pushedAt: probe.pushedAt || null,
      visibility: probe.visibility || null,
      defaultBranch: probe.defaultBranch || "main",
      algoVersion: s.templateUrl
        ? extractTemplateRef(s.templateUrl)
        : (s.templateSha ? s.templateSha.substring(0, 7) : "Developer/Private"),
      templateUrl: s.templateUrl || null,
      country: s.country || null,
      repoVersion: s.repoVersion || null,
      type: s.type || null,
      runs: runSummary,
      openPRs: probe.openPRs,
    });
  })));
  out.sort((a, b) => a.name.localeCompare(b.name));
  return { repos: out, discoveryMode, totalOrgRepos };
}

export async function triggerWorkflow(org, repo, workflowFile, ref, inputs) {
  const args = ["workflow", "run", workflowFile, "-R", `${org}/${repo}`, "-r", ref];
  if (inputs) {
    for (const [k, v] of Object.entries(inputs)) {
      args.push("-f", `${k}=${v}`);
    }
  }
  await runGh(args, { preferKeyring: true });
  return { ok: true };
}

export async function rerunFailedLatest(org, repo) {
  const { runs } = await latestRuns(org, repo);
  const failing = runs.find((r) => r.conclusion === "failure");
  if (!failing) return { ok: false, reason: "no_failing_run" };
  await runGh(["run", "rerun", String(failing.id), "-R", `${org}/${repo}`, "--failed"], { preferKeyring: true });
  return { ok: true, runId: failing.id };
}

// Fetch a single run with its jobs and steps. Used by the Run drill-down
// side panel in the Runs view.
export async function getRunDetail(org, repo, runId) {
  const [run, jobsResp] = await Promise.all([
    ghApi(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions/runs/${encodeURIComponent(runId)}`).catch(() => null),
    ghApi(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions/runs/${encodeURIComponent(runId)}/jobs?per_page=100`).catch(() => null),
  ]);
  if (!run) throw new Error(`run ${runId} not found in ${org}/${repo}`);
  const jobs = (jobsResp && jobsResp.jobs) || [];
  return {
    runId: run.id,
    workflow: run.name,
    htmlUrl: run.html_url,
    status: run.status,
    conclusion: run.conclusion,
    headBranch: run.head_branch,
    headSha: run.head_sha,
    runNumber: run.run_number,
    attempt: run.run_attempt,
    event: run.event,
    createdAt: run.created_at,
    updatedAt: run.updated_at,
    actor: run.actor && { login: run.actor.login, avatarUrl: run.actor.avatar_url },
    displayTitle: run.display_title,
    jobs: jobs.map((j) => ({
      id: j.id,
      name: j.name,
      status: j.status,
      conclusion: j.conclusion,
      startedAt: j.started_at,
      completedAt: j.completed_at,
      htmlUrl: j.html_url,
      runnerName: j.runner_name,
      labels: j.labels || [],
      steps: (j.steps || []).map((s) => ({
        name: s.name,
        status: s.status,
        conclusion: s.conclusion,
        number: s.number,
        startedAt: s.started_at,
        completedAt: s.completed_at,
      })),
      failedStep: (j.steps || []).find((s) => s.conclusion === "failure")?.name || null,
    })),
  };
}

// Return the last `lines` lines of a job's log. Returns null when the log is
// no longer available (expired / 410) or the user lacks access.
export async function getJobLogTail(org, repo, jobId, lines = 80) {
  const raw = await ghApiRaw(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions/jobs/${encodeURIComponent(jobId)}/logs`);
  if (!raw) return null;
  // GitHub job logs prefix every line with an ISO timestamp; strip it for
  // readability while keeping the structural prefix (e.g. `##[group]`).
  const stripped = raw.split(/\r?\n/).map((l) => l.replace(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s?/, ""));
  const tail = stripped.slice(-Math.max(1, lines));
  return tail.join("\n");
}

// ---------------------------------------------------------------------------
// Settings inspector: repo-wide settings (layers 1-5 of the AL-Go hierarchy).
//
// Layers, in precedence order (later wins per top-level key):
//   1. ALGoOrgSettings                                  (GitHub org variable)
//   2. .github/AL-Go-TemplateRepoSettings.doNotEdit.json (repo file, template-managed)
//   3. .github/AL-Go-Settings.json                       (repo file, hand-edited)
//   4. ALGoRepoSettings                                  (GitHub repo variable)
//   5. .github/AL-Go-TemplateProjectSettings.doNotEdit.json (repo file, template-managed)
//
// Layers 6-9 (per-project, per-workflow, per-user) are intentionally NOT included
// in this bundle.
// ---------------------------------------------------------------------------

// One org variable value is shared by every repo in the org; cache briefly to
// avoid N extra API calls when the user clicks around the Settings tab.
const orgVarCache = new Map(); // org -> { layer, fetchedAt }
const ORG_VAR_TTL_MS = 60_000;

function classifyError(err) {
  const msg = err && err.message ? err.message : String(err);
  if (/HTTP 404|Not Found/i.test(msg)) return { kind: "absent" };
  if (/HTTP 401|Unauthor|HTTP 403|Forbidden/i.test(msg)) return { kind: "forbidden", message: msg };
  return { kind: "error", message: msg };
}

async function fetchRepoFile(org, repo, filePath) {
  const layer = { source: filePath, kind: "file", status: "absent", value: null, raw: null, message: null };
  try {
    const data = await ghApi(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/contents/${filePath}`);
    if (!data || !data.content) return layer;
    const raw = Buffer.from(data.content, "base64").toString("utf8");
    layer.raw = raw;
    layer.htmlUrl = data.html_url || null;
    try {
      layer.value = JSON.parse(raw);
      layer.status = "present";
    } catch (e) {
      layer.status = "invalid";
      layer.message = `JSON parse error: ${e.message}`;
    }
  } catch (err) {
    const c = classifyError(err);
    if (c.kind === "absent") layer.status = "absent";
    else if (c.kind === "forbidden") { layer.status = "forbidden"; layer.message = c.message; }
    else { layer.status = "error"; layer.message = c.message; }
  }
  return layer;
}

async function fetchVariable(scopePath, name) {
  const layer = { source: name, kind: "variable", status: "absent", value: null, raw: null, message: null };
  try {
    const data = await ghApi(`${scopePath}/actions/variables/${encodeURIComponent(name)}`);
    if (!data) return layer;
    layer.raw = data.value || "";
    try {
      layer.value = layer.raw ? JSON.parse(layer.raw) : {};
      layer.status = "present";
    } catch (e) {
      layer.status = "invalid";
      layer.message = `JSON parse error: ${e.message}`;
    }
  } catch (err) {
    const c = classifyError(err);
    if (c.kind === "absent") layer.status = "absent";
    else if (c.kind === "forbidden") { layer.status = "forbidden"; layer.message = c.message; }
    else { layer.status = "error"; layer.message = c.message; }
  }
  return layer;
}

async function fetchOrgSettingsVariable(org) {
  const cached = orgVarCache.get(org);
  if (cached && Date.now() - cached.fetchedAt < ORG_VAR_TTL_MS) return cached.layer;
  const layer = await fetchVariable(`/orgs/${encodeURIComponent(org)}`, "ALGoOrgSettings");
  orgVarCache.set(org, { layer, fetchedAt: Date.now() });
  return layer;
}

// Merge top-level keys, last layer wins. We don't deep-merge — that matches
// AL-Go's "last applied settings file wins" semantics (per the docs).
function mergeLayers(layers) {
  const out = {};
  const provenance = {}; // key -> source label of the layer that supplied the final value
  for (const layer of layers) {
    if (layer.status !== "present" || !layer.value || typeof layer.value !== "object") continue;
    for (const [k, v] of Object.entries(layer.value)) {
      out[k] = v;
      provenance[k] = layer.source;
    }
  }
  return { effective: out, provenance };
}

export async function getRepoSettingsBundle(org, repo, { includeSecrets = true } = {}) {
  // Fan out all fetches in parallel. The org variable is cached, so a fresh
  // bundle typically costs 4 settings calls + 2 secrets calls per click.
  // Pass { includeSecrets: false } during fleet-wide scans to skip the
  // secrets fetch (2 fewer API calls per repo).
  const settingsPromises = [
    fetchOrgSettingsVariable(org),
    fetchRepoFile(org, repo, ".github/AL-Go-TemplateRepoSettings.doNotEdit.json"),
    fetchRepoFile(org, repo, ".github/AL-Go-Settings.json"),
    fetchVariable(`/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}`, "ALGoRepoSettings"),
    fetchRepoFile(org, repo, ".github/AL-Go-TemplateProjectSettings.doNotEdit.json"),
  ];
  const secretsPromise = includeSecrets ? fetchRepoSecretsAndVars(org, repo) : Promise.resolve(null);
  const [orgVar, templateRepo, repoFile, repoVar, templateProject, secretsAndVars] = await Promise.all([
    ...settingsPromises,
    secretsPromise,
  ]);

  // Decorate each layer with display metadata so the frontend doesn't need to
  // hardcode the hierarchy. Order matches AL-Go's precedence (lowest first).
  const layers = [
    { ...orgVar,          order: 1, scope: "org",  label: "ALGoOrgSettings (org variable)" },
    { ...templateRepo,    order: 2, scope: "repo", label: "Template repo settings (managed)" },
    { ...repoFile,        order: 3, scope: "repo", label: "AL-Go-Settings.json (repo)" },
    { ...repoVar,         order: 4, scope: "repo", label: "ALGoRepoSettings (repo variable)" },
    { ...templateProject, order: 5, scope: "repo", label: "Template project settings (managed)" },
  ];

  const { effective, provenance } = mergeLayers(layers);
  const deprecations = scanDeprecations(layers, effective);

  return { org, repo, layers, effective, provenance, deprecations, secretsAndVars };
}

// Fetch repo-level Actions secrets and variables. Secret values are never
// returned by the API (you only get names + timestamps), variables include
// values. Falls back to a `status: "forbidden"` block for users without
// repo-admin access so the UI can render a hint instead of an error.
async function fetchRepoSecretsAndVars(org, repo) {
  const base = `/repos/${encodeURIComponent(org)}/${encodeURIComponent(repo)}/actions`;
  const result = { secrets: null, variables: null };
  const [secretsRes, varsRes] = await Promise.allSettled([
    ghApi(`${base}/secrets?per_page=100`),
    ghApi(`${base}/variables?per_page=100`),
  ]);
  const settle = (res) => {
    if (res.status === "fulfilled") {
      const list = res.value && Array.isArray(res.value.secrets) ? res.value.secrets
                 : res.value && Array.isArray(res.value.variables) ? res.value.variables
                 : [];
      return { status: "ok", items: list, total: res.value && res.value.total_count != null ? res.value.total_count : list.length };
    }
    const c = classifyError(res.reason);
    if (c.kind === "absent") return { status: "absent", items: [], total: 0 };
    if (c.kind === "forbidden") return { status: "forbidden", items: [], total: 0, message: c.message };
    return { status: "error", items: [], total: 0, message: c.message };
  };
  result.secrets = settle(secretsRes);
  result.variables = settle(varsRes);
  return result;
}

// ── Deprecation detection ───────────────────────────────────────────────────
// Sourced from DEPRECATIONS.md in microsoft/AL-Go. Keep this list in sync
// when new deprecations are added or sunset dates change. Anchors map to
// https://github.com/microsoft/AL-Go/blob/main/DEPRECATIONS.md#<anchor>.
const DEPRECATED_SETTINGS = {
  unusedALGoSystemFiles: {
    sunset: "2026-10-01",
    replacement: "customALGoFiles.filesToExclude",
    anchor: "unusedalgosystemfiles",
  },
  alwaysBuildAllProjects: {
    sunset: "2025-10-01",
    replacement: "incrementalBuilds.onPull_Request",
    anchor: "alwaysbuildallprojects",
  },
  cleanModePreprocessorSymbols: {
    sunset: "2025-04-01",
    replacement: "preprocessorSymbols (via conditionalSettings.buildModes)",
    anchor: "cleanmodepreprocessorsymbols",
  },
};

// Dynamic patterns where the setting key is generated (e.g. "<workflow>Schedule").
const DEPRECATED_PATTERNS = [
  {
    test: (key) => key.endsWith("Schedule") && key !== "workflowSchedule",
    sunset: "2025-10-01",
    replacement: "workflowSchedule (via conditionalSettings or workflow-specific settings file)",
    anchor: "_workflow_schedule",
  },
];

function lookupDeprecation(key) {
  if (DEPRECATED_SETTINGS[key]) return DEPRECATED_SETTINGS[key];
  for (const p of DEPRECATED_PATTERNS) {
    if (p.test(key)) {
      const { test, ...rest } = p;
      return rest;
    }
  }
  return null;
}

// Walk every layer (top-level keys + nested conditionalSettings[].settings) and
// every key in the merged effective view. Return one entry per (key, location)
// pair so the UI can show where the deprecated value lives.
function scanDeprecations(layers, effective) {
  const hits = [];
  for (const layer of layers) {
    if (!layer.value || typeof layer.value !== "object") continue;
    for (const key of Object.keys(layer.value)) {
      const info = lookupDeprecation(key);
      if (info) hits.push({ key, ...info, layerOrder: layer.order, layerLabel: layer.label, scope: "top" });
    }
    const cs = Array.isArray(layer.value.conditionalSettings) ? layer.value.conditionalSettings : [];
    cs.forEach((entry, idx) => {
      if (!entry || typeof entry !== "object" || !entry.settings) return;
      for (const key of Object.keys(entry.settings)) {
        const info = lookupDeprecation(key);
        if (info) hits.push({ key, ...info, layerOrder: layer.order, layerLabel: layer.label, scope: `conditionalSettings[${idx}]` });
      }
    });
  }
  for (const key of Object.keys(effective || {})) {
    const info = lookupDeprecation(key);
    if (info && !hits.some((h) => h.key === key && h.scope === "effective")) {
      hits.push({ key, ...info, scope: "effective" });
    }
  }
  return hits;
}

// ── Fleet-wide deprecation roll-up ──────────────────────────────────────────
// Cached because scanning every repo costs N × 4 API calls (org variable is
// already cached separately). Invalidated by passing { force: true }.
const fleetDepCache = new Map(); // org -> { fetchedAt, totalRepos, scanned, errors, byKey }
const FLEET_DEP_TTL_MS = 5 * 60_000;

// Cap the concurrent settings fetches so a 50-repo org doesn't fan out 250+
// `gh api` spawns at once and hit rate limits.
async function runWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let i = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const idx = i++;
      if (idx >= items.length) return;
      results[idx] = await worker(items[idx], idx);
    }
  });
  await Promise.all(runners);
  return results;
}

export async function getFleetDeprecations(org, repoNames, { force = false, onProgress } = {}) {
  const cached = fleetDepCache.get(org);
  if (!force && cached && Date.now() - cached.fetchedAt < FLEET_DEP_TTL_MS) {
    return cached;
  }
  const names = Array.isArray(repoNames) ? repoNames.slice() : [];
  const byKey = new Map(); // key -> { key, sunset, replacement, anchor, repos: [{repo, scopes:[]}] }
  const errors = [];
  let done = 0;
  await runWithConcurrency(names, 6, async (repo) => {
    try {
      const bundle = await getRepoSettingsBundle(org, repo, { includeSecrets: false });
      for (const dep of bundle.deprecations || []) {
        let entry = byKey.get(dep.key);
        if (!entry) {
          entry = { key: dep.key, sunset: dep.sunset, replacement: dep.replacement, anchor: dep.anchor, repos: [] };
          byKey.set(dep.key, entry);
        }
        let r = entry.repos.find((x) => x.repo === repo);
        if (!r) { r = { repo, scopes: [] }; entry.repos.push(r); }
        const scopeLabel = dep.scope === "effective"
          ? "effective"
          : `${dep.layerLabel || "?"}${dep.scope && dep.scope !== "top" ? ` → ${dep.scope}` : ""}`;
        if (!r.scopes.includes(scopeLabel)) r.scopes.push(scopeLabel);
      }
    } catch (err) {
      errors.push({ repo, error: err.message });
    } finally {
      done++;
      if (onProgress) onProgress({ done, total: names.length, repo });
    }
  });
  // Sort: most-affected keys first, repos alphabetically within each key.
  const keys = [...byKey.values()]
    .map((e) => ({ ...e, repos: e.repos.sort((a, b) => a.repo.localeCompare(b.repo)) }))
    .sort((a, b) => b.repos.length - a.repos.length || a.key.localeCompare(b.key));
  const out = {
    org,
    fetchedAt: Date.now(),
    totalRepos: names.length,
    scanned: done,
    errors,
    keys,
  };
  fleetDepCache.set(org, out);
  return out;
}
