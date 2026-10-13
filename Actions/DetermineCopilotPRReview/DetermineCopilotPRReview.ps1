<#
.SYNOPSIS
Resolves a workflow-run event to an eligible pull request for Copilot review.
#>
[CmdletBinding()]
param(
    [string] $token = '',
    [string] $repository = '',
    [string] $pullRequestNumber = '',
    [Parameter(Mandatory)]
    [string] $workflowHeadSha,
    [string] $workflowHeadOwner = '',
    [string] $workflowHeadBranch = '',
    [Parameter(Mandatory)]
    [string] $codeReviewAgent
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

try {
    $settings = $codeReviewAgent | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "CodeReviewAgent must be valid JSON: $($_.Exception.Message)"
}

foreach ($property in @('enabled', 'model', 'leafModel')) {
    if ($settings.PSObject.Properties.Name -notcontains $property) {
        throw "CodeReviewAgent is missing required property '$property'."
    }
}
if ([string]::IsNullOrWhiteSpace([string] $settings.model) -or [string]::IsNullOrWhiteSpace([string] $settings.leafModel)) {
    throw 'CodeReviewAgent model and leafModel must be non-empty.'
}
if ([string] $settings.model -match '[\r\n]' -or [string] $settings.leafModel -match '[\r\n]') {
    throw 'CodeReviewAgent model and leafModel must not contain line breaks.'
}
if ($repository -notmatch '^[^/\s]+/[^/\s]+$') {
    throw "repository must use owner/repository form; received '$repository'."
}
if ($workflowHeadSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw "workflowHeadSha must be a 40-character Git commit SHA; received '$workflowHeadSha'."
}
if ($pullRequestNumber -and $pullRequestNumber -notmatch '^[1-9]\d*$') {
    throw "pullRequestNumber must be a positive integer; received '$pullRequestNumber'."
}

$enabled = [bool] $settings.enabled
$eligible = $false
$resolvedNumber = ''
$headSha = ''
$baseRef = ''

if ($enabled) {
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $token"
        'User-Agent' = 'al-go-copilot-review'
    }

    if (-not $pullRequestNumber -and $workflowHeadOwner -and $workflowHeadBranch) {
        $head = [System.Uri]::EscapeDataString("${workflowHeadOwner}:$workflowHeadBranch")
        $uri = "$($env:GITHUB_API_URL.TrimEnd('/'))/repos/$repository/pulls?state=open&head=$head&per_page=30"
        $candidates = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
        $matchingCandidates = @($candidates | Where-Object { $_.head.sha -eq $workflowHeadSha })
        if ($matchingCandidates.Count -eq 1) {
            $pullRequestNumber = [string] $matchingCandidates[0].number
        }
        elseif ($matchingCandidates.Count -gt 1) {
            throw 'Pull request lookup returned multiple pull requests matching the workflow-run head SHA.'
        }
    }

    if ($pullRequestNumber) {
        $uri = "$($env:GITHUB_API_URL.TrimEnd('/'))/repos/$repository/pulls/$pullRequestNumber"
        $pullRequest = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
        $resolvedNumber = [string] $pullRequest.number
        $headSha = [string] $pullRequest.head.sha
        $baseRef = [string] $pullRequest.base.ref
        $eligible = (
            $pullRequest.state -eq 'open' -and
            $headSha -eq $workflowHeadSha -and
            -not [bool] $pullRequest.draft -and
            [string] $pullRequest.user.type -ne 'Bot'
        )
    }
}

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "enabled=$($enabled.ToString().ToLowerInvariant())"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "eligible=$($eligible.ToString().ToLowerInvariant())"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "prNumber=$resolvedNumber"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "headSha=$headSha"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "baseRef=$baseRef"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "model=$([string] $settings.model)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "leafModel=$([string] $settings.leafModel)"
