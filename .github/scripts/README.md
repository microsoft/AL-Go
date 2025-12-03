# AL-Go Scripts

This directory contains utility scripts for the AL-Go repository.

## comment-on-existing-release-notes-prs.ps1

This PowerShell script adds a reminder comment to all open PRs that modify the `RELEASENOTES.md` file. It uses GitHub CLI (gh) for better readability and maintainability.

### Usage

```powershell
# Option 1: Use gh auth login (recommended - more secure)
gh auth login

# Option 2: Set GitHub token as environment variable
# Note: Tokens may be visible in shell history
$env:GH_TOKEN = "your-github-token-here"
# or
$env:GITHUB_TOKEN = "your-github-token-here"

# Run the script
pwsh .github/scripts/comment-on-existing-release-notes-prs.ps1
```

**Security Note:** When setting tokens directly, they may be visible in your shell history. Use `gh auth login` for better security.

### Parameters

- `Owner` (optional): Repository owner (default: "microsoft")
- `Repo` (optional): Repository name (default: "AL-Go")

### What it does

1. Verifies GitHub CLI is installed and authenticated
2. Automatically detects the current version from `RELEASENOTES.md`
3. Fetches all open pull requests in the repository using `gh pr list`
4. Checks each PR to see if it modifies `RELEASENOTES.md`
5. For PRs that do modify the release notes:
   - Checks if an active reminder comment already exists
   - If not, adds a comment reminding contributors to place their changes above the new version section
6. Provides a detailed summary with success/skip/fail counts
7. Lists any PRs where comment addition failed

### Requirements

- GitHub CLI (`gh`) installed: https://cli.github.com/
- GitHub token with PR comment permissions (set via `GH_TOKEN` or `GITHUB_TOKEN`)
- PowerShell 7 or later

### Error Handling

- Errors out if GitHub CLI is not installed
- Errors out if not authenticated
- Errors out if version cannot be detected from `RELEASENOTES.md`
- Tracks and reports failed comment additions
- Exit code 1 if any comments fail, 0 if all successful
