// gh CLI wrapper. Bypasses stale GH_TOKEN env vars in favour of the
// keyring credential, which is the working auth source for most users.

import { spawn } from "node:child_process";

function quoteWin(arg) {
  // Wrap args containing shell metacharacters so cmd.exe doesn't interpret them.
  if (/[\s&|<>^"]/.test(arg)) {
    return `"${arg.replace(/"/g, '\\"')}"`;
  }
  return arg;
}

function runGh(args, { input, preferKeyring } = {}) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env };
    if (preferKeyring) {
      delete env.GH_TOKEN;
      delete env.GITHUB_TOKEN;
    }
    const isWin = process.platform === "win32";
    const finalArgs = isWin ? args.map(quoteWin) : args;
    const child = spawn("gh", finalArgs, {
      env,
      shell: isWin,
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (b) => (stdout += b.toString("utf8")));
    child.stderr.on("data", (b) => (stderr += b.toString("utf8")));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(stdout);
      else {
        const err = new Error(`gh ${args.join(" ")} failed (${code}): ${stderr.trim() || stdout.trim()}`);
        err.stdout = stdout;
        err.stderr = stderr;
        err.code = code;
        reject(err);
      }
    });
    if (input !== undefined) {
      child.stdin.write(input);
      child.stdin.end();
    }
  });
}

async function ghJson(args, opts) {
  try {
    const out = await runGh(args, opts);
    return out.trim() ? JSON.parse(out) : null;
  } catch (err) {
    if (/token.*invalid|Bad credentials|HTTP 401/i.test(err.message) && !(opts && opts.preferKeyring)) {
      const out = await runGh(args, { ...(opts || {}), preferKeyring: true });
      return out.trim() ? JSON.parse(out) : null;
    }
    throw err;
  }
}

export async function ghApi(path, { method = "GET", fields, paginate } = {}) {
  const args = ["api", path];
  if (method !== "GET") args.push("--method", method);
  if (paginate) args.push("--paginate", "--slurp");
  if (fields) {
    for (const [k, v] of Object.entries(fields)) {
      args.push("-f", `${k}=${v}`);
    }
  }
  return ghJson(args);
}

// Like ghApi but returns raw text (used for endpoints like job logs that
// return plain text instead of JSON). Returns null on 404/410/etc.
export async function ghApiRaw(path) {
  const args = ["api", path];
  try {
    return await runGh(args);
  } catch (e) {
    if (typeof e?.message === "string" && /HTTP 4\d\d/.test(e.message)) {
      try {
        return await runGh(args, { preferKeyring: true });
      } catch {
        return null;
      }
    }
    return null;
  }
}

// GraphQL via `gh api graphql`. Pass the query and variables as raw fields so
// `gh` sends them as JSON in the request body.
export async function ghGraphql(query, variables = {}) {
  // Collapse whitespace: on Windows we run via `shell: true` for PATH lookup
  // of gh.cmd, and embedded newlines/tabs in the argv get mangled by cmd.exe.
  // GraphQL is whitespace-insensitive so this is safe.
  const flat = query.replace(/\s+/g, " ").trim();
  const args = ["api", "graphql", "-f", `query=${flat}`];
  for (const [k, v] of Object.entries(variables)) {
    if (typeof v === "string") args.push("-F", `${k}=${v}`);
    else args.push("--raw-field", `${k}=${JSON.stringify(v)}`);
  }
  // gh exits non-zero when GraphQL returns an `errors` field, but the response
  // body usually still carries usable partial `data`. Capture both branches.
  let raw;
  try {
    raw = await runGh(args);
  } catch (err) {
    // gh exits non-zero when GraphQL returns `errors`, but the JSON body
    // (with partial `data`) is still on stdout. Recover from there.
    if (err.stdout && err.stdout.trim()) {
      try {
        const parsed = JSON.parse(err.stdout);
        if (parsed && (parsed.data !== undefined || parsed.errors)) return parsed.data || null;
      } catch { /* fall through */ }
    }
    if (/token.*invalid|Bad credentials|HTTP 401/i.test(err.message)) {
      raw = await runGh(args, { preferKeyring: true });
    } else {
      throw err;
    }
  }
  if (!raw || !raw.trim()) return null;
  const parsed = JSON.parse(raw);
  return parsed && parsed.data;
}

export { runGh };
