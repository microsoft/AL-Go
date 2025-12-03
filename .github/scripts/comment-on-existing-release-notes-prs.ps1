#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Adds a comment to all open PRs that modify RELEASENOTES.md
.DESCRIPTION
    This script searches for all open PRs that have changes to RELEASENOTES.md
    and adds a reminder comment about placing changes above the new version section.
    
    This is a one-time script to handle existing PRs. New PRs will be handled
    by the check-release-notes-prs.yml workflow.
.PARAMETER Owner
    The repository owner (default: microsoft)
.PARAMETER Repo
    The repository name (default: AL-Go)
.PARAMETER GitHubToken
    GitHub token with permissions to comment on PRs
.EXAMPLE
    $env:GITHUB_TOKEN = "your-token-here"
    ./comment-on-existing-release-notes-prs.ps1
#>

param(
    [string]$Owner = "microsoft",
    [string]$Repo = "AL-Go",
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

if (-not $GitHubToken) {
    Write-Error "GitHub token is required. Set GITHUB_TOKEN environment variable or pass -GitHubToken parameter."
    exit 1
}

# Detect current version from RELEASENOTES.md
$currentVersion = "v8.1" # fallback
$releaseNotesPath = Join-Path $PSScriptRoot "../../RELEASENOTES.md"
if (Test-Path $releaseNotesPath) {
    $releaseNotesContent = Get-Content -Path $releaseNotesPath -Raw
    if ($releaseNotesContent -match '^##\s*v(\d+\.\d+)') {
        $currentVersion = "v$($matches[1])"
        Write-Host "Detected current version: $currentVersion"
    }
} else {
    Write-Host "Could not find RELEASENOTES.md, using fallback version: $currentVersion"
}

$comment = @"
### ⚠️ Release Notes Update Reminder

Thank you for updating the release notes! 

Please ensure that your changes are placed **above the new version section** (currently ``## $currentVersion``) in the RELEASENOTES.md file.

This helps maintain a clear changelog structure where new changes are grouped under the latest unreleased version.
"@

$headers = @{
    "Authorization" = "Bearer $GitHubToken"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

Write-Host "Fetching open pull requests for $Owner/$Repo..."

# Get all open PRs
$prsUrl = "https://api.github.com/repos/$Owner/$Repo/pulls?state=open&per_page=100"
$prs = Invoke-RestMethod -Uri $prsUrl -Headers $headers -Method Get

Write-Host "Found $($prs.Count) open PRs. Checking which ones modify RELEASENOTES.md..."

$prsWithReleaseNotes = @()

foreach ($pr in $prs) {
    $prNumber = $pr.number
    Write-Host "Checking PR #$prNumber..."
    
    # Get files changed in this PR
    $filesUrl = "https://api.github.com/repos/$Owner/$Repo/pulls/$prNumber/files"
    $files = Invoke-RestMethod -Uri $filesUrl -Headers $headers -Method Get
    
    # Check if RELEASENOTES.md was modified
    $releaseNotesModified = $files | Where-Object { $_.filename -eq "RELEASENOTES.md" }
    
    if ($releaseNotesModified) {
        Write-Host "  ✓ PR #$prNumber modifies RELEASENOTES.md"
        $prsWithReleaseNotes += $pr
    } else {
        Write-Host "  - PR #$prNumber does not modify RELEASENOTES.md"
    }
}

Write-Host "`nFound $($prsWithReleaseNotes.Count) PRs that modify RELEASENOTES.md"

if ($prsWithReleaseNotes.Count -eq 0) {
    Write-Host "No PRs found that modify RELEASENOTES.md. Exiting."
    exit 0
}

Write-Host "`nAdding comments to PRs..."

foreach ($pr in $prsWithReleaseNotes) {
    $prNumber = $pr.number
    $prTitle = $pr.title
    
    Write-Host "`nProcessing PR #$prNumber: $prTitle"
    
    # Check if we've already commented
    $commentsUrl = "https://api.github.com/repos/$Owner/$Repo/issues/$prNumber/comments"
    $existingComments = Invoke-RestMethod -Uri $commentsUrl -Headers $headers -Method Get
    
    $alreadyCommented = $existingComments | Where-Object { 
        $_.user.type -eq "Bot" -and $_.body -like "*Release Notes Update Reminder*"
    }
    
    if ($alreadyCommented) {
        Write-Host "  ℹ️  Comment already exists on PR #$prNumber, skipping..."
        continue
    }
    
    # Add comment
    try {
        $body = @{
            body = $comment
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $commentsUrl -Headers $headers -Method Post -Body $body -ContentType "application/json"
        Write-Host "  ✓ Comment added to PR #$prNumber"
    }
    catch {
        Write-Error "  ✗ Failed to add comment to PR #$prNumber: $_"
    }
}

Write-Host "`n✓ Done! Comments have been added to $($prsWithReleaseNotes.Count) PRs."
