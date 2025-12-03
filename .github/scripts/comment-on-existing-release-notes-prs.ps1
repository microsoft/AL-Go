#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Adds a comment to all open PRs that modify RELEASENOTES.md
.DESCRIPTION
    This script searches for all open PRs that have changes to RELEASENOTES.md
    and adds a reminder comment about placing changes above the new version section.
    
    Uses GitHub CLI (gh) for better readability and maintainability.
.PARAMETER Owner
    The repository owner (default: microsoft)
.PARAMETER Repo
    The repository name (default: AL-Go)
.EXAMPLE
    # Set GH_TOKEN or GITHUB_TOKEN environment variable
    $env:GH_TOKEN = "your-token-here"
    ./comment-on-existing-release-notes-prs.ps1
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
### ⚠️ Release Notes Update Reminder

Thank you for updating the release notes! 

Please ensure that your changes are placed **above the new version section** (currently ``## $currentVersion``) in the RELEASENOTES.md file.

This helps maintain a clear changelog structure where new changes are grouped under the latest unreleased version.
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
    
    # Check if we've already commented (check for active/open comments)
    $existingCommentsOutput = gh api "/repos/$Owner/$Repo/issues/$prNumber/comments" --jq '[.[] | select(.body | contains("Release Notes Update Reminder"))]'
    
    if ($LASTEXITCODE -eq 0 -and $existingCommentsOutput) {
        $existingComments = $existingCommentsOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
        
        if ($existingComments -and $existingComments.Count -gt 0) {
            Write-Host "  ℹ️  Comment already exists on PR #$prNumber, skipping..."
            $skipCount++
            continue
        }
    }
    
    # Add comment using gh CLI
    $tempFile = $null
    try {
        # Save comment to temp file to avoid escaping issues
        $tempFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempFile -Value $comment -NoNewline
        
        gh pr comment $prNumber --repo "$Owner/$Repo" --body-file $tempFile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Comment added to PR #$prNumber"
            $successCount++
        } else {
            Write-Warning "  ✗ Failed to add comment to PR #${prNumber}"
            $failCount++
            $failedPRs += $prNumber
        }
    }
    catch {
        Write-Warning "  ✗ Failed to add comment to PR #${prNumber}: $_"
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
