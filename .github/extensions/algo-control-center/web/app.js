"use strict";

const state = {
  orgs: [],
  selectedOrg: null,
  fleet: [],
  selection: new Set(),
  filter: "",
  view: "fleet",
  runsFilter: { workflow: "", conclusion: "", repo: "", text: "" },
  runsHasMore: true,
  runsLoadingMore: false,
  runsWindowDays: 7,
  runsWindowLoaded: false,
  runsWindowLoading: false,
  sort: { key: "name", dir: "asc" },
  settingsFilter: "",
  selectedSettingsRepo: null,
  settingsBundle: null,
  settingsLoading: false,
  fleetDeps: null,            // { keys, totalRepos, scanned, errors, fetchedAt } or { error }
  fleetDepsLoading: false,
  fleetDepsExpanded: new Set(), // expanded deprecation keys
};

// AL-Go workflow files shipped via the official templates (union of PTE,
// AppSource App and Power Platform Solution templates). Maps the workflow
// filename to its GitHub Actions display name (from the YAML `name:` field).
// Used to keep the Runs view focused on AL-Go's own pipelines and to expose
// the full set in the filter dropdown even when no runs are loaded.
const AL_GO_WORKFLOWS = [
  { file: "CICD.yaml", name: "CI/CD" },
  { file: "PullRequestHandler.yaml", name: "Pull Request Build" },
  { file: "_BuildALGoProject.yaml", name: "_Build AL-Go project" },
  { file: "_BuildPowerPlatformSolution.yaml", name: "_Build PowerPlatform Solution" },
  { file: "AddExistingAppOrTestApp.yaml", name: "Add existing app or test app" },
  { file: "CreateApp.yaml", name: "Create a new app" },
  { file: "CreateOnlineDevelopmentEnvironment.yaml", name: "Create Online Dev. Environment" },
  { file: "CreatePerformanceTestApp.yaml", name: "Create a new performance test app" },
  { file: "CreateRelease.yaml", name: "Create release" },
  { file: "CreateTestApp.yaml", name: "Create a new test app" },
  { file: "Current.yaml", name: "Test Current" },
  { file: "DeployReferenceDocumentation.yaml", name: "Deploy Reference Documentation" },
  { file: "IncrementVersionNumber.yaml", name: "Increment Version Number" },
  { file: "NextMajor.yaml", name: "Test Next Major" },
  { file: "NextMinor.yaml", name: "Test Next Minor" },
  { file: "PublishToAppSource.yaml", name: "Publish To AppSource" },
  { file: "PublishToEnvironment.yaml", name: "Publish To Environment" },
  { file: "PullPowerPlatformChanges.yaml", name: "Pull Power Platform changes" },
  { file: "PushPowerPlatformChanges.yaml", name: "Push Power Platform changes" },
  { file: "Troubleshooting.yaml", name: "Troubleshooting" },
  { file: "UpdateGitHubGoSystemFiles.yaml", name: "Update AL-Go System Files" },
];
const AL_GO_WORKFLOW_FILES = new Set(AL_GO_WORKFLOWS.map((w) => w.file));
const AL_GO_WORKFLOW_NAMES = AL_GO_WORKFLOWS.map((w) => w.name).sort((a, b) => a.localeCompare(b));

function isAlGoWorkflow(workflowPath) {
  if (!workflowPath) return false;
  const slash = workflowPath.lastIndexOf("/");
  const file = slash >= 0 ? workflowPath.slice(slash + 1) : workflowPath;
  return AL_GO_WORKFLOW_FILES.has(file);
}

// CI conclusion ordering for sort: worst first when ascending so users can
// see failures with one click.
const CI_RANK = {
  failure: 0,
  startup_failure: 0,
  timed_out: 1,
  cancelled: 2,
  action_required: 3,
  in_progress: 4,
  queued: 5,
  waiting: 5,
  neutral: 6,
  skipped: 7,
  success: 8,
};

function sortValue(repo, key) {
  switch (key) {
    case "name": return (repo.name || "").toLowerCase();
    case "algoVersion": return (repo.algoVersion || "").toLowerCase();
    case "repoVersion": return (repo.repoVersion || "").toLowerCase();
    case "country": return (repo.country || "").toLowerCase();
    case "type": return (repo.type || "").toLowerCase();
    case "ci": {
      const c = repo.runs && repo.runs.ci && repo.runs.ci.conclusion;
      return c in CI_RANK ? CI_RANK[c] : 99;
    }
    case "nextMajor": {
      const c = repo.runs && repo.runs.nextMajor && repo.runs.nextMajor.conclusion;
      return c in CI_RANK ? CI_RANK[c] : 99;
    }
    case "pushedAt": return repo.pushedAt ? new Date(repo.pushedAt).getTime() : 0;
    case "openPRs": return repo.openPRs || 0;
    default: return "";
  }
}

function sortRepos(rows) {
  const { key, dir } = state.sort;
  const mult = dir === "desc" ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = sortValue(a, key);
    const bv = sortValue(b, key);
    if (av < bv) return -1 * mult;
    if (av > bv) return 1 * mult;
    // Stable secondary sort by name to keep ties deterministic.
    return (a.name || "").localeCompare(b.name || "");
  });
}

function updateSortIndicators() {
  $$(".repo-table th.sortable").forEach((th) => {
    th.classList.remove("sort-asc", "sort-desc");
    if (th.dataset.sortKey === state.sort.key) {
      th.classList.add(state.sort.dir === "desc" ? "sort-desc" : "sort-asc");
    }
  });
}

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

function toast(msg, ms = 2400) {
  const el = $("#toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove("show"), ms);
}

async function fetchJSON(url, opts) {
  const r = await fetch(url, opts);
  if (!r.ok) {
    let detail = "";
    try { detail = (await r.json()).error || ""; } catch {}
    throw new Error(`${r.status} ${r.statusText}${detail ? ` — ${detail}` : ""}`);
  }
  return r.json();
}

async function loadOrgs() {
  try {
    const orgs = await fetchJSON("/api/orgs");
    state.orgs = orgs;
    const sel = $("#org-select");
    sel.innerHTML = "";
    if (orgs.length === 0) {
      sel.innerHTML = `<option value="">No orgs available</option>`;
      return;
    }
    sel.innerHTML = `<option value="">Choose an org…</option>` +
      orgs.map((o) => `<option value="${o.login}">${o.login}</option>`).join("");
    const prefs = await fetchJSON("/api/preferences");
    if (prefs.selectedOrg && orgs.some((o) => o.login === prefs.selectedOrg)) {
      sel.value = prefs.selectedOrg;
      state.selectedOrg = prefs.selectedOrg;
      await loadFleet();
    }
  } catch (err) {
    $("#fleet-status").textContent = "Could not list orgs: " + err.message;
  }
}

async function loadFleet({ force, mode } = {}) {
  if (!state.selectedOrg) return;
  state.discoveryMode = mode || state.discoveryMode || "auto";
  $("#fleet-status").textContent = `Scanning ${state.selectedOrg}…`;
  try {
    const params = new URLSearchParams({ org: state.selectedOrg });
    if (force) params.set("force", "1");
    if (state.discoveryMode && state.discoveryMode !== "auto") params.set("mode", state.discoveryMode);
    const data = await fetchJSON(`/api/fleet?${params}`);
    state.fleet = data.repos;
    state.allRuns = null;
    state.runsHasMore = true;
    state.runsWindowLoaded = false;
    renderFleet();
    renderHealth();
    renderRuns();
    $("#fleet-status").textContent = data.repos.length === 0
      ? `No AL-Go repos found in ${data.org}.`
      : `Found ${data.repos.length} AL-Go repo${data.repos.length === 1 ? "" : "s"} in ${data.org}.`;
    $("#total-count").textContent = String(data.repos.length);
    renderDiscoveryBanner(data);
  } catch (err) {
    $("#fleet-status").textContent = "Failed to load fleet: " + err.message;
  }
}

function renderDiscoveryBanner(data) {
  const banner = $("#discovery-banner");
  const msg = $("#discovery-msg");
  if (data.discoveryMode === "search") {
    banner.hidden = false;
    msg.textContent = `Discovery used GitHub code search (~${data.totalOrgRepos ?? "many"} repos in org). Recently created repos may be missing until they're indexed.`;
    $("#deep-scan").textContent = "Switch to deep scan";
    $("#deep-scan").dataset.mode = "deep";
  } else if (data.discoveryMode === "deep" && data.totalOrgRepos && data.totalOrgRepos > 250) {
    banner.hidden = false;
    msg.textContent = `Deep scan over ${data.totalOrgRepos} repos. This is slower than code-search discovery.`;
    $("#deep-scan").textContent = "Switch to search discovery";
    $("#deep-scan").dataset.mode = "search";
  } else {
    banner.hidden = true;
  }
}

function badgeForCI(ci, repoHtmlUrl, opts = {}) {
  const actionsUrl = repoHtmlUrl ? `${repoHtmlUrl}/actions` : null;
  if (!ci) {
    return actionsUrl
      ? `<a class="badge neutral" href="${actionsUrl}" target="_blank" rel="noopener"><span class="dot neutral"></span>no runs</a>`
      : `<span class="badge neutral"><span class="dot neutral"></span>no runs</span>`;
  }
  // Hover-reveal delegate button when this badge represents an actionable
  // failure. Only attached when the caller passes a repo (so we know what
  // to delegate against).
  const repo = opts.repo;
  const isFailing = ci.conclusion === "failure";
  const delegateBtn = (isFailing && repo)
    ? `<button class="badge-delegate" title="Delegate investigation to agent"
        data-delegate-run="${escapeHtml(String(ci.runId))}"
        data-delegate-repo="${escapeHtml(repo)}"
        data-delegate-workflow="${escapeHtml(ci.name || "")}"
        data-delegate-workflow-path="${escapeHtml(ci.path || "")}"
        data-delegate-html-url="${escapeHtml(ci.htmlUrl || "")}"
        data-delegate-head-branch="${escapeHtml(ci.headBranch || "")}"
      >🤖</button>`
    : "";
  let badge;
  if (ci.status && ci.status !== "completed") {
    badge = `<a class="badge warn" href="${ci.htmlUrl}" target="_blank" rel="noopener"><span class="dot warn"></span>${escapeHtml(ci.status)}</a>`;
  } else if (ci.conclusion === "success") {
    badge = `<a class="badge ok" href="${ci.htmlUrl}" target="_blank" rel="noopener"><span class="dot ok"></span>passing</a>`;
  } else if (ci.conclusion === "failure") {
    badge = `<a class="badge fail" href="${ci.htmlUrl}" target="_blank" rel="noopener"><span class="dot fail"></span>failing</a>`;
  } else if (ci.conclusion === "cancelled") {
    badge = `<a class="badge neutral" href="${ci.htmlUrl}" target="_blank" rel="noopener"><span class="dot neutral"></span>cancelled</a>`;
  } else {
    badge = `<a class="badge neutral" href="${ci.htmlUrl}" target="_blank" rel="noopener"><span class="dot neutral"></span>${escapeHtml(ci.conclusion || "unknown")}</a>`;
  }
  return delegateBtn ? `<span class="badge-wrap">${badge}${delegateBtn}</span>` : badge;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function fmtRelativeTime(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const sec = Math.floor((Date.now() - d.getTime()) / 1000);
  if (sec < 60) return `${sec}s ago`;
  if (sec < 3600) return `${Math.floor(sec/60)}m ago`;
  if (sec < 86400) return `${Math.floor(sec/3600)}h ago`;
  return `${Math.floor(sec/86400)}d ago`;
}

function renderFleet() {
  const tbody = $("#fleet-body");
  const filter = state.filter.trim().toLowerCase();
  const filtered = state.fleet.filter((r) => !filter || r.name.toLowerCase().includes(filter) || (r.repoVersion || "").toLowerCase().includes(filter) || (r.type || "").toLowerCase().includes(filter));
  const rows = sortRepos(filtered);
  updateSortIndicators();
  tbody.innerHTML = rows.map((r) => {
    const checked = state.selection.has(r.name) ? "checked" : "";
    const cls = state.selection.has(r.name) ? "selected" : "";
    const algoCell = r.templateUrl
      ? `<a class="badge neutral" href="${escapeHtml(templateUrlToHtml(r.templateUrl))}" target="_blank" rel="noopener" title="${escapeHtml(r.templateUrl)}">${escapeHtml(r.algoVersion || "?")}</a>`
      : `<span class="badge neutral">${escapeHtml(r.algoVersion || "?")}</span>`;
    const branchUrl = `${r.htmlUrl}/commits/${encodeURIComponent(r.defaultBranch || "main")}`;
    const activityCell = r.pushedAt
      ? `<a class="muted-link" href="${branchUrl}" target="_blank" rel="noopener" title="${escapeHtml(r.pushedAt)}">${escapeHtml(fmtRelativeTime(r.pushedAt))}</a>`
      : `<span class="muted">—</span>`;
    const prsUrl = `${r.htmlUrl}/pulls`;
    const prsCell = r.openPRs > 0
      ? `<a class="badge neutral" href="${prsUrl}" target="_blank" rel="noopener">${r.openPRs}</a>`
      : `<a class="muted-link" href="${prsUrl}" target="_blank" rel="noopener">0</a>`;
    return `<tr class="${cls}" data-repo="${escapeHtml(r.name)}">
      <td class="col-check"><input type="checkbox" class="row-check" ${checked} data-repo="${escapeHtml(r.name)}" /></td>
      <td>
        <a class="repo-link" href="${r.htmlUrl}" target="_blank" rel="noopener">${escapeHtml(r.name)}</a>
        <div class="muted" style="font-size:12px">${escapeHtml(r.visibility || "")}</div>
      </td>
      <td>${algoCell}</td>
      <td>${escapeHtml(r.repoVersion || "—")}</td>
      <td>${escapeHtml(r.type || "—")}</td>
      <td>${badgeForCI(r.runs && r.runs.ci, r.htmlUrl, { repo: r.name })}</td>
      <td>${badgeForCI(r.runs && r.runs.nextMajor, r.htmlUrl, { repo: r.name })}</td>
      <td>${activityCell}</td>
      <td>${prsCell}</td>
    </tr>`;
  }).join("");
  updateSelectionUI();
}

// templateUrl is in the form "https://github.com/<owner>/<repo>@<ref>".
// Turn it into a browsable URL pointing at that ref's tree.
function templateUrlToHtml(url) {
  if (!url) return "#";
  const m = /^(https?:\/\/github\.com\/[^/]+\/[^/@]+)(?:@(.+))?$/.exec(url);
  if (!m) return url;
  const repo = m[1];
  const ref = m[2];
  return ref ? `${repo}/tree/${encodeURIComponent(ref)}` : repo;
}

function renderHealth() {
  // Renders the repo list on the (renamed) Settings tab. The right-side
  // detail panel is populated on click via loadRepoSettings().
  const list = $("#settings-repos");
  if (!list) return;
  if (state.fleet.length === 0) {
    list.innerHTML = `<li class="settings-empty">Pick an org to begin.</li>`;
    return;
  }
  const filter = state.settingsFilter.trim().toLowerCase();
  const rows = state.fleet
    .filter((r) => !filter || r.name.toLowerCase().includes(filter))
    .sort((a, b) => a.name.localeCompare(b.name));
  list.innerHTML = rows.map((r) => {
    const sel = state.selectedSettingsRepo === r.name ? " selected" : "";
    return `<li class="settings-repo${sel}" data-repo="${escapeHtml(r.name)}">
      <span class="settings-repo-name">${escapeHtml(r.name)}</span>
      <span class="muted settings-repo-sub">${escapeHtml(r.algoVersion || "?")}</span>
    </li>`;
  }).join("");
  // Clear selection if the previously-selected repo got filtered out.
  if (state.selectedSettingsRepo && !rows.some((r) => r.name === state.selectedSettingsRepo)) {
    state.selectedSettingsRepo = null;
    state.settingsBundle = null;
    renderSettingsPanel();
  }
}

async function loadRepoSettings(repo) {
  if (!state.selectedOrg || !repo) return;
  state.selectedSettingsRepo = repo;
  state.settingsBundle = null;
  state.settingsLoading = true;
  renderHealth();
  renderSettingsPanel();
  try {
    const data = await fetchJSON(`/api/repo-settings?org=${encodeURIComponent(state.selectedOrg)}&repo=${encodeURIComponent(repo)}`);
    if (state.selectedSettingsRepo !== repo) return; // user moved on
    state.settingsBundle = data;
  } catch (err) {
    if (state.selectedSettingsRepo !== repo) return;
    state.settingsBundle = { error: err.message };
  } finally {
    state.settingsLoading = false;
    renderSettingsPanel();
  }
}

function renderSettingsPanel() {
  const panel = $("#settings-panel");
  if (!panel) return;
  if (!state.selectedSettingsRepo) {
    panel.innerHTML = `<div class="settings-empty">Pick a repo to inspect its settings.</div>`;
    return;
  }
  const repo = state.selectedSettingsRepo;
  if (state.settingsLoading) {
    panel.innerHTML = `<div class="settings-empty">Loading settings for ${escapeHtml(repo)}…</div>`;
    return;
  }
  const b = state.settingsBundle;
  if (!b) { panel.innerHTML = ""; return; }
  if (b.error) {
    panel.innerHTML = `<div class="settings-empty">Failed to load: ${escapeHtml(b.error)}</div>`;
    return;
  }
  const repoUrl = `https://github.com/${encodeURIComponent(b.org)}/${encodeURIComponent(b.repo)}`;
  const effective = b.effective || {};
  const provenance = b.provenance || {};
  const condBlock = Array.isArray(effective.ConditionalSettings) ? effective.ConditionalSettings : null;
  const baseEntries = Object.entries(effective)
    .filter(([k]) => k !== "ConditionalSettings")
    .sort(([a], [c]) => a.localeCompare(c));
  const deprecations = Array.isArray(b.deprecations) ? b.deprecations : [];
  const deprecatedKeys = new Set(deprecations.map((d) => d.key));
  panel.innerHTML = `
    <div class="settings-header">
      <h3><a href="${escapeHtml(repoUrl)}" target="_blank" rel="noopener">${escapeHtml(b.repo)}</a></h3>
      <button class="btn small" id="settings-close" title="Close panel">×</button>
    </div>
    ${renderDeprecationBanner(deprecations)}
    <div class="settings-section">
      <div class="settings-section-head">Effective base
        <span class="muted">(${baseEntries.length} key${baseEntries.length === 1 ? "" : "s"}, conditional settings not resolved)</span>
      </div>
      ${baseEntries.length === 0
        ? `<div class="settings-empty small">No settings defined at layers 1-5.</div>`
        : `<table class="settings-effective">${baseEntries.map(([k, v]) => `
            <tr${deprecatedKeys.has(k) ? ' class="deprecated"' : ""}>
              <td class="settings-key">${deprecatedKeys.has(k) ? `<span class="dep-mark" title="Deprecated setting">⚠</span> ` : ""}${escapeHtml(k)}</td>
              <td class="settings-value"><code>${escapeHtml(formatValue(v))}</code></td>
              <td class="settings-from muted" title="${escapeHtml(provenance[k] || "")}">${escapeHtml(shortSource(provenance[k]))}</td>
            </tr>`).join("")}</table>`}
      ${condBlock ? `<div class="settings-conditional">
        <div class="settings-conditional-head">ConditionalSettings (last-wins from layer ${escapeHtml(shortSource(provenance.ConditionalSettings))})</div>
        <pre class="settings-json">${escapeHtml(JSON.stringify(condBlock, null, 2))}</pre>
      </div>` : ""}
    </div>
    <div class="settings-section">
      <div class="settings-section-head">Layers (top = lowest precedence)</div>
      ${(b.layers || []).map((l) => renderLayer(l)).join("")}
    </div>
    ${renderSecretsAndVars(b.secretsAndVars)}`;
  const closeBtn = panel.querySelector("#settings-close");
  if (closeBtn) closeBtn.addEventListener("click", () => {
    state.selectedSettingsRepo = null;
    state.settingsBundle = null;
    renderHealth();
    renderSettingsPanel();
  });
  panel.querySelectorAll("details.settings-layer").forEach((det) => {
    det.addEventListener("toggle", () => {
      // Lazy-init: nothing extra, contents already rendered. Hook present
      // for future expansion (e.g. fetch raw on demand).
    });
  });
}

function renderLayer(l) {
  const badge = (() => {
    switch (l.status) {
      case "present": return `<span class="badge ok">present</span>`;
      case "absent": return `<span class="badge neutral">not set</span>`;
      case "forbidden": return `<span class="badge warn" title="${escapeHtml(l.message || "")}">no access</span>`;
      case "invalid": return `<span class="badge fail" title="${escapeHtml(l.message || "")}">invalid JSON</span>`;
      default: return `<span class="badge fail" title="${escapeHtml(l.message || "")}">error</span>`;
    }
  })();
  const keyCount = l.status === "present" && l.value && typeof l.value === "object"
    ? Object.keys(l.value).length : 0;
  const summary = `<summary class="settings-layer-head">
    <span class="settings-layer-order">${l.order}</span>
    <span class="settings-layer-label">${escapeHtml(l.label || l.source || "?")}</span>
    ${badge}
    ${l.status === "present" ? `<span class="muted small">${keyCount} key${keyCount === 1 ? "" : "s"}</span>` : ""}
  </summary>`;
  const body = l.status === "present"
    ? `<pre class="settings-json">${escapeHtml(JSON.stringify(l.value, null, 2))}</pre>`
    : l.message
    ? `<div class="settings-layer-msg muted small">${escapeHtml(l.message)}</div>`
    : "";
  return `<details class="settings-layer">${summary}${body}</details>`;
}

function formatValue(v) {
  if (v === null) return "null";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  // Short objects / arrays render inline; longer ones get truncated. Click the
  // layer below to see the full JSON.
  const s = JSON.stringify(v);
  return s.length > 80 ? s.slice(0, 77) + "…" : s;
}

function shortSource(src) {
  if (!src) return "";
  if (src.startsWith(".github/")) return src.slice(".github/".length);
  return src;
}

function renderDeprecationBanner(deps) {
  if (!deps || deps.length === 0) return "";
  // Deduplicate by key — one banner row per deprecated setting, with all the
  // locations where it was found listed underneath. This keeps the alert
  // compact when the same key appears in both a base layer and an effective
  // merge.
  const byKey = new Map();
  for (const d of deps) {
    if (!byKey.has(d.key)) byKey.set(d.key, { ...d, locations: [] });
    if (d.layerLabel) {
      byKey.get(d.key).locations.push(`${shortSource(d.layerLabel)}${d.scope && d.scope !== "top" ? ` → ${d.scope}` : ""}`);
    }
  }
  const docsBase = "https://github.com/microsoft/AL-Go/blob/main/DEPRECATIONS.md";
  const rows = [...byKey.values()].map((d) => {
    const locs = d.locations.length ? d.locations : ["(effective merge)"];
    return `<div class="dep-row">
      <div class="dep-row-head">
        <span class="badge warn">deprecated</span>
        <code class="dep-key">${escapeHtml(d.key)}</code>
        <span class="muted small">sunset ${escapeHtml(d.sunset)}</span>
        <a class="dep-doc" href="${escapeHtml(`${docsBase}#${d.anchor}`)}" target="_blank" rel="noopener">docs ↗</a>
      </div>
      <div class="dep-row-body muted small">
        Use <code>${escapeHtml(d.replacement)}</code> instead. Found in: ${escapeHtml(locs.join(", "))}.
      </div>
    </div>`;
  }).join("");
  return `<div class="settings-deprecations">
    <div class="settings-deprecations-head">⚠ ${byKey.size} deprecated setting${byKey.size === 1 ? "" : "s"} in use</div>
    ${rows}
  </div>`;
}

// ── Fleet-wide deprecations roll-up ────────────────────────────────────────
async function loadFleetDeprecations({ force = false } = {}) {
  if (!state.selectedOrg) {
    state.fleetDeps = null;
    renderFleetDeprecations();
    return;
  }
  // Cheap re-render path: keep showing the cached results if we have them and
  // the user isn't explicitly asking for a refresh.
  if (!force && state.fleetDeps && state.fleetDeps.org === state.selectedOrg) {
    renderFleetDeprecations();
    return;
  }
  state.fleetDepsLoading = true;
  renderFleetDeprecations();
  try {
    const url = `/api/fleet-deprecations?org=${encodeURIComponent(state.selectedOrg)}${force ? "&force=1" : ""}`;
    const data = await fetchJSON(url);
    state.fleetDeps = { ...data, org: state.selectedOrg };
  } catch (err) {
    state.fleetDeps = { org: state.selectedOrg, error: err.message };
  } finally {
    state.fleetDepsLoading = false;
    renderFleetDeprecations();
  }
}

function renderFleetDeprecations() {
  const box = $("#fleet-deps");
  if (!box) return;
  if (!state.selectedOrg) { box.hidden = true; box.innerHTML = ""; return; }
  box.hidden = false;
  if (state.fleetDepsLoading && !state.fleetDeps) {
    box.innerHTML = `<div class="fleet-deps-head"><span class="muted">Scanning fleet for deprecated settings…</span></div>`;
    return;
  }
  const d = state.fleetDeps;
  if (!d) { box.innerHTML = ""; return; }
  if (d.error) {
    box.innerHTML = `<div class="fleet-deps-head fail">Failed to scan: ${escapeHtml(d.error)} <button class="btn small" id="fleet-deps-retry">Retry</button></div>`;
    const btn = box.querySelector("#fleet-deps-retry");
    if (btn) btn.addEventListener("click", () => loadFleetDeprecations({ force: true }));
    return;
  }
  const keys = d.keys || [];
  const total = d.totalRepos || 0;
  const errCount = (d.errors && d.errors.length) || 0;
  const refreshBtn = `<button class="btn small" id="fleet-deps-refresh" title="Re-scan (clears 5-minute cache)">↻ Re-scan</button>`;
  const errPill = errCount > 0
    ? `<span class="badge warn" title="${escapeHtml((d.errors || []).map((e) => `${e.repo}: ${e.error}`).join("\n"))}">${errCount} repo${errCount === 1 ? "" : "s"} failed</span>`
    : "";
  if (keys.length === 0) {
    box.innerHTML = `<details class="fleet-deps-box ok">
      <summary class="fleet-deps-head">
        <span class="badge ok">✓ no deprecations</span>
        <span class="muted">${total} repo${total === 1 ? "" : "s"} scanned</span>
        ${errPill}
        ${refreshBtn}
      </summary>
    </details>`;
    box.querySelector("#fleet-deps-refresh").addEventListener("click", (e) => { e.preventDefault(); loadFleetDeprecations({ force: true }); });
    return;
  }
  const docsBase = "https://github.com/microsoft/AL-Go/blob/main/DEPRECATIONS.md";
  const affected = new Set();
  for (const k of keys) for (const r of k.repos) affected.add(r.repo);
  const rows = keys.map((k) => {
    const expanded = state.fleetDepsExpanded.has(k.key);
    const reposList = k.repos.map((r) =>
      `<li>
        <div class="fdep-repo-line">
          <button class="link" data-fdep-repo="${escapeHtml(r.repo)}">${escapeHtml(r.repo)}</button>
          <button class="btn xsmall" data-fdep-delegate-key="${escapeHtml(k.key)}" data-fdep-delegate-repo="${escapeHtml(r.repo)}" title="Ask the agent to migrate this repo in chat">🤖 Delegate</button>
        </div>
        <span class="muted small">${escapeHtml(r.scopes.join(" · "))}</span>
      </li>`).join("");
    return `<div class="fdep-row${expanded ? " expanded" : ""}">
      <button class="fdep-row-head" data-fdep-toggle="${escapeHtml(k.key)}" aria-expanded="${expanded ? "true" : "false"}">
        <span class="fdep-caret">${expanded ? "▾" : "▸"}</span>
        <code class="dep-key">${escapeHtml(k.key)}</code>
        <span class="badge warn">${k.repos.length} repo${k.repos.length === 1 ? "" : "s"}</span>
        <span class="muted small">sunset ${escapeHtml(k.sunset || "?")}</span>
        <a class="dep-doc" href="${escapeHtml(`${docsBase}#${k.anchor || ""}`)}" target="_blank" rel="noopener" onclick="event.stopPropagation()">docs ↗</a>
      </button>
      ${expanded ? `<div class="fdep-row-body">
        <div class="fdep-row-actions">
          <span class="muted small">Use <code>${escapeHtml(k.replacement || "")}</code> instead.</span>
          <button class="btn small" data-fdep-delegate-key="${escapeHtml(k.key)}" title="Ask the agent in chat to migrate all ${k.repos.length} repo${k.repos.length === 1 ? "" : "s"}">🤖 Delegate to agent (all ${k.repos.length})</button>
        </div>
        <ul class="fdep-repos">${reposList}</ul>
      </div>` : ""}
    </div>`;
  }).join("");
  box.innerHTML = `<details class="fleet-deps-box" open>
    <summary class="fleet-deps-head">
      <span class="badge warn">⚠ ${keys.length} deprecation${keys.length === 1 ? "" : "s"} across ${affected.size} repo${affected.size === 1 ? "" : "s"}</span>
      <span class="muted">${total} repo${total === 1 ? "" : "s"} scanned</span>
      ${errPill}
      ${refreshBtn}
    </summary>
    <div class="fleet-deps-list">${rows}</div>
  </details>`;
  box.querySelector("#fleet-deps-refresh").addEventListener("click", (e) => { e.preventDefault(); loadFleetDeprecations({ force: true }); });
  box.querySelectorAll("[data-fdep-toggle]").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      const key = btn.dataset.fdepToggle;
      if (state.fleetDepsExpanded.has(key)) state.fleetDepsExpanded.delete(key);
      else state.fleetDepsExpanded.add(key);
      renderFleetDeprecations();
    });
  });
  box.querySelectorAll("[data-fdep-repo]").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      const repo = btn.dataset.fdepRepo;
      loadRepoSettings(repo);
      const wrap = $(".settings-list-wrap");
      if (wrap) wrap.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });
  box.querySelectorAll("[data-fdep-delegate-key]").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.preventDefault();
      e.stopPropagation();
      const key = btn.dataset.fdepDelegateKey;
      const repo = btn.dataset.fdepDelegateRepo; // may be undefined → all repos
      const original = btn.innerHTML;
      btn.disabled = true;
      btn.innerHTML = "Delegating…";
      try {
        const body = { org: state.selectedOrg, key };
        if (repo) body.repos = [repo];
        const r = await fetchJSON("/api/fleet-deprecations/delegate", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
        });
        btn.innerHTML = `✓ Sent to chat (${r.repos.length})`;
        setTimeout(() => { btn.innerHTML = original; btn.disabled = false; }, 4000);
      } catch (err) {
        btn.innerHTML = `✗ ${err.message}`;
        setTimeout(() => { btn.innerHTML = original; btn.disabled = false; }, 4000);
      }
    });
  });
}

function renderSecretsAndVars(sv) {
  if (!sv) return "";
  const renderBlock = (label, kind, block, withValues) => {
    if (!block) return "";
    if (block.status === "forbidden") {
      return `<div class="sv-block">
        <div class="sv-head">${label} <span class="badge warn" title="${escapeHtml(block.message || "")}">no access</span></div>
        <div class="muted small">Requires repo admin to list ${kind}.</div>
      </div>`;
    }
    if (block.status === "error") {
      return `<div class="sv-block">
        <div class="sv-head">${label} <span class="badge fail" title="${escapeHtml(block.message || "")}">error</span></div>
      </div>`;
    }
    const items = block.items || [];
    if (items.length === 0) {
      return `<div class="sv-block">
        <div class="sv-head">${label} <span class="muted small">(none)</span></div>
      </div>`;
    }
    const rows = items
      .slice()
      .sort((a, b) => a.name.localeCompare(b.name))
      .map((it) => {
        const updated = it.updated_at || it.created_at || "";
        const when = updated ? new Date(updated).toISOString().slice(0, 10) : "";
        const valueCell = withValues
          ? `<td class="sv-value"><code>${escapeHtml(formatValue(it.value))}</code></td>`
          : "";
        return `<tr>
          <td class="sv-name"><code>${escapeHtml(it.name)}</code></td>
          ${valueCell}
          <td class="sv-when muted small">${escapeHtml(when)}</td>
        </tr>`;
      }).join("");
    const headCols = withValues
      ? `<th>Name</th><th>Value</th><th>Updated</th>`
      : `<th>Name</th><th>Updated</th>`;
    return `<div class="sv-block">
      <div class="sv-head">${label} <span class="muted small">(${items.length})</span></div>
      <table class="sv-table"><thead><tr>${headCols}</tr></thead><tbody>${rows}</tbody></table>
    </div>`;
  };
  return `<div class="settings-section">
    <div class="settings-section-head">Repository secrets &amp; variables
      <span class="muted small">(secret values are never returned by the API)</span>
    </div>
    ${renderBlock("Secrets", "secrets", sv.secrets, false)}
    ${renderBlock("Variables", "variables", sv.variables, true)}
  </div>`;
}

// All workflow runs across the fleet, sorted newest first.
// Sourced from the in-memory `state.allRuns` cache (seeded by fleet load,
// extended by /api/runs/load-more).
function flatRuns() {
  if (state.allRuns) return state.allRuns;
  const out = [];
  for (const repo of state.fleet) {
    for (const r of (repo.runs && repo.runs.all) || []) {
      if (!isAlGoWorkflow(r.workflowPath)) continue;
      out.push({ ...r, repo: repo.name, repoHtmlUrl: repo.htmlUrl });
    }
  }
  out.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  state.allRuns = out;
  state.runsHasMore = true;
  return out;
}

async function loadRunsWindow({ force = false } = {}) {
  if (!state.selectedOrg) return;
  if (state.runsWindowLoading) return;
  if (state.runsWindowLoaded && !force) return;
  state.runsWindowLoading = true;
  const status = $("#runs-status");
  status.hidden = false;
  status.textContent = `Loading runs from the last ${state.runsWindowDays} days…`;
  try {
    const data = await fetchJSON("/api/runs/window", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        org: state.selectedOrg,
        mode: state.discoveryMode,
        windowDays: state.runsWindowDays,
        force,
      }),
    });
    state.allRuns = (data.runs || []).filter((r) => isAlGoWorkflow(r.workflowPath));
    state.runsHasMore = !!data.hasMore;
    state.runsWindowLoaded = true;
    renderRuns();
  } catch (err) {
    status.textContent = "Could not load runs: " + err.message;
  } finally {
    state.runsWindowLoading = false;
  }
}

async function loadMoreRuns(opts = {}) {
  if (!state.selectedOrg) return 0;
  if (state.runsLoadingMore || !state.runsHasMore) return 0;
  state.runsLoadingMore = true;
  $("#runs-sentinel").hidden = false;
  $("#runs-end").hidden = true;
  let added = 0;
  try {
    const data = await fetchJSON("/api/runs/load-more", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ org: state.selectedOrg, mode: state.discoveryMode, repo: opts.repo || undefined }),
    });
    added = typeof data.added === "number" ? data.added : (data.runs.length - state.allRuns.length);
    state.allRuns = (data.runs || []).filter((r) => isAlGoWorkflow(r.workflowPath));
    state.runsHasMore = !!data.hasMore;
    renderRuns();
  } catch (err) {
    toast("Could not load more runs: " + err.message);
  } finally {
    state.runsLoadingMore = false;
    $("#runs-sentinel").hidden = true;
    $("#runs-end").hidden = state.runsHasMore;
  }
  return added;
}

// When the user narrows the Runs view with a filter, the first page rarely
// fills up (e.g. CI/CD is ~4% of runs in a PR-heavy repo). Keep pulling more
// pages within the same time window until we have enough matches, the data
// is exhausted, or we hit the cap. Targets the filtered repo when set.
const AUTO_LOAD_TARGET = 30;
const AUTO_LOAD_MAX_ATTEMPTS = 12;
let autoLoadAttempts = 0;
let autoLoadKey = "";
function filterKey() {
  const f = state.runsFilter;
  return `${f.workflow}|${f.conclusion}|${f.repo}|${f.text}`;
}
function maybeAutoLoadMore(filteredCount) {
  if (!state.selectedOrg || !state.runsHasMore || state.runsLoadingMore || state.runsWindowLoading) return;
  if (!state.runsWindowLoaded) return;
  if (filteredCount >= AUTO_LOAD_TARGET) return;
  const key = filterKey();
  if (key !== autoLoadKey) { autoLoadKey = key; autoLoadAttempts = 0; }
  if (autoLoadAttempts >= AUTO_LOAD_MAX_ATTEMPTS) return;
  autoLoadAttempts++;
  queueMicrotask(async () => {
    const added = await loadMoreRuns({ repo: state.runsFilter.repo });
    if (state.runsFilter.repo && added === 0) {
      autoLoadAttempts = AUTO_LOAD_MAX_ATTEMPTS;
    }
  });
}

const ICON = {
  ok: '<svg class="run-icon ok" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 16A8 8 0 1 0 8 0a8 8 0 0 0 0 16Zm3.78-9.72-4.5 4.5a.75.75 0 0 1-1.06 0l-2-2a.75.75 0 1 1 1.06-1.06l1.47 1.47 3.97-3.97a.75.75 0 1 1 1.06 1.06Z"/></svg>',
  fail: '<svg class="run-icon fail" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M2.343 13.657A8 8 0 1 1 13.657 2.343 8 8 0 0 1 2.343 13.657Zm8.014-9.014L8 7l-2.357-2.357-1.286 1.286L6.714 8.286l-2.357 2.357 1.286 1.286L8 9.572l2.357 2.357 1.286-1.286L9.286 8.286l2.357-2.357-1.286-1.286Z"/></svg>',
  cancelled: '<svg class="run-icon neutral" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M3.5 1A2.5 2.5 0 0 0 1 3.5v9A2.5 2.5 0 0 0 3.5 15h9a2.5 2.5 0 0 0 2.5-2.5v-9A2.5 2.5 0 0 0 12.5 1h-9ZM4 4h8v8H4V4Z"/></svg>',
  skipped: '<svg class="run-icon neutral" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0Zm-.75 4.75v4.5l4 2.25.75-1.3-3.25-1.85V4.75h-1.5Z"/></svg>',
  progress: '<span class="run-icon progress" aria-label="In progress"></span>',
  queued: '<svg class="run-icon warn" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
  neutral: '<svg class="run-icon neutral" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
};

function runIcon(run) {
  if (run.status && run.status !== "completed") {
    if (run.status === "queued") return ICON.queued;
    return ICON.progress;
  }
  if (run.conclusion === "success") return ICON.ok;
  if (run.conclusion === "failure" || run.conclusion === "timed_out") return ICON.fail;
  if (run.conclusion === "cancelled") return ICON.cancelled;
  if (run.conclusion === "skipped") return ICON.skipped;
  return ICON.neutral;
}

function populateRunFilters(runs) {
  // Workflow list = all AL-Go-shipped workflows plus any unknown names
  // appearing in the loaded runs. Both dropdowns are sorted alphabetically
  // with no run counts shown.
  const wfNames = new Set(AL_GO_WORKFLOW_NAMES);
  const repoNames = new Set();
  for (const r of runs) {
    if (r.workflow) wfNames.add(r.workflow);
    if (r.repo) repoNames.add(r.repo);
  }
  const workflows = [...wfNames].sort((a, b) => a.localeCompare(b));
  const repos = [...repoNames].sort((a, b) => a.localeCompare(b));
  const wfSel = $("#runs-workflow");
  const repoSel = $("#runs-repo");
  const currentWf = wfSel.value;
  const currentRepo = repoSel.value;
  wfSel.innerHTML = `<option value="">All workflows</option>` +
    workflows.map((w) => `<option value="${escapeHtml(w)}">${escapeHtml(w)}</option>`).join("");
  repoSel.innerHTML = `<option value="">All repositories</option>` +
    repos.map((r) => `<option value="${escapeHtml(r)}">${escapeHtml(r)}</option>`).join("");
  if (workflows.includes(currentWf)) wfSel.value = currentWf;
  if (repos.includes(currentRepo)) repoSel.value = currentRepo;
}

function renderRuns() {
  const list = $("#runs-list");
  const status = $("#runs-status");
  if (state.fleet.length === 0) {
    list.innerHTML = "";
    status.hidden = false;
    status.textContent = "Pick an org to begin.";
    $("#runs-shown").textContent = "0";
    return;
  }
  const allRuns = flatRuns();
  populateRunFilters(allRuns);
  const f = state.runsFilter;
  const text = (f.text || "").trim().toLowerCase();
  const filtered = allRuns.filter((r) => {
    if (f.workflow && r.workflow !== f.workflow) return false;
    if (f.repo && r.repo !== f.repo) return false;
    if (f.conclusion) {
      if (f.conclusion === "in_progress" || f.conclusion === "queued") {
        if (r.status !== f.conclusion) return false;
      } else if (r.conclusion !== f.conclusion) return false;
    }
    if (text) {
      const hay = `${r.workflow} ${r.repo} ${r.headBranch || ""} ${r.displayTitle || ""} ${(r.actor && r.actor.login) || ""}`.toLowerCase();
      if (!hay.includes(text)) return false;
    }
    return true;
  });
  status.hidden = filtered.length > 0;
  if (!status.hidden) {
    status.textContent = allRuns.length === 0
      ? "No workflow runs yet for this org."
      : "No runs match these filters.";
  }
  $("#runs-shown").textContent = String(filtered.length);
  const winEl = $("#runs-window");
  if (winEl) winEl.textContent = String(state.runsWindowDays);
  list.innerHTML = filtered.map((r) => {
    const icon = runIcon(r);
    const title = escapeHtml(r.displayTitle || r.workflow);
    const actor = r.actor
      ? `<a href="https://github.com/${escapeHtml(r.actor.login)}" target="_blank" rel="noopener" title="${escapeHtml(r.actor.login)}"><img class="avatar" src="${escapeHtml(r.actor.avatarUrl)}" alt="${escapeHtml(r.actor.login)}" /></a>`
      : "";
    const workflowFile = r.workflowPath ? r.workflowPath.split("/").pop() : null;
    const workflowUrl = workflowFile
      ? `${r.repoHtmlUrl}/actions/workflows/${encodeURIComponent(workflowFile)}`
      : `${r.repoHtmlUrl}/actions`;
    const branchUrl = r.headBranch ? `${r.repoHtmlUrl}/tree/${encodeURIComponent(r.headBranch)}` : null;
    const commitUrl = r.headSha ? `${r.repoHtmlUrl}/commit/${r.headSha}` : null;
    const shortSha = r.headSha ? r.headSha.substring(0, 7) : "";
    return `<li>
      ${icon}
      <div class="run-main">
        <a class="run-title" href="${r.htmlUrl}" target="_blank" rel="noopener">${title}</a>
        <div class="run-meta">
          <a class="pill" href="${workflowUrl}" target="_blank" rel="noopener" title="${escapeHtml(r.workflowPath || r.workflow)}">${escapeHtml(r.workflow)}</a>
          <a href="${r.repoHtmlUrl}" target="_blank" rel="noopener">${escapeHtml(r.repo)}</a>
          · <a href="${r.htmlUrl}" target="_blank" rel="noopener">#${escapeHtml(String(r.runNumber))}${r.attempt > 1 ? `·${r.attempt}` : ""}</a>
          ${branchUrl ? `· <a href="${branchUrl}" target="_blank" rel="noopener">${escapeHtml(r.headBranch)}</a>` : ""}
          ${commitUrl ? `· <a href="${commitUrl}" target="_blank" rel="noopener" title="${escapeHtml(r.headSha)}">${escapeHtml(shortSha)}</a>` : ""}
          · ${escapeHtml(r.event || "")}
        </div>
      </div>
      <div class="run-side">
        ${actor}
        ${commitUrl
          ? `<a class="muted-link" href="${commitUrl}" target="_blank" rel="noopener" title="${escapeHtml(r.updatedAt || "")}">${escapeHtml(fmtRelativeTime(r.updatedAt))}</a>`
          : `<span title="${escapeHtml(r.updatedAt || "")}">${escapeHtml(fmtRelativeTime(r.updatedAt))}</span>`}
      </div>
    </li>`;
  }).join("");
  $("#runs-end").hidden = state.runsHasMore || filtered.length === 0;
  maybeAutoLoadMore(filtered.length);
}

function updateSelectionUI() {
  const n = state.selection.size;
  $("#sel-count").textContent = String(n);
  $("#action-bar-count").textContent = String(n);
  const bar = $("#action-bar");
  bar.dataset.disabled = n === 0 ? "true" : "false";
  const allRows = state.fleet.length;
  $("#check-all").checked = allRows > 0 && n === allRows;
}

function appendLog(entry) {
  const div = document.createElement("div");
  div.className = `entry ${entry.ok ? "ok" : "fail"}`;
  div.textContent = entry.text;
  $("#bulk-log").appendChild(div);
  $("#bulk-log").scrollTop = $("#bulk-log").scrollHeight;
  // Auto-open the log details on first activity so users see progress.
  const wrap = $("#bulk-log-wrap");
  if (wrap && !wrap.open) wrap.open = true;
}

async function runBulk(endpoint, body, label) {
  if (state.selection.size === 0) {
    toast("Select some repos on the Overview tab first.");
    return;
  }
  appendLog({ ok: true, text: `→ ${label}: ${state.selection.size} repos…` });
  try {
    const data = await fetchJSON(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ org: state.selectedOrg, repos: [...state.selection], ...body }),
    });
    for (const r of data.results || []) {
      appendLog({ ok: r.ok, text: `  ${r.ok ? "✓" : "✗"} ${r.repo}${r.error ? ` — ${r.error}` : ""}${r.reason ? ` (${r.reason})` : ""}` });
    }
    toast(`${label} done`);
  } catch (err) {
    appendLog({ ok: false, text: `  ✗ ${err.message}` });
    toast(`${label} failed: ${err.message}`);
  }
}

function wireEvents() {
  $("#org-select").addEventListener("change", async (e) => {
    state.selectedOrg = e.target.value || null;
    state.selection.clear();
    state.fleetDeps = null;
    state.fleetDepsExpanded.clear();
    state.selectedSettingsRepo = null;
    state.settingsBundle = null;
    await fetchJSON("/api/preferences", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ selectedOrg: state.selectedOrg }),
    });
    if (state.selectedOrg) await loadFleet();
  });

  $("#refresh").addEventListener("click", () => {
    state.fleetDeps = null; // force re-scan on next visit to Settings tab
    loadFleet({ force: true });
  });

  $("#deep-scan").addEventListener("click", (e) => {
    const next = e.target.dataset.mode || "deep";
    state.discoveryMode = next;
    loadFleet({ force: true, mode: next });
  });

  $("#filter").addEventListener("input", (e) => {
    state.filter = e.target.value;
    renderFleet();
  });

  $("#check-all").addEventListener("change", (e) => {
    if (e.target.checked) {
      state.fleet.forEach((r) => state.selection.add(r.name));
    } else {
      state.selection.clear();
    }
    renderFleet();
  });

  $("#fleet-body").addEventListener("change", (e) => {
    if (!e.target.classList.contains("row-check")) return;
    const repo = e.target.dataset.repo;
    if (e.target.checked) state.selection.add(repo);
    else state.selection.delete(repo);
    e.target.closest("tr").classList.toggle("selected", e.target.checked);
    updateSelectionUI();
  });

  $("#fleet-body").addEventListener("click", async (e) => {
    const btn = e.target.closest(".badge-delegate");
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    if (btn.disabled) return;
    const original = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = "…";
    try {
      const body = {
        org: state.selectedOrg,
        repo: btn.dataset.delegateRepo,
        runId: btn.dataset.delegateRun,
        workflow: btn.dataset.delegateWorkflow,
        workflowPath: btn.dataset.delegateWorkflowPath,
        htmlUrl: btn.dataset.delegateHtmlUrl,
        headBranch: btn.dataset.delegateHeadBranch,
      };
      await fetchJSON("/api/runs/delegate-investigation", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      btn.innerHTML = "✓";
      btn.classList.add("done");
      setTimeout(() => { btn.innerHTML = original; btn.disabled = false; btn.classList.remove("done"); }, 4000);
    } catch (err) {
      btn.innerHTML = "✗";
      btn.title = err.message;
      setTimeout(() => { btn.innerHTML = original; btn.disabled = false; btn.title = "Delegate investigation to agent"; }, 4000);
    }
  });

  document.querySelector(".repo-table thead").addEventListener("click", (e) => {
    const th = e.target.closest("th.sortable");
    if (!th) return;
    const key = th.dataset.sortKey;
    if (state.sort.key === key) {
      state.sort.dir = state.sort.dir === "asc" ? "desc" : "asc";
    } else {
      state.sort.key = key;
      // Default to descending for numeric/date columns so the most-recent /
      // largest values land at the top, ascending for textual ones.
      state.sort.dir = (key === "pushedAt" || key === "openPRs" || key === "ci") ? "desc" : "asc";
    }
    renderFleet();
  });

  $$(".tab").forEach((t) => t.addEventListener("click", () => {
    $$(".tab").forEach((x) => x.classList.toggle("active", x === t));
    $$(".view").forEach((v) => v.classList.remove("active"));
    $(`#view-${t.dataset.view}`).classList.add("active");
    state.view = t.dataset.view;
    if (state.view === "runs") { renderRuns(); loadRunsWindow(); }
    if (state.view === "health") {
      renderHealth();
      renderSettingsPanel();
      loadFleetDeprecations();
    }
  }));

  const settingsList = $("#settings-repos");
  if (settingsList) {
    settingsList.addEventListener("click", (e) => {
      const row = e.target.closest("li.settings-repo");
      if (!row) return;
      const repo = row.dataset.repo;
      if (repo === state.selectedSettingsRepo) {
        // Click selected row again = close panel.
        state.selectedSettingsRepo = null;
        state.settingsBundle = null;
        renderHealth();
        renderSettingsPanel();
      } else {
        loadRepoSettings(repo);
      }
    });
  }
  const settingsFilter = $("#settings-filter");
  if (settingsFilter) {
    settingsFilter.addEventListener("input", (e) => {
      state.settingsFilter = e.target.value;
      renderHealth();
    });
  }

  for (const id of ["runs-workflow", "runs-conclusion", "runs-repo"]) {
    $("#" + id).addEventListener("change", (e) => {
      state.runsFilter[id.replace("runs-", "")] = e.target.value;
      renderRuns();
    });
  }
  $("#runs-filter").addEventListener("input", (e) => {
    state.runsFilter.text = e.target.value;
    renderRuns();
  });

  // Infinite scroll: when the sentinel (rendered after the runs list) enters
  // the viewport, page in another batch from the server. Threshold > 0 so it
  // fires slightly before the user actually hits the end.
  const sentinel = $("#runs-sentinel");
  if (sentinel && "IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting && state.view === "runs" && state.runsHasMore && !state.runsLoadingMore) {
          loadMoreRuns();
        }
      }
    }, { root: null, rootMargin: "200px", threshold: 0 });
    // We need the sentinel to be in the DOM but not hidden while observed.
    // Observe a separate always-present anchor sibling to the list instead.
    const anchor = document.createElement("div");
    anchor.id = "runs-anchor";
    anchor.style.height = "1px";
    sentinel.parentNode.insertBefore(anchor, sentinel);
    io.observe(anchor);
  }

  // Populate the "More ▾" workflow dropdown with all AL-Go workflows except
  // reusable callees (_*) and ones already wired to dedicated buttons.
  const workflowSelect = $("#custom-workflow");
  if (workflowSelect) {
    const skip = new Set(["UpdateGitHubGoSystemFiles.yaml"]);
    const options = AL_GO_WORKFLOWS
      .filter((w) => !w.file.startsWith("_") && !skip.has(w.file))
      .sort((a, b) => a.name.localeCompare(b.name));
    workflowSelect.innerHTML =
      '<option value="">Select a workflow…</option>' +
      options.map((w) => `<option value="${w.file}">${escapeHtml(w.name)}</option>`).join("");
  }

  $$('button[data-action]').forEach((b) => b.addEventListener("click", (e) => {
    if (b.closest('.action-bar') && b.closest('.action-bar').dataset.disabled === 'true') return;
    const action = b.dataset.action;
    if (action === "update-algo") runBulk("/api/bulk/update-algo", {}, "Update AL-Go System Files");
    else if (action === "rerun-failed") runBulk("/api/bulk/rerun-failed", {}, "Re-run failed");
    else if (action === "trigger-workflow") {
      const sel = $("#custom-workflow");
      const workflow = sel.value;
      if (!workflow) return toast("Pick a workflow");
      const label = sel.options[sel.selectedIndex]?.textContent || workflow;
      runBulk("/api/bulk/trigger", { workflow }, `Trigger ${label}`);
      // close the dropdown after submit
      const dd = b.closest('details');
      if (dd) dd.open = false;
    }
  }));

  const es = new EventSource("/events");
  es.addEventListener("fleet:progress", (e) => {
    const d = JSON.parse(e.data);
    $("#fleet-status").textContent = `Scanning ${d.org}… ${d.done}/${d.total}`;
  });
  es.addEventListener("bulk:progress", (e) => {
    const d = JSON.parse(e.data);
    appendLog({ ok: true, text: `  · ${d.repo} (${d.done}/${d.total})` });
  });
}

(async function init() {
  wireEvents();
  await loadOrgs();
})();
