import base64
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone


REPO = "Aholstrup1-PersonalOrg/BugBash7"
WORKFLOW_UPDATE = "UpdateGitHubGoSystemFiles.yaml"
WORKFLOW_CICD = "CICD.yaml"
TEMPLATE_URL = "https://github.com/microsoft/AL-Go@aholstrup1/nuget-compiler-folder"
REPORT_FILE = "bugbash7-workspace-compilation-results.md"
MAX_WORKFLOW_SECONDS = 30 * 60
POLL_SECONDS = 20


SCENARIOS = [
    {
        "number": 1,
        "name": "Basic workspace compilation",
        "branch": "scenario-1",
        "settings": {"country": "us", "workspaceCompilation": {"enabled": True}},
        "expect": {
            "log_contains": ["Installing AL compiler", "Downloading dependencies"],
            "compile_step": "success",
        },
        "what_tested": (
            "Enabled workspaceCompilation with default options in .AL-Go/settings.json. "
            "This exercises the new NuGet-based compiler installation path together with "
            "workspace dependency download instead of the legacy compiler folder download. "
            "It is the primary happy-path validation for the new workspace compilation flow."
        ),
    },
    {
        "number": 2,
        "name": "Workspace compilation with parallelism",
        "branch": "scenario-2",
        "settings": {"country": "us", "workspaceCompilation": {"enabled": True, "parallelism": -1}},
        "expect": {
            "log_contains": ["Installing AL compiler"],
            "compile_step": "success",
        },
        "what_tested": (
            "Enabled workspaceCompilation and set parallelism to -1 in .AL-Go/settings.json. "
            "This exercises the workspace compilation code path while also passing the parallelism "
            "setting through the compile step. It verifies the new implementation remains stable "
            "when concurrency-related configuration is present, even for a single app."
        ),
    },
    {
        "number": 3,
        "name": "Workspace compilation with compilerVersion override",
        "branch": "scenario-3",
        "settings": {"country": "us", "workspaceCompilation": {"enabled": True, "compilerVersion": "26.*"}},
        "expect": {
            "log_contains": ["Installing AL compiler"],
            "compile_step": "success",
            "compiler_version_regex": r"Installing AL compiler.*26\..*|Installing AL compiler.*26\*",
        },
        "what_tested": (
            "Enabled workspaceCompilation and overrode compilerVersion to 26.* in .AL-Go/settings.json. "
            "This specifically exercises the version resolution logic that should prefer the explicit "
            "compilerVersion setting over inferred artifact versions. It matters because the new NuGet "
            "installation path must honor caller-selected compiler major versions."
        ),
    },
    {
        "number": 4,
        "name": "Workspace compilation disabled regression",
        "branch": "scenario-4",
        "settings": {"country": "us", "workspaceCompilation": {"enabled": False}},
        "expect": {
            "compile_step": "skipped",
            "build_step": "success",
        },
        "what_tested": (
            "Explicitly disabled workspaceCompilation in .AL-Go/settings.json. "
            "This is a regression test for the legacy container-based build path and checks that the "
            "Compile Apps step stays skipped while the standard Build/RunPipeline flow still performs compilation. "
            "It confirms existing repositories are not broken by the new feature."
        ),
    },
    {
        "number": 5,
        "name": "Workspace compilation with includeAssemblyProbing",
        "branch": "scenario-5",
        "settings": {"country": "us", "workspaceCompilation": {"enabled": True, "includeAssemblyProbing": True}},
        "expect": {
            "log_contains": [
                "Installing AL compiler",
                "Downloading assembly probing DLLs from platform artifacts",
            ],
            "compile_step": "success",
        },
        "what_tested": (
            "Enabled workspaceCompilation and includeAssemblyProbing in .AL-Go/settings.json. "
            "This exercises the optional code path that still downloads platform artifacts, but only "
            "for assembly probing DLLs rather than the full compiler folder. It validates the targeted "
            "DLL download behavior introduced by the refactor."
        ),
    },
]


class CommandError(Exception):
    pass


def run(args, check=True, capture=True):
    proc = subprocess.run(
        args,
        text=True,
        capture_output=capture,
        encoding="utf-8",
        errors="replace",
    )
    if check and proc.returncode != 0:
        raise CommandError(
            f"Command failed ({proc.returncode}): {' '.join(args)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc


def gh(*args, check=True):
    return run(["gh", *args], check=check).stdout.strip()


def gh_json(*args, check=True):
    out = gh(*args, check=check)
    return json.loads(out) if out else None


def progress(message):
    print(message, flush=True)


def iso_to_dt(value):
    if not value:
        return None
    value = value.replace("Z", "+00:00")
    return datetime.fromisoformat(value)


def current_unix():
    return time.time()


def get_latest_run(workflow, branch=None):
    args = ["run", "list", "--workflow", workflow, "--repo", REPO, "--limit", "1", "--json", "status,conclusion,databaseId,createdAt,headBranch"]
    if branch:
        args.extend(["--branch", branch])
    runs = gh_json(*args)
    if not runs:
        return None
    return runs[0]


def trigger_workflow_and_get_run(workflow, fields=None, ref=None, branch=None, description=None):
    before = get_latest_run(workflow, branch=branch)
    cmd = ["workflow", "run", workflow, "--repo", REPO]
    if ref:
        cmd.extend(["--ref", ref])
    if fields:
        for key, value in fields.items():
            cmd.extend(["-f", f"{key}={value}"])
    gh(*cmd)
    started = current_unix()
    while current_unix() - started < 180:
        run_info = get_latest_run(workflow, branch=branch)
        if run_info and (before is None or run_info["databaseId"] != before["databaseId"]):
            return run_info["databaseId"]
        time.sleep(5)
    raise RuntimeError(f"Timed out waiting for {description or workflow} run to appear")


def wait_for_run(run_id, label):
    started = current_unix()
    while True:
        info = gh_json("run", "view", str(run_id), "--repo", REPO, "--json", "status,conclusion,createdAt,updatedAt,headBranch")
        status = info["status"]
        conclusion = info.get("conclusion")
        if status == "completed":
            return info
        if current_unix() - started > MAX_WORKFLOW_SECONDS:
            return {
                "status": "completed",
                "conclusion": "timed_out",
                "headBranch": info.get("headBranch"),
                "createdAt": info.get("createdAt"),
            }
        progress(f"⏳ {label}: status={status}")
        time.sleep(POLL_SECONDS)


def cancel_latest_incomplete_cicd():
    run_id = gh(
        "run",
        "list",
        "--workflow",
        WORKFLOW_CICD,
        "--repo",
        REPO,
        "--limit",
        "1",
        "--json",
        "databaseId,status",
        "--jq",
        '.[] | select(.status != "completed") | .databaseId',
        check=True,
    ).strip()
    if run_id:
        gh("run", "cancel", run_id, "--repo", REPO)
        return run_id
    return None


def verify_repo_structure():
    tree = gh_json("api", f"repos/{REPO}/git/trees/main?recursive=1")
    paths = sorted(item["path"] for item in tree["tree"] if item["path"].endswith("app.json"))
    return paths


def ensure_branch(branch, sha):
    ref_path = f"repos/{REPO}/git/refs/heads/{branch}"
    result = run(["gh", "api", ref_path], check=False)
    if result.returncode == 0:
        gh("api", ref_path, "--method", "PATCH", "-f", f"sha={sha}", "-F", "force=true")
    else:
        gh("api", f"repos/{REPO}/git/refs", "-f", f"ref=refs/heads/{branch}", "-f", f"sha={sha}")


def get_file_info(path, ref):
    return gh_json("api", f"repos/{REPO}/contents/{path}?ref={ref}")


def update_file(path, branch, message, content_text, sha):
    encoded = base64.b64encode(content_text.encode("utf-8")).decode("ascii")
    gh(
        "api",
        f"repos/{REPO}/contents/{path}",
        "--method",
        "PUT",
        "-f",
        f"message={message}",
        "-f",
        f"branch={branch}",
        "-f",
        f"content={encoded}",
        "-f",
        f"sha={sha}",
    )


def get_jobs(run_id):
    data = gh_json("run", "view", str(run_id), "--repo", REPO, "--json", "jobs")
    return data.get("jobs", [])


def get_log(run_id, failed_only=False):
    args = ["run", "view", str(run_id), "--repo", REPO]
    args.append("--log-failed" if failed_only else "--log")
    return gh(*args)


INFRA_PATTERNS = [
    r"docker.*(error|failed|daemon)",
    r"runner.*shutdown",
    r"service unavailable",
    r"502 bad gateway",
    r"connection (timed out|reset)",
    r"network.*timed out",
    r"TLS handshake timeout",
    r"failed to connect",
]


def is_infra_failure(text):
    lower = text.lower()
    return any(re.search(pattern, lower) for pattern in INFRA_PATTERNS)


def excerpt(text, needle=None, regex=None, lines=10):
    split = text.splitlines()
    match_index = None
    if needle:
        for idx, line in enumerate(split):
            if needle.lower() in line.lower():
                match_index = idx
                break
    elif regex:
        cre = re.compile(regex, re.IGNORECASE)
        for idx, line in enumerate(split):
            if cre.search(line):
                match_index = idx
                break
    if match_index is None:
        return None
    start = max(0, match_index - 2)
    end = min(len(split), match_index + lines)
    return "\n".join(split[start:end]).strip()


def find_step_status(jobs, step_name):
    statuses = []
    for job in jobs:
        for step in job.get("steps", []):
            if step.get("name") == step_name:
                statuses.append(step.get("conclusion") or step.get("status"))
    if not statuses:
        return None
    if "failure" in statuses:
        return "failure"
    if "success" in statuses:
        return "success"
    if "skipped" in statuses:
        return "skipped"
    return statuses[0]


def validate_scenario(scenario, run_id):
    info = gh_json("run", "view", str(run_id), "--repo", REPO, "--json", "status,conclusion")
    jobs = get_jobs(run_id)
    log = get_log(run_id, failed_only=False)
    passed = info["conclusion"] == "success"
    reasons = []
    note = None

    expected_compile = scenario["expect"].get("compile_step")
    if expected_compile:
        compile_status = find_step_status(jobs, "Compile Apps")
        if compile_status != expected_compile:
            passed = False
            reasons.append(f'Expected "Compile Apps" step to be {expected_compile}, got {compile_status or "missing"}')

    expected_build = scenario["expect"].get("build_step")
    if expected_build:
        build_status = find_step_status(jobs, "Build")
        if build_status != expected_build:
            passed = False
            reasons.append(f'Expected "Build" step to be {expected_build}, got {build_status or "missing"}')

    for needle in scenario["expect"].get("log_contains", []):
        if needle.lower() not in log.lower():
            passed = False
            reasons.append(f'Missing log entry: "{needle}"')

    version_regex = scenario["expect"].get("compiler_version_regex")
    if version_regex and not re.search(version_regex, log, re.IGNORECASE):
        passed = False
        reasons.append("Did not find expected compiler version 26.x in install log")

    error_text = None
    if not passed:
        failed_log = get_log(run_id, failed_only=True)
        error_text = failed_log.strip() or "\n".join(reasons)
        if not error_text.strip():
            error_text = "\n".join(reasons)
    return {
        "status": "PASS" if passed else "FAIL",
        "run_id": run_id,
        "url": f"https://github.com/{REPO}/actions/runs/{run_id}",
        "error": error_text,
        "reasons": reasons,
        "note": note,
        "log": log,
        "jobs": jobs,
    }


def format_error(result):
    if result["status"] == "PASS":
        return ""
    if result["error"]:
        text = result["error"].strip()
        if len(text) > 1800:
            text = text[:1800].rstrip() + "\n...[truncated]"
        return text
    return "; ".join(result.get("reasons", []))


def main():
    results = {}

    progress("Starting workspace compilation scenarios for Aholstrup1-PersonalOrg/BugBash7")

    update_run = trigger_workflow_and_get_run(
        WORKFLOW_UPDATE,
        fields={"templateUrl": TEMPLATE_URL, "downloadLatest": "true", "directCommit": "true"},
        description="Update AL-Go System Files",
    )
    update_result = wait_for_run(update_run, "Update AL-Go System Files")
    if update_result["conclusion"] != "success":
        raise RuntimeError(f"Update AL-Go System Files failed (run {update_run}) with conclusion {update_result['conclusion']}")
    progress("✅ Setup: Update AL-Go System Files completed successfully")

    cancelled = cancel_latest_incomplete_cicd()
    if cancelled:
        progress(f"✅ Setup: Cancelled triggered CICD run {cancelled}")

    app_paths = verify_repo_structure()
    if app_paths != ["TestApp/app.json"]:
        raise RuntimeError(f"Unexpected app.json paths after setup: {app_paths}")
    progress("✅ Repo structure verified: TestApp/app.json")

    main_sha = gh("api", f"repos/{REPO}/git/refs/heads/main", "--jq", ".object.sha")
    settings_info = get_file_info(".AL-Go/settings.json", "main")
    settings_sha = settings_info["sha"]

    for scenario in SCENARIOS:
        ensure_branch(scenario["branch"], main_sha)
        payload = json.dumps(scenario["settings"], separators=(",", ":"))
        update_file(
            ".AL-Go/settings.json",
            scenario["branch"],
            f"Scenario {scenario['number']} setup",
            payload,
            settings_sha,
        )
    progress("✅ Branches created: scenario-1, scenario-2, scenario-3, scenario-4, scenario-5")

    run_ids = {}
    for scenario in SCENARIOS:
        run_id = trigger_workflow_and_get_run(
            WORKFLOW_CICD,
            ref=scenario["branch"],
            branch=scenario["branch"],
            description=f"CICD {scenario['branch']}",
        )
        run_ids[scenario["branch"]] = run_id
    progress("✅ All CI/CD runs triggered")

    pending = {scenario["branch"]: dict(scenario) for scenario in SCENARIOS}
    rerun_used = set()
    start_times = {branch: current_unix() for branch in pending}

    while pending:
        for branch in list(pending.keys()):
            run_id = run_ids[branch]
            info = gh_json("run", "view", str(run_id), "--repo", REPO, "--json", "status,conclusion")
            if info["status"] != "completed":
                if current_unix() - start_times[branch] > MAX_WORKFLOW_SECONDS:
                    scenario = pending.pop(branch)
                    results[branch] = {
                        "status": "FAIL",
                        "run_id": run_id,
                        "url": f"https://github.com/{REPO}/actions/runs/{run_id}",
                        "error": "Workflow exceeded 30 minutes and was treated as TIMED OUT.",
                        "note": None,
                    }
                    progress(f"❌ Scenario {scenario['number']}: FAIL - TIMED OUT")
                continue

            scenario = pending[branch]
            if info["conclusion"] != "success":
                failed_log = get_log(run_id, failed_only=True)
                if branch not in rerun_used and is_infra_failure(failed_log):
                    gh("run", "rerun", str(run_id), "--repo", REPO)
                    rerun_used.add(branch)
                    start_times[branch] = current_unix()
                    new_run = wait_for_run(run_id, f"Rerun request for {branch}")
                    # GitHub rerun keeps the same run id; just continue polling.
                    progress(f"ℹ️ Scenario {scenario['number']}: rerun requested after infra failure")
                    continue

            validation = validate_scenario(scenario, run_id)
            if branch in rerun_used and validation["status"] == "PASS":
                validation["note"] = "Rerun after infrastructure failure"
            results[branch] = validation
            pending.pop(branch)
            symbol = "✅" if validation["status"] == "PASS" else "❌"
            progress(f"{symbol} Scenario {scenario['number']}: {validation['status']} - {scenario['name']}")

        if pending:
            time.sleep(POLL_SECONDS)

    ordered = [results[s["branch"]] | {"scenario": s} for s in SCENARIOS]
    passed = sum(1 for item in ordered if item["status"] == "PASS")
    failed = len(ordered) - passed

    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        f.write("# BugBash7 Workspace Compilation Test Results\n\n")
        f.write(f"- Repository: {REPO}\n")
        f.write(f"- Template URL: {TEMPLATE_URL}\n")
        f.write(f"- Passed: {passed}\n")
        f.write(f"- Failed: {failed}\n\n")
        for item in ordered:
            scenario = item["scenario"]
            f.write(f"## Scenario {scenario['number']}: {scenario['name']}\n")
            f.write(f"- Status: {item['status']}\n")
            f.write(f"- Branch: {scenario['branch']}\n")
            f.write(f"- Run: {item['run_id']}\n")
            f.write(f"- URL: {item['url']}\n")
            f.write(f"- What was tested: {scenario['what_tested']}\n")
            if item["status"] != "PASS":
                f.write(f"- Error: {format_error(item)}\n")
            if item.get("note"):
                f.write(f"- Note: {item['note']}\n")
            f.write("\n")

    progress(f"✅ Report written: {REPORT_FILE}")
    print("FINAL_REPORT_START", flush=True)
    for item in ordered:
        scenario = item["scenario"]
        print(f"### Scenario {scenario['number']}: {scenario['name']}")
        print(f"- Status: {item['status']}")
        print(f"- Branch: {scenario['branch']}")
        print(f"- Run: {item['run_id']}")
        print(f"- URL: {item['url']}")
        print(f"- What was tested: {scenario['what_tested']}")
        if item["status"] != "PASS":
            print(f"- Error (if failed): {format_error(item)}")
        else:
            print("- Error (if failed):")
        if item.get("note"):
            print(f"- Note (if applicable): {item['note']}")
        print()
    print(f"SUMMARY: {passed} passed, {failed} failed", flush=True)
    print("FINAL_REPORT_END", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FATAL: {exc}", file=sys.stderr, flush=True)
        raise
