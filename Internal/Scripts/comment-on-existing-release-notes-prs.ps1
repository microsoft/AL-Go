#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Adds a comment to all open PRs that modify RELEASENOTES.md
.DESCRIPTION
    This script searches for all open PRs that have changes to RELEASENOTES.md
    and adds a reminder comment about placing changes above the new version section.

    Uses GitHub CLI (gh) for better readability and maintainability.

    The script will:
    1. Verify GitHub CLI is installed and authenticated
    2. Automatically detect the current version from RELEASENOTES.md
    3. Fetch all open pull requests using 'gh pr list'
    4. Check each PR to see if it modifies RELEASENOTES.md
    5. For PRs that modify the release notes:
       - Check if an active reminder comment already exists
       - If not, add a comment reminding contributors to place changes above the new version section
    6. Provide a detailed summary with success/skip/fail counts
    7. List any PRs where comment addition failed
.PARAMETER Owner
    The repository owner (default: microsoft)
.PARAMETER Repo
    The repository name (default: AL-Go)
.EXAMPLE
    # Recommended: Use gh auth login (more secure)
    gh auth login
    ./comment-on-existing-release-notes-prs.ps1
.EXAMPLE
    # Alternative: Set GH_TOKEN or GITHUB_TOKEN environment variable
    # Note: Tokens may be visible in shell history
    $env:GH_TOKEN = "your-token-here"
    ./comment-on-existing-release-notes-prs.ps1
.NOTES
    Requirements:
    - GitHub CLI (gh) installed: https://cli.github.com/
    - GitHub authentication (via 'gh auth login' or GH_TOKEN/GITHUB_TOKEN environment variable)
    - PowerShell 7 or later

    Error Handling:
    - Errors out if GitHub CLI is not installed
    - Errors out if not authenticated
    - Errors out if version cannot be detected from RELEASENOTES.md
    - Tracks and reports failed comment additions
    - Exit code 1 if any comments fail, 0 if all successful
#>

param(
    [string]$Owner = "microsoft",
    [string]$Repo = "AL-Go"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# Check if gh CLI is available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com/"
    exit 1
}

# Verify authentication
try {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI is not authenticated. Run 'gh auth login' or set GH_TOKEN/GITHUB_TOKEN environment variable."
        exit 1
    }
} catch {
    Write-Error "Failed to verify GitHub CLI authentication: $_"
    exit 1
}

# Detect current version from RELEASENOTES.md
$releaseNotesPath = Join-Path $PSScriptRoot "../../RELEASENOTES.md"
if (-not (Test-Path $releaseNotesPath)) {
    Write-Error "RELEASENOTES.md not found at $releaseNotesPath"
    exit 1
}

$releaseNotesContent = Get-Content -Path $releaseNotesPath -Raw
if ($releaseNotesContent -match '(?m)^##\s*v(\d+\.\d+)') {
    $currentVersion = "v$($matches[1])"
    Write-Host "Detected current version: $currentVersion"
} else {
    Write-Error "Could not detect version from RELEASENOTES.md. Expected to find a line matching '## vX.Y'"
    exit 1
}

$comment = @"
A new version of AL-Go ($currentVersion) has been released.

Please move your release notes changes to above the ``## $currentVersion`` section in the RELEASENOTES.md file.

This ensures your changes are included in the next release rather than being listed under an already-released version.
"@

Write-Host "Fetching open pull requests for $Owner/$Repo..."

# Get all open PRs using gh CLI
$prsJsonOutput = gh pr list --repo "$Owner/$Repo" --state open --limit 100 --json number,title,files
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch pull requests from GitHub"
    exit 1
}

$prsJson = @($prsJsonOutput | ConvertFrom-Json)

Write-Host "Found $($prsJson.Count) open PRs. Checking which ones modify RELEASENOTES.md..."

$prsWithReleaseNotes = @()

foreach ($pr in $prsJson) {
    $prNumber = $pr.number
    Write-Host "Checking PR #$prNumber..."

    # Check if RELEASENOTES.md was modified
    $releaseNotesModified = $pr.files | Where-Object { $_.path -eq "RELEASENOTES.md" }

    if ($releaseNotesModified) {
        Write-Host "  ✓ PR #$prNumber modifies RELEASENOTES.md"
        $prsWithReleaseNotes += $pr
    } else {
        Write-Host "  - PR #$prNumber does not modify RELEASENOTES.md"
    }
}

if ($prsWithReleaseNotes.Count -eq 0) {
    Write-Host "`nNo PRs found that modify RELEASENOTES.md. Exiting."
    exit 0
}

Write-Host "`nFound $($prsWithReleaseNotes.Count) PRs that modify RELEASENOTES.md"
Write-Host "`nAdding comments to PRs..."

$successCount = 0
$skipCount = 0
$failCount = 0
$failedPRs = @()

foreach ($pr in $prsWithReleaseNotes) {
    $prNumber = $pr.number
    $prTitle = $pr.title

    Write-Host "`nProcessing PR #${prNumber}: $prTitle"

    # Check if we've already commented (check for review comments on RELEASENOTES.md)
    $searchText = "A new version of AL-Go ($currentVersion) has been released."
    $existingReviewCommentsOutput = gh api "/repos/$Owner/$Repo/pulls/$prNumber/comments" --jq "[.[] | select(.path == `"RELEASENOTES.md`" and (.body | contains(`"$searchText`")))]"

    if ($LASTEXITCODE -eq 0 -and $existingReviewCommentsOutput) {
        $existingReviewComments = $existingReviewCommentsOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

        if ($existingReviewComments -and $existingReviewComments.Count -gt 0) {
            Write-Host "  ℹ️  Review comment already exists on RELEASENOTES.md in PR #$prNumber, skipping..."
            $skipCount++
            continue
        }
    }

    # Add review comment on RELEASENOTES.md file
    $tempFile = $null
    try {
        # Get the commit SHA for the PR
        $prDetails = gh api "/repos/$Owner/$Repo/pulls/$prNumber" | ConvertFrom-Json
        $commitSha = $prDetails.head.sha

        # Create review comment payload
        $reviewCommentBody = @{
            body = $comment
            path = "RELEASENOTES.md"
            commit_id = $commitSha
        } | ConvertTo-Json -Compress

        # Save to temp file
        $tempFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempFile -Value $reviewCommentBody -NoNewline

        # Post the review comment
        $response = gh api -X POST "/repos/$Owner/$Repo/pulls/$prNumber/comments" --input $tempFile

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Review comment added to RELEASENOTES.md in PR #$prNumber"
            $successCount++
        } else {
            Write-Warning "  ✗ Failed to add review comment to PR #${prNumber}"
            $failCount++
            $failedPRs += $prNumber
        }
    }
    catch {
        Write-Warning "  ✗ Failed to add review comment to PR #${prNumber}: $_"
        $failCount++
        $failedPRs += $prNumber
    }
    finally {
        # Always clean up temp file
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Final summary
Write-Host "`n========================================="
Write-Host "Summary:"
Write-Host "  Total PRs with RELEASENOTES.md changes: $($prsWithReleaseNotes.Count)"
Write-Host "  Comments added: $successCount"
Write-Host "  Skipped (already commented): $skipCount"
Write-Host "  Failed: $failCount"

if ($failCount -gt 0) {
    Write-Host "`n⚠️  Failed to add comments to the following PRs:"
    foreach ($prNum in $failedPRs) {
        Write-Host "  - PR #$prNum"
    }
    Write-Host "`nPlease review these PRs manually."
    exit 1
} else {
    Write-Host "`n✓ Done! All comments have been processed successfully."
    exit 0
}
