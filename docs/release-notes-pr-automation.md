# Release Notes PR Automation

## Overview

This automation ensures that contributors are reminded to place their release note changes in the correct location within the `RELEASENOTES.md` file.

## Problem

When multiple contributors update the release notes, there's a risk that changes might be added to different version sections or in the wrong location. To maintain a clear and organized changelog, all new changes should be added under the latest/upcoming version section.

## Solution

### PowerShell Script for Adding Comments

**File**: `.github/scripts/comment-on-existing-release-notes-prs.ps1`

This PowerShell script can be run manually to add reminder comments to all currently open PRs that modify `RELEASENOTES.md`.

**Usage:**
```powershell
# Option 1: Use gh auth login (recommended - more secure)
gh auth login

# Option 2: Set GitHub token as environment variable
# Note: Tokens set this way may be visible in shell history
$env:GH_TOKEN = "your-token-here"
# or
$env:GITHUB_TOKEN = "your-token-here"

# Run the script
pwsh .github/scripts/comment-on-existing-release-notes-prs.ps1
```

**Security Note:** When setting tokens directly in the shell, they may be visible in your shell history. Consider using `gh auth login` or a secure credential manager for production use.

**Key Features:**
- Uses GitHub CLI (`gh`) for better readability and maintainability
- Automatically detects current version from `RELEASENOTES.md`
- Checks for existing active comments to avoid duplicates
- Provides detailed summary with success/skip/fail counts
- Exits with error if any comments fail to add
- Lists failed PRs for manual review

**What it does:**
1. Verifies GitHub CLI is installed and authenticated
2. Automatically detects the current version from `RELEASENOTES.md`
3. Fetches all open pull requests using `gh pr list`
4. Checks each PR to see if it modifies `RELEASENOTES.md`
5. For PRs that modify release notes:
   - Checks if an active reminder comment already exists
   - If not, adds the reminder comment
6. Provides a detailed summary report

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
- Reading the file and finding the first line matching the pattern `## vX.Y`
- Using the detected version in the comment message
- **Failing with an error if the version cannot be detected** (ensures the automation is working correctly)

This means no manual updates are needed when a new version is released - the comment will automatically reference the correct version. If version detection fails, it indicates an issue that needs to be addressed.

## Implementation Details

### Script Implementation

The PowerShell script:
- Uses GitHub CLI (`gh`) for better readability and maintainability
- Requires GitHub CLI to be installed and authenticated
- Automatically detects current version from RELEASENOTES.md
- Implements duplicate detection
- Tracks success, skip, and fail counts
- Provides detailed progress output and summary
- Handles errors gracefully and reports failures

## Maintenance

### Automatic Updates

The version number is automatically detected from `RELEASENOTES.md`, so no manual updates are needed when a new version is released. The workflows and script will automatically use the current version found in the file.

### Monitoring

You can monitor the automation by:
1. Checking PR comments for the reminder message
2. Reviewing workflow runs in the Actions tab
3. Checking for any workflow failures

### Troubleshooting

**Script fails:**
- Ensure GitHub CLI (`gh`) is installed: https://cli.github.com/
- Verify authentication: run `gh auth status`
- Set `GH_TOKEN` or `GITHUB_TOKEN` environment variable
- Verify token has `pull-requests: write` permission
- Check API rate limits aren't exceeded
- Ensure `RELEASENOTES.md` exists and contains a version header

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

To test the script:

1. **Test Script**: Run the script with authentication in a fork or test repository
2. **Verify**: Check that comments are added correctly and duplicates are avoided
3. **Review**: Check the summary report for success/skip/fail counts

## References

- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [GitHub REST API - Issues Comments](https://docs.github.com/en/rest/issues/comments)
- [AL-Go Release Notes](../RELEASENOTES.md)
