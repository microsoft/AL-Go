// Loopback HTTP server. Serves the iframe and the JSON API + SSE stream.

import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8",
};

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  res.end(body);
}

async function serveStatic(res, filePath) {
  try {
    const data = await fs.readFile(filePath);
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      "content-type": MIME[ext] || "application/octet-stream",
      "cache-control": "no-cache",
    });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
}

async function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      try { resolve(raw ? JSON.parse(raw) : {}); }
      catch (e) { reject(e); }
    });
    req.on("error", reject);
  });
}

function createHub() {
  const clients = new Set();
  return {
    attach(res) {
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "connection": "keep-alive",
      });
      res.write(`: connected\n\n`);
      clients.add(res);
      res.on("close", () => clients.delete(res));
    },
    publish(event, data) {
      const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
      for (const c of clients) {
        try { c.write(payload); } catch { /* ignore */ }
      }
    },
  };
}

export async function startServer({ webRoot, handlers }) {
  const hub = createHub();
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    try {
      if (req.method === "GET" && url.pathname === "/events") return hub.attach(res);
      if (req.method === "GET" && url.pathname === "/api/orgs")
        return sendJson(res, 200, await handlers.listOrgs());
      if (req.method === "GET" && url.pathname === "/api/fleet") {
        const org = url.searchParams.get("org");
        const force = url.searchParams.get("force") === "1";
        const mode = url.searchParams.get("mode") || undefined;
        if (!org) return sendJson(res, 400, { error: "missing org" });
        return sendJson(res, 200, await handlers.getFleet(org, { force, mode, hub }));
      }
      if (req.method === "GET" && url.pathname === "/api/preferences")
        return sendJson(res, 200, await handlers.getPreferences());
      if (req.method === "POST" && url.pathname === "/api/preferences") {
        const body = await readBody(req);
        return sendJson(res, 200, await handlers.savePreferences(body));
      }
      if (req.method === "POST" && url.pathname === "/api/runs/load-more") {
        const body = await readBody(req);
        if (!body.org) return sendJson(res, 400, { error: "missing org" });
        return sendJson(res, 200, await handlers.loadMoreRuns(body.org, body.mode, hub, { repo: body.repo }));
      }
      if (req.method === "POST" && url.pathname === "/api/runs/window") {
        const body = await readBody(req);
        if (!body.org) return sendJson(res, 400, { error: "missing org" });
        return sendJson(res, 200, await handlers.loadRunsWindow(body.org, body.mode, hub, { windowDays: body.windowDays, force: !!body.force }));
      }
      if (req.method === "GET" && url.pathname === "/api/runs/detail") {
        const org = url.searchParams.get("org");
        const repo = url.searchParams.get("repo");
        const runId = url.searchParams.get("runId");
        if (!org || !repo || !runId) return sendJson(res, 400, { error: "org, repo, runId required" });
        try {
          return sendJson(res, 200, await handlers.getRunDetail(org, repo, runId));
        } catch (e) {
          return sendJson(res, 404, { error: e.message });
        }
      }
      if (req.method === "GET" && url.pathname === "/api/runs/job-log") {
        const org = url.searchParams.get("org");
        const repo = url.searchParams.get("repo");
        const jobId = url.searchParams.get("jobId");
        const lines = Number(url.searchParams.get("lines") || "80") || 80;
        if (!org || !repo || !jobId) return sendJson(res, 400, { error: "org, repo, jobId required" });
        const text = await handlers.getJobLogTail(org, repo, jobId, lines);
        return sendJson(res, 200, { log: text, lines });
      }
      if (req.method === "GET" && url.pathname === "/api/repo-settings") {
        const org = url.searchParams.get("org");
        const repo = url.searchParams.get("repo");
        if (!org || !repo) return sendJson(res, 400, { error: "org and repo required" });
        return sendJson(res, 200, await handlers.getRepoSettingsBundle(org, repo));
      }
      if (req.method === "GET" && url.pathname === "/api/fleet-deprecations") {
        const org = url.searchParams.get("org");
        const force = url.searchParams.get("force") === "1";
        if (!org) return sendJson(res, 400, { error: "missing org" });
        return sendJson(res, 200, await handlers.getFleetDeprecations(org, { force, hub }));
      }
      if (req.method === "POST" && url.pathname === "/api/runs/delegate-investigation") {
        const body = await readBody(req);
        if (!body.org || !body.repo || !body.runId) return sendJson(res, 400, { error: "org, repo, runId required" });
        return sendJson(res, 200, await handlers.delegateRunInvestigation(body));
      }
      if (req.method === "POST" && url.pathname === "/api/fleet-deprecations/delegate") {
        const body = await readBody(req);
        if (!body.org || !body.key) return sendJson(res, 400, { error: "org and key required" });
        return sendJson(res, 200, await handlers.delegateDeprecation(body));
      }
      if (req.method === "POST" && url.pathname === "/api/bulk/update-algo") {
        const body = await readBody(req);
        return sendJson(res, 200, await handlers.bulkUpdateAlgoSystemFiles(body, hub));
      }
      if (req.method === "POST" && url.pathname === "/api/bulk/rerun-failed") {
        const body = await readBody(req);
        return sendJson(res, 200, await handlers.bulkRerunFailed(body, hub));
      }
      if (req.method === "POST" && url.pathname === "/api/bulk/trigger") {
        const body = await readBody(req);
        return sendJson(res, 200, await handlers.bulkTriggerWorkflow(body, hub));
      }
      if (req.method === "GET") {
        let rel = url.pathname === "/" ? "/index.html" : url.pathname;
        rel = rel.replace(/^\/+/, "");
        const full = path.join(webRoot, rel);
        if (!full.startsWith(webRoot)) {
          res.writeHead(403); return res.end("forbidden");
        }
        return serveStatic(res, full);
      }
      res.writeHead(404); res.end("not found");
    } catch (err) {
      sendJson(res, 500, { error: err.message });
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  return { server, port, hub };
}
