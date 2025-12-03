# AL-Go Scripts

This directory contains utility scripts for the AL-Go repository.

## comment-on-existing-release-notes-prs.ps1

This PowerShell script adds a reminder comment to all open PRs that modify the `RELEASENOTES.md` file. It's a one-time utility script to handle existing PRs.

### Usage

```powershell
# Set your GitHub token as an environment variable
$env:GITHUB_TOKEN = "your-github-token-here"

# Run the script
pwsh .github/scripts/comment-on-existing-release-notes-prs.ps1
```

### Parameters

- `Owner` (optional): Repository owner (default: "microsoft")
- `Repo` (optional): Repository name (default: "AL-Go")
- `GitHubToken` (optional): GitHub token with PR comment permissions (default: reads from `$env:GITHUB_TOKEN`)

### What it does

1. Fetches all open pull requests in the repository
2. Checks each PR to see if it modifies `RELEASENOTES.md`
3. For PRs that do modify the release notes:
   - Checks if a reminder comment already exists
   - If not, adds a comment reminding contributors to place their changes above the new version section

### Requirements

- GitHub token with `pull-requests: write` permission
- PowerShell 7 or later

### Note

For new PRs, the automated workflow `.github/workflows/check-release-notes-prs.yml` will automatically add the comment. This script is only needed to handle existing open PRs at the time of deployment.
