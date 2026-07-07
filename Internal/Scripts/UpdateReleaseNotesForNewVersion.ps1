#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Seals the current (unreleased) section of RELEASENOTES.md under a new version header.
.DESCRIPTION
    After AL-Go for GitHub is released, the notes that were accumulated at the top of
    RELEASENOTES.md need to be "sealed" under a version header (e.g. `## v9.0`) so that
    subsequent changes are collected above it for the next release.

    Previously this was done manually (for example https://github.com/microsoft/AL-Go/pull/2203).
    This script automates that step as part of the Deploy workflow: it prepends a
    `## <version>` header to RELEASENOTES.md and either commits the change directly to the
    source branch or creates a pull request against it.

    The script is idempotent - if the top-most version header in RELEASENOTES.md already
    matches the requested version, no change is made.

    When dot-sourced (for example from tests), only the functions are defined and no git
    operations are performed.
.NOTES
    The following environment variables are used when the script is invoked directly:
    - version: The version to seal the release notes under (e.g. the release branch name, 'v9.0').
    - sourceBranch: The branch that holds the release notes to seal (typically 'main').
    - directCommit: 'true' to commit directly to sourceBranch, otherwise a pull request is created.
    - GITHUB_WORKSPACE: The path to the checked out AL-Go repository.
    - GITHUB_REPOSITORY_OWNER: The owner used for the git commit identity.
    - GH_TOKEN / GITHUB_TOKEN: Token used by the GitHub CLI to authenticate git and create the PR.
#>

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Add-VersionToReleaseNotes {
    <#
    .SYNOPSIS
        Prepends a `## <version>` header to the release notes content.
    .DESCRIPTION
        Returns the release notes with a new `## <version>` header added at the top,
        sealing the current unreleased section under that version. If the top-most
        version header already matches the requested version, the content is returned
        unchanged (making the operation idempotent). Line endings are normalized to LF.
    .PARAMETER releaseNotes
        The current content of RELEASENOTES.md.
    .PARAMETER version
        The version to seal the release notes under (e.g. 'v9.0').
    .EXAMPLE
        Add-VersionToReleaseNotes -releaseNotes $content -version 'v9.0'
    #>
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $releaseNotes,
        [Parameter(Mandatory = $true)]
        [string] $version
    )

    # Normalize line endings to LF for consistent processing
    $normalized = $releaseNotes.Replace("`r`n", "`n")

    # Find the top-most version header (a line starting with '## ')
    $firstHeader = ($normalized -split "`n") | Where-Object { $_ -match '^##\s' } | Select-Object -First 1
    if ($firstHeader -eq "## $version") {
        # Release notes are already sealed under this version - nothing to do
        return $normalized
    }

    return "## $version`n`n$normalized"
}

# Main execution - skipped when the script is dot-sourced (for example from tests)
if ($MyInvocation.InvocationName -ne '.') {
    $version = "$ENV:version"
    $sourceBranch = "$ENV:sourceBranch"
    $directCommit = "$ENV:directCommit" -eq 'true'

    if (-not $version) {
        throw "The 'version' environment variable is not set."
    }
    if (-not $sourceBranch) {
        throw "The 'sourceBranch' environment variable is not set."
    }

    $releaseNotesFile = Join-Path $ENV:GITHUB_WORKSPACE "RELEASENOTES.md"
    $existingReleaseNotes = (Get-Content -Encoding utf8 -Path $releaseNotesFile -Raw).Replace("`r`n", "`n")
    $updatedReleaseNotes = Add-VersionToReleaseNotes -releaseNotes $existingReleaseNotes -version $version

    if ($updatedReleaseNotes -eq $existingReleaseNotes) {
        Write-Host "::notice::RELEASENOTES.md already contains the '## $version' section. Nothing to update."
        return
    }

    [System.IO.File]::WriteAllText($releaseNotesFile, $updatedReleaseNotes)

    # Authenticate to GIT and GH
    git config --global user.email "$($ENV:GITHUB_REPOSITORY_OWNER)@users.noreply.github.com"
    git config --global user.name "$($ENV:GITHUB_REPOSITORY_OWNER)"
    git config --global hub.protocol https
    git config --global core.autocrlf false
    gh auth setup-git
    if ($LASTEXITCODE -ne 0) { throw "Failed to set up git authentication (gh auth setup-git)." }

    $commitMessage = "Add release notes section for $version"

    if ($directCommit) {
        git add RELEASENOTES.md
        git commit -m $commitMessage
        git push origin "HEAD:$sourceBranch"
        if ($LASTEXITCODE -ne 0) { throw "Failed to push release notes to branch $sourceBranch." }
        Write-Host "::notice::Added '## $version' section to RELEASENOTES.md on branch $sourceBranch"
    }
    else {
        $branchName = "releasenotes/$version/$((Get-Date).ToUniversalTime().ToString('yyMMddHHmmss'))"
        git checkout -b $branchName
        git add RELEASENOTES.md
        git commit -m $commitMessage
        git push origin $branchName
        if ($LASTEXITCODE -ne 0) { throw "Failed to push release notes branch $branchName." }
        $prUrl = gh pr create --base $sourceBranch --head $branchName --title $commitMessage --body $commitMessage
        if ($LASTEXITCODE -ne 0) { throw "Failed to create pull request for branch $branchName." }
        Write-Host "::notice::Created pull request to add '## $version' section to RELEASENOTES.md. PR URL: $prUrl"
    }
}
