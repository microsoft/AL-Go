# Release Notes PR Automation

## Overview

This automation ensures that contributors are reminded to place their release note changes in the correct location within the `RELEASENOTES.md` file.

## Problem

When multiple contributors update the release notes, there's a risk that changes might be added to different version sections or in the wrong location. To maintain a clear and organized changelog, all new changes should be added under the latest/upcoming version section.

## Solution

The solution consists of two components:

### 1. Automated Workflow for New PRs

**File**: `.github/workflows/check-release-notes-prs.yml`

This workflow automatically triggers when a PR is opened, updated, or reopened if it modifies the `RELEASENOTES.md` file. It:

- Detects when `RELEASENOTES.md` has been changed in a PR
- Checks if a reminder comment already exists
- If not, adds a friendly comment reminding the contributor to place changes above the new version section

**Trigger Conditions:**
- `pull_request` events: `opened`, `synchronize`, `reopened`
- Only when `RELEASENOTES.md` is modified

**Permissions Required:**
- `pull-requests: write` - to add comments
- `contents: read` - to read the repository content

### 2. One-Time Script for Existing PRs

**Files**: 
- `.github/scripts/comment-on-existing-release-notes-prs.ps1` (PowerShell script)
- `.github/workflows/comment-on-existing-release-notes-prs.yml` (Manual workflow)

These are designed to be run once to add comments to all currently open PRs that modify `RELEASENOTES.md`. After the initial run, the automated workflow handles new PRs.

**Usage (Recommended - Manual Workflow):**
1. Go to the Actions tab in the repository
2. Select "Comment on Existing Release Notes PRs" workflow
3. Click "Run workflow"
4. Choose whether to run in dry-run mode (preview only)
5. Click "Run workflow" to execute

**Usage (Alternative - PowerShell Script):**
```powershell
$env:GITHUB_TOKEN = "your-token-here"
pwsh .github/scripts/comment-on-existing-release-notes-prs.ps1
```

What it does:
1. Fetches all open PRs (or uses a predefined list)
2. Checks which ones modify `RELEASENOTES.md`
3. Adds the reminder comment (if not already present)

## Comment Content

The comment added to PRs is:

```markdown
### ⚠️ Release Notes Update Reminder

Thank you for updating the release notes! 

Please ensure that your changes are placed **above the new version section** (currently `## v8.1`) in the RELEASENOTES.md file.

This helps maintain a clear changelog structure where new changes are grouped under the latest unreleased version.
```

## Automatic Version Detection

The workflows and script automatically detect the current version from `RELEASENOTES.md` by:
- Reading the file and finding the first line matching the pattern `## vX.Y` or `## vX.Y.Z`
- Using the detected version in the comment message
- **Failing with an error if the version cannot be detected** (ensures the automation is working correctly)

This means no manual updates are needed when a new version is released - the comment will automatically reference the correct version. If version detection fails, it indicates an issue that needs to be addressed.

## Implementation Details

### Workflow Implementation

The workflow uses `actions/github-script@v7` which provides:
- GitHub API access via `github` object
- Context information via `context` object
- Checkout step to read `RELEASENOTES.md` for version detection

**Key Features:**
- Only triggers on `RELEASENOTES.md` changes (path filter)
- Automatically detects current version from RELEASENOTES.md
- Checks for existing comments to avoid duplicates
- Uses Bot user type to identify its own comments
- Minimal permissions (read content, write comments)

### Script Implementation

The PowerShell script:
- Uses GitHub REST API directly
- Requires a GitHub token with PR comment permissions
- Automatically detects current version from RELEASENOTES.md
- Implements duplicate detection
- Provides detailed progress output
- Handles errors gracefully

## Maintenance

### Automatic Updates

The version number is automatically detected from `RELEASENOTES.md`, so no manual updates are needed when a new version is released. The workflows and script will automatically use the current version found in the file.

### Monitoring

You can monitor the automation by:
1. Checking PR comments for the reminder message
2. Reviewing workflow runs in the Actions tab
3. Checking for any workflow failures

### Troubleshooting

**Workflow doesn't trigger:**
- Verify the PR modifies `RELEASENOTES.md`
- Check workflow permissions are correct
- Review the workflow run logs in Actions tab

**Script fails:**
- Ensure `GITHUB_TOKEN` is set and valid
- Verify token has `pull-requests: write` permission
- Check API rate limits aren't exceeded

**Duplicate comments:**
- The automation checks for existing comments
- If duplicates occur, check the comment detection logic

## Future Improvements

Potential enhancements:
1. Add validation to check if changes are actually in the correct section
2. Automatically detect the current version from RELEASENOTES.md
3. Add metrics/telemetry for tracking compliance
4. Create a pre-commit hook for local development

## Testing

To test the automation:

1. **Test Workflow**: Create a test PR that modifies `RELEASENOTES.md`
2. **Test Script**: Run the script with a test token in a fork
3. **Verify**: Check that comments are added correctly and duplicates are avoided

## References

- [GitHub Actions - actions/github-script](https://github.com/actions/github-script)
- [GitHub REST API - Issues Comments](https://docs.github.com/en/rest/issues/comments)
- [AL-Go Release Notes](../RELEASENOTES.md)
