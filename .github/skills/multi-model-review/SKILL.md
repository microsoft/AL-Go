______________________________________________________________________

## name: multi-model-review description: > Multi-model code review skill. Launches 3 parallel code reviews using different AI models (Claude Opus, GPT, Gemini), then synthesizes findings using weighted consensus. Use this skill when asked to review a PR, review code changes, or perform a multi-model review. Trigger phrases: "multi-model review", "review this PR with multiple models", "consensus review", "triple review", "/multi-model-review".

# Multi-Model Code Review

You are orchestrating a multi-model code review. Your job is to launch 3 independent code reviews
in parallel using different AI models, collect their findings, and synthesize a single
weighted-consensus assessment.

## Step 0: Prerequisites check

Before starting, verify all prerequisites are met. If any check fails, stop and tell the user
what is missing.

1. **`gh` CLI** — Run `gh auth status` to confirm the GitHub CLI is installed and authenticated.
   Needed for creating pending reviews in Step 6.
1. **Python** — Run `python --version` (or `python3 --version`) to confirm Python is available.
   Needed for building JSON payloads (avoids PowerShell Unicode/encoding issues).
1. **GitHub MCP server** — Verify the `github-mcp-server-pull_request_read` tool is available
   (try a lightweight call like listing PR details). Subagents depend on this for reading diffs
   and file contents.
1. **Model access** — The skill requires three models: `claude-opus-4.6`, `gpt-5.2-codex`, and
   `gemini-3-pro-preview`. These are passed via the `model` parameter to the `task` tool. If a
   model is unavailable, the skill can still run with 2 models but must note reduced consensus
   confidence in the output.

If all checks pass, proceed silently. Only report issues.

## CRITICAL RULES

1. **Do NOT submit reviews or post standalone comments to the PR.** You may create a **pending
   (draft) review** with inline comments (see Step 6), but you must NEVER submit it. The pending
   review is only visible to the authenticated user. The user decides whether to submit, edit, or
   discard it. Do NOT use `create_pull_request_thread`, `reply_to_comment`, `update_pull_request`,
   or any GitHub MCP write operations on the PR.

1. **Be pragmatic.** If the code looks good, say so. Do not force feedback, manufacture nitpicks,
   or comment on style/formatting. Only surface issues that genuinely matter: bugs, security
   vulnerabilities, logic errors, missing error handling, or significant design concerns.

## Step 1: Identify the changes to review

Determine what code changes to review based on the user's input:

- A GitHub PR URL (e.g. `https://github.com/owner/repo/pull/123`) — parse the owner, repo, and PR number
- A PR number — assume the current repository (microsoft/AL-Go)
- "local changes", "staged changes", "branch diff" — for local work

Note what the target is (PR number + repo, or local diff type). You'll pass this to the subagents
so they know where to look. Do NOT fetch the diff yourself — the subagents will do their own research.

**Remember: NEVER write anything to the PR. Read-only.**

## Step 2: Summarize the changes

Write a brief summary of the changes (3-5 sentences) to give the subagents context about intent.

If reviewing a PR, read the PR description (`pull_request_read` with `method: "get"`) and the
file list (`method: "get_files"`) to understand the scope and the author's stated intent.

Keep the summary factual and concise. Save it — you will pass it to each subagent and include
it in the final output.

## Step 3: Launch 3 parallel code reviews

Use the `task` tool to launch 3 review subagents in **background** mode, each with a different
model. All 3 must run in parallel (launch all in a single response).

For each subagent, use `agent_type: "general-purpose"`. General-purpose subagents have access to
all CLI tools (grep, glob, view, shell, GitHub MCP read tools). The key is to tell each subagent
to actively USE these tools to explore the codebase — not just passively read a pasted diff.

**Before building the prompts**, read the companion review criteria files in this skill's directory:

- `Style.md` — PowerShell conventions, naming, cross-file consistency, settings system, PR quality
- `Security.md` — secrets handling, script injection, template safety, workflow security
- `TestCoverage.md` — what needs tests, test quality, culture/locale testing, edge cases
- `ErrorHandling.md` — error handling patterns, logging, observability, telemetry

### Subagent prompt template

```
You are performing a thorough, senior-level code review. You have access to all CLI tools (view,
grep, glob, shell) and GitHub MCP read tools.

IMPORTANT INSTRUCTIONS ON THOROUGHNESS:
- You MUST actively use tools to explore the codebase. Do NOT skip this step.
- Read EVERY changed file in full — not just the diff hunks. You need surrounding context.
- For each changed file, grep for related usages across the codebase to check for side effects.
- Check if related files need matching changes (e.g., template mirroring, settings schema, tests).
- Trace function calls: if a function signature changed, find all callers.
- Do NOT rush. A thorough review takes time. It is better to be slow and correct than fast and shallow.
- You must demonstrate your work by listing every file you read and what you checked in it.

IMPORTANT: Do NOT post comments, reviews, or any content to the PR. Do NOT use any GitHub MCP
write tools. Your job is to analyze and report findings — nothing else.

CLEANUP: If you download files, clone repos, or create any temporary files/directories during your
review, delete them when you are done. Leave the workspace exactly as you found it.

CHANGE SUMMARY:
[Insert the summary from Step 2 here]

WHAT TO REVIEW:
[If reviewing a PR, specify: "Review PR #N in the microsoft/AL-Go repository. Use
pull_request_read with method get_diff to get the diff, and method get_files to see changed
files. Then use the view tool to read the full contents of each changed file to understand
the surrounding context. Use grep to find callers/usages of any changed functions."]
[If reviewing local changes, specify: "Run git diff to see the changes, then read each changed
file with the view tool. Use grep to find callers/usages of any changed functions."]

AL-GO REVIEW CRITERIA:
[Insert the contents of Style.md, Security.md, and TestCoverage.md here]

REVIEW PROCESS:
1. Get the diff and list of changed files
2. For each changed file, read the FULL file (not just the diff) to understand context
3. For any new or changed functions, grep the codebase for all callers to check for breaking changes
4. Check if related files need changes too (e.g. template mirroring, settings schema)
5. Evaluate against the AL-Go review criteria above
6. Focus ONLY on issues that genuinely matter — bugs, security vulnerabilities, logic errors,
   missing error handling, performance problems, or significant design concerns
7. Do NOT comment on style, formatting, or trivial matters
8. If the code looks good, say so — but show your analysis work

Format your response as:

FILES REVIEWED:
[List each file you examined and a 1-sentence note on what you checked]

VERDICT: [APPROVE | REQUEST_CHANGES | COMMENT]

FINDINGS:
For each issue found, output:
- **Severity**: [critical | high | medium | low]
- **Category**: [bug | security | logic | performance | error-handling | al-go-convention | test-coverage | other]
- **What?** [Clear description of the issue — what is wrong and why it matters]
- **Where?** [filename:line_number] (e.g. `Actions/RunPipeline/RunPipeline.ps1:202`) then a code snippet (5-10 lines max) showing the actual problematic code. The line number is REQUIRED — do not omit it.
- **Recommendation:**
  [What should be done to fix it. Include a code snippet showing the suggested fix if applicable]

If no issues found, output:
VERDICT: APPROVE
FINDINGS: No issues found. The code looks good.
```

### Randomized focus areas

To ensure different reviewers running this skill on the same PR get varied feedback, each run
randomly assigns a **primary focus area** to each model. All models still review all areas, but
each one goes extra deep on its assigned area.

The 4 focus areas are: **Security**, **Style**, **TestCoverage**, **ErrorHandling**.

**How to randomize:** Before launching subagents, randomly assign one focus area to each of the
3 models. Each focus area may only be assigned once per run (3 models, 4 areas — one area is
unassigned each run, which is fine since all models still cover all areas at baseline depth).
Use any randomization method available (e.g., shuffle the list and pick the first 3).

**Add this to each subagent's prompt** (after the review criteria section):

```
YOUR PRIMARY FOCUS AREA: [assigned area]

You must do a TWO-PASS review:

PASS 1 — Full review across all areas. Review every changed file against all criteria (Security,
Style, TestCoverage, ErrorHandling). Record your findings as you go.

PASS 2 — Focused re-review through the lens of [assigned area]. Go back through the changed files
a second time, but now ONLY look through the [assigned area] lens. Consider your Pass 1 findings
and ask yourself: "Did I miss anything related to [assigned area]?" Read additional files if
needed — grep for related patterns, check edge cases, look at how similar code handles [assigned
area] elsewhere in the codebase. This second pass is where you add the most unique value.

Combine findings from both passes in your final output. If Pass 2 found something Pass 1 missed,
great — that's the whole point.
```

### The 3 subagents

| # | Model | Description label |
|---|-------|------------------|
| 1 | `claude-opus-4.6` | "Code review (Claude Opus)" |
| 2 | `gpt-5.2-codex` | "Code review (GPT)" |
| 3 | `gemini-3-pro-preview` | "Code review (Gemini)" |

## Step 4: Collect results and quality gate

Wait for all 3 subagents to complete using `read_agent`.

### Quality gate — detect slacking reviewers

After collecting each result, check whether the reviewer actually did their job. A result **fails
the quality gate** if ANY of these are true:

- The agent returned **no response** or an empty result
- The response is **shorter than 200 characters**
- The response does **not contain "FILES REVIEWED:"** (meaning it skipped the required work)
- The agent completed in **under 30 seconds** (strong signal it didn't use tools)

### Retry failed reviewers

If a result fails the quality gate, **immediately re-launch** that specific model with an escalated
prompt. Use the same subagent prompt template from Step 3, but prepend this warning:

```
⚠️ YOUR PREVIOUS ATTEMPT FAILED — you returned an empty or insufficient response.
This is your SECOND attempt. You MUST use tools this time. Specifically:
1. Call pull_request_read to get the diff
2. Call pull_request_read to get the file list
3. Use "view" to read EVERY changed file in full
4. Use "grep" to find usages of changed functions
If you return another empty response, you will be excluded from the consensus.
```

Rules:

- **Maximum 1 retry per model.** If a model fails twice, exclude it from the consensus and note
  the failure in the final output.
- Re-launch the retry as a background agent and wait for it to complete.
- If 2+ models fail after retries, report what you have and note the degraded consensus.
- Adjust the synthesis accordingly (e.g., with only 2 models, consensus is 2/2 or 1/2 instead of
  3/3, 2/3, 1/3).

## Step 5: Synthesize with weighted consensus

Compare the findings from all 3 models and produce a single consolidated review.

### Consensus rules

1. **Group duplicate/overlapping findings.** Two findings are "the same" if they reference the same
   file/location and describe the same underlying issue (even if worded differently).
   When merging, combine the best description for "What?", keep the clearest code snippet for
   "Where?", and pick the most actionable "Recommendation:". If none of the subagents included a
   snippet, fetch the code yourself with the `view` tool and include ~5-10 lines around the issue.

1. **Rank by agreement level and always present in this order** (highest confidence first):

   - 🔴 **High confidence** (3/3 models agree) — Almost certainly a real issue. Present these FIRST.
   - 🟡 **Medium confidence** (2/3 models agree) — Likely a real issue. Present these SECOND.
   - 🔵 **Single model** (1/3) — Possibly a real issue. Present these LAST.
     Within each confidence section, sort findings by severity: critical → high → medium → low.

1. **Determine overall verdict by majority rule:**

   - If 2+ models say REQUEST_CHANGES → final verdict is **REQUEST CHANGES**
   - If 2+ models say COMMENT → final verdict is **COMMENT**
   - If 2+ models say APPROVE → final verdict is **APPROVE**

1. **If all 3 models approve with no findings, simply say the code looks good.** Don't pad the
   output with unnecessary commentary.

### Output format

Present the final synthesis to the user in this format:

````
## Multi-Model Code Review Summary

### What changed
[Insert the change summary from Step 2]

**Verdict: [APPROVE ✅ | REQUEST CHANGES ❌ | COMMENT 💬]**
Model verdicts: Claude Opus (focus: [area]) → [verdict], GPT (focus: [area]) → [verdict], Gemini (focus: [area]) → [verdict]

### 🔴 High Confidence (all 3 models agree)
[For each finding use this structure:]

**[Title]** (severity) — all 3 models

**What?**
[Description of the issue]

**Where?** `filename:line_number` (line number is required)
```powershell
[code snippet showing the problematic code]
````

**Recommendation:**
[What to do about it, with fix snippet if applicable]

______________________________________________________________________

[Or "None" if no findings at this level]

### 🟡 Medium Confidence (2 of 3 models agree)

[Same structure as above, noting which 2 models flagged it, or "None"]

### 🔵 Single Model Findings

[Same structure as above, noting which model flagged it, or "None"]

### Summary

[1-2 sentence pragmatic summary. If the code is fine, just say so.]

```

**IMPORTANT:** Always include all three confidence sections (🔴, 🟡, 🔵) in the output, even when
empty. Show "None" for sections with no findings. This keeps the output consistent and makes it
immediately clear what was and wasn't flagged. For example, when all models approve:

```

## Multi-Model Code Review Summary

### What changed

[Insert the change summary from Step 2]

**Verdict: APPROVE ✅**
Model verdicts: Claude Opus (focus: Security) → APPROVE, GPT (focus: ErrorHandling) → APPROVE, Gemini (focus: Style) → APPROVE

### 🔴 High Confidence (all 3 models agree)

None

### 🟡 Medium Confidence (2 of 3 models agree)

None

### 🔵 Single Model Findings

None

### Summary

All 3 models reviewed the changes and found no issues. The code looks good. 👍

````

## Step 6: Create pending review on PR

After presenting the synthesis in the terminal, create a **pending (draft) review** on the PR so
the user can see findings inline in the "Files changed" tab.

**IMPORTANT:** The review must NOT be submitted. A pending review is only visible to the
authenticated user until they choose to submit or discard it.

### Check for existing pending review

Before creating a new review, check if the user already has a pending review on this PR:

```powershell
gh api repos/{owner}/{repo}/pulls/{pull_number}/reviews --jq '[.[] | select(.state == "PENDING")]'
````

If a pending review exists, **you MUST ask the user** (using the `ask_user` tool) whether it is
okay to delete it. Explain that GitHub only allows one pending review per user per PR, so the
existing one must be deleted before a new one can be created. **Do NOT delete it without explicit
user confirmation.** If the user declines, skip this step and only show findings in the terminal.

If the user confirms, delete the existing review:

```
DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
```

### Validate line placement

Subagents report line numbers, but these may be slightly off — a comment placed even one line away
from the actual issue is confusing. Before building the review payload, **you (the orchestrator)
must verify and correct every line number** by reading the PR diff yourself:

1. Fetch the diff: `pull_request_read` with `method: "get_diff"`
1. For each finding with a file + line number:
   a. Find the relevant diff hunk for that file (look for `@@ ... @@` headers)
   b. Read the code around the reported line number in the diff
   c. Identify the **exact line** where the comment belongs — this is the line that best represents
   the issue (e.g., the line with the bug, the missing check, the problematic pattern)
   d. If the subagent's line is off by a few lines, correct it
   e. If the line is not in the diff at all, move the finding to the review `body` text instead
1. This validation is non-negotiable — every inline comment must point to the precise line

### How to create the pending review

Use `gh api` via the shell to create the review. The API endpoint is:

```
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

Build the request body as JSON with:

- `body` — the overall synthesis summary (verdict + model verdicts table, keep it brief)
- `comments` — an array of inline comments, one per finding that has a specific file + line number

Each comment in the array needs:

- `path` — the file path (e.g., `Actions/RunPipeline/RunPipeline.ps1`)
- `line` — the **validated** line number (after your verification in the step above)
- `side` — always `"RIGHT"` (we're commenting on the new version)
- `body` — the finding formatted as markdown:
  ```
  **[🔴|🟡|🔵] [Title]** (severity) — [which models]

  **What?** [description]

  **Recommendation:** [fix suggestion]
  ```

### Comment formatting rules (must be consistent across every run)

Every inline comment and every finding in the terminal output **must** use exactly the format above.
These visual cues are non-negotiable and must not vary between runs:

- **Confidence emoji prefix**: `🔴` (3/3), `🟡` (2/3), or `🔵` (1/3) — always the first character
  of the bold title. Never omit, never substitute with text like "(high confidence)".
- **Title in bold**: `**🟡 Title here**` — emoji inside the bold markers, followed by the title.
- **Severity in parentheses**: `(critical)`, `(high)`, `(medium)`, or `(low)` — immediately after
  the closing `**`, separated by a space.
- **Em-dash with model names**: ` — Claude Opus + GPT` — use the em-dash character `—` (not `-`
  or `--`), preceded and followed by a space. List the agreeing model names separated by `+`.
- **What? section**: Always `**What?**` followed by a newline and the description.
- **Recommendation section**: Always `**Recommendation:**` followed by a newline and the fix
  suggestion. Include code snippets in fenced blocks when applicable.

**Do not** use alternative formats like "Flagged by:", "(2/3 models)", numbered lists, or any
other layout. The format must be identical whether the output goes to the terminal or a PR review.

**Technical note:** When building the JSON payload for the GitHub API, use Python (write a temp
`.py` file and run it) rather than constructing JSON inline in PowerShell. PowerShell's terminal
mangles Unicode emojis and `${{ }}` curly brace patterns. Python handles both natively.

**Do NOT include the `event` field** — omitting it creates a PENDING review that is not submitted.

### Handling findings without line numbers

Some findings don't have a specific file/line (e.g., "missing test for X", "no documentation
update"). Include these in the review `body` text rather than as inline comments.

### Example shell command

```powershell
$comments = [System.Collections.ArrayList]::new()
$null = $comments.Add(@{
    path = "Actions/RunPipeline/RunPipeline.ps1"
    line = 202; side = "RIGHT"
    body = "**🟡 Get-Content missing -Raw** (medium)`nFlagged by: Claude Opus`n`n**What?** Without -Raw, multi-line JSON fails in PS 5.1.`n`n**Recommendation:** Use ``Get-Content -Raw``"
})

$payload = @{
    body = "## Multi-Model Review: REQUEST CHANGES (2/3)..."
    comments = $comments.ToArray()
} | ConvertTo-Json -Depth 5

# Write WITHOUT BOM — gh api chokes on UTF-8 BOM
$tempFile = Join-Path $env:TEMP "review-payload.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempFile, $payload, $utf8NoBom)

Get-Content $tempFile -Raw | gh api repos/{owner}/{repo}/pulls/{pull_number}/reviews --method POST --input -

Remove-Item $tempFile -ErrorAction SilentlyContinue
```

### Important notes

- **UTF-8 BOM**: PowerShell's default `Set-Content` writes a BOM. The `gh api --input` command
  rejects JSON with BOM. Always use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`
  or pipe via `Get-Content -Raw | gh api ... --input -`.
- **Line numbers are validated by the orchestrator**: The "Validate line placement" step above
  ensures every inline comment points to the exact right line. Subagent-reported lines are treated
  as approximate — the orchestrator reads the diff and corrects them before building the payload.
- **Use `ArrayList` for comments**: PowerShell's `@()` array with complex hashtables can lose items
  during `ConvertTo-Json`. Use `[System.Collections.ArrayList]` with `.Add()` instead.
- **One pending review per user**: GitHub only allows one pending review per user per PR. If you
  need to update a pending review (e.g., add more comments), you must delete the existing pending
  review first (`DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}`) and
  recreate it with ALL comments included. Always include all findings in a single review creation.

### When to skip

- If reviewing local changes (not a PR), skip this step — there's no PR to attach comments to.
- If there are no findings (all models approve with no issues), skip this step — don't create an
  empty review.
- If the `gh` CLI is not available or not authenticated, skip and note it in the terminal output.
