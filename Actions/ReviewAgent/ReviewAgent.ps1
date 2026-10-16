<#
.SYNOPSIS
Runs the trusted phases of Copilot pull request review.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Action inputs are consumed by phase-specific functions.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = "Review phase to run (context, prepare, generate, or post)")]
    [string] $phase,
    [Parameter(HelpMessage = "CodeReviewAgent settings as compressed JSON")]
    [string] $codeReviewSettingsJson = '',
    [Parameter(HelpMessage = "BCQuality settings as compressed JSON")]
    [string] $bcqualitySettingsJson = '',
    [Parameter(HelpMessage = "Path to the pull request event metadata")]
    [string] $metadataPath = '',
    [Parameter(HelpMessage = "Head SHA reported by the completed intake workflow")]
    [string] $workflowHeadSha = '',
    [Parameter(HelpMessage = "ID of the completed pull request intake workflow run")]
    [string] $workflowRunId = '',
    [Parameter(HelpMessage = "GitHub token used for pull request access")]
    [string] $token = '',
    [Parameter(HelpMessage = "GitHub owner/repository being reviewed")]
    [string] $repository = '',
    [Parameter(HelpMessage = "Pull request number")]
    [string] $prNumber = '',
    [Parameter(HelpMessage = "Pull request head SHA")]
    [string] $prHeadSha = '',
    [Parameter(HelpMessage = "Pull request base branch")]
    [string] $baseRef = 'main',
    [Parameter(HelpMessage = "Model used for final review consolidation")]
    [string] $model = '',
    [Parameter(HelpMessage = "Model used for isolated leaf reviews")]
    [string] $leafModel = '',
    [Parameter(HelpMessage = "Trusted base-branch checkout used by the reviewer")]
    [string] $reviewWorkspace = '',
    [Parameter(HelpMessage = "Directory used for generated review artifacts")]
    [string] $reviewOutputDir = '',
    [Parameter(HelpMessage = "Path to the installed and filtered BCQuality plugin")]
    [string] $bcqualityRoot = '',
    [Parameter(HelpMessage = "Exact Copilot CLI version to install and run; defaults to the pinned action dependency")]
    [string] $copilotCliVersion = '',
    [Parameter(HelpMessage = "Exact semantic version recorded in review comments and diagnostics")]
    [string] $agentVersion = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0
. (Join-Path -Path $PSScriptRoot -ChildPath '..\AL-Go-Helper.ps1' -Resolve)

function Write-ReviewOutput {
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowEmptyString()][string] $Value
    )

    if ($env:GITHUB_OUTPUT) {
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
}

function ConvertTo-ReviewHashtable {
    param([AllowNull()][object] $InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-ReviewHashtable -InputObject $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-ReviewHashtable -InputObject $property.Value
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return ,@($InputObject | ForEach-Object {
            ConvertTo-ReviewHashtable -InputObject $_
        })
    }
    return $InputObject
}

function Get-BCQualitySettings {
    if ([string]::IsNullOrWhiteSpace($bcqualitySettingsJson)) {
        throw 'bcqualitySettingsJson is required.'
    }

    try {
        $settings = ConvertTo-ReviewHashtable -InputObject (
            $bcqualitySettingsJson | ConvertFrom-Json -ErrorAction Stop
        )
    }
    catch {
        throw "bcqualitySettingsJson is invalid: $($_.Exception.Message)"
    }

    if (-not ($settings -is [System.Collections.IDictionary])) {
        throw 'bcqualitySettingsJson must contain a JSON object.'
    }
    if ([string]::IsNullOrWhiteSpace([string] $settings.marketplaceRepo) -or
        [string]$settings.version -notmatch '\A[0-9]+\.[0-9]+\z') {
        throw 'BCQuality.marketplaceRepo and a major.minor BCQuality.version are required.'
    }
    if (@($settings.enabledLayers).Count -eq 0) {
        throw 'BCQuality.enabledLayers must contain at least one layer.'
    }
    if (-not ($settings.knowledge -is [System.Collections.IDictionary])) {
        throw 'BCQuality.knowledge is required.'
    }

    return $settings
}

function Invoke-ContextPhase {
    if ([string]::IsNullOrWhiteSpace($codeReviewSettingsJson)) {
        throw 'codeReviewSettingsJson is required for the context phase.'
    }
    if ([string]::IsNullOrWhiteSpace($metadataPath) -or -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Pull request metadata was not found at '$metadataPath'."
    }

    $settings = $codeReviewSettingsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $bcqualitySettings = Get-BCQualitySettings
    $metadata = Get-Content -LiteralPath $metadataPath -Encoding UTF8 -Raw | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $number = [string] $metadata.pull_request.number
    if ($number -notmatch '\A[1-9][0-9]*\z' -or $workflowRunId -notmatch '\A[1-9][0-9]*\z' -or
        $repository -notmatch '\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z' -or -not $token) {
        throw 'A valid repository, pull request number, workflowRunId, and token are required for trusted context resolution.'
    }

    $apiUrl = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL.TrimEnd('/') } else { 'https://api.github.com' }
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json' }
    $run = (InvokeWebRequest -headers $headers -uri "$apiUrl/repos/$repository/actions/runs/$workflowRunId").Content |
        ConvertFrom-Json | ConvertTo-HashTable -recurse
    $pullRequest = (InvokeWebRequest -headers $headers -uri "$apiUrl/repos/$repository/pulls/$number").Content |
        ConvertFrom-Json | ConvertTo-HashTable -recurse
    $headSha = [string] $pullRequest.head.sha
    if ([string]::IsNullOrWhiteSpace($workflowHeadSha) -or $headSha -ne $workflowHeadSha -or $headSha -ne $run.head_sha) {
        throw 'Pull request head SHA does not match the triggering workflow run.'
    }
    # Fork runs can have an empty pull_requests array. Bind those runs using the
    # authoritative head repository, branch and commit rather than artifact fields.
    if ($run.event -ne 'pull_request' -or $run.conclusion -ne 'success' -or
        $run.repository.full_name -ne $repository -or $pullRequest.base.repo.full_name -ne $repository -or
        [string] $pullRequest.number -ne $number -or
        $run.head_repository.full_name -ne $pullRequest.head.repo.full_name -or
        $run.head_branch -ne $pullRequest.head.ref -or
        (@($run.pull_requests).Count -gt 0 -and $number -notin @($run.pull_requests | ForEach-Object { [string] $_.number }))) {
        throw 'Pull request identity does not match the triggering workflow run.'
    }
    if (@($run.pull_requests).Count -eq 0 -and $pullRequest.state -eq 'open') {
        $head = [Uri]::EscapeDataString("$($run.head_repository.full_name.Split('/')[0]):$($run.head_branch)")
        $matchingNumbers = @()
        $page = 1
        do {
            $candidateObjects = (InvokeWebRequest -headers $headers -uri "$apiUrl/repos/$repository/pulls?state=open&head=$head&per_page=100&page=$page").Content |
                ConvertFrom-Json
            $candidates = @($candidateObjects | ConvertTo-HashTable -recurse)
            $matchingNumbers += @($candidates | Where-Object {
                $_.head.repo.full_name -eq $run.head_repository.full_name -and
                $_.head.ref -eq $run.head_branch -and $_.head.sha -eq $run.head_sha
            } | ForEach-Object { [string] $_.number })
            $page++
        } while ($candidates.Count -eq 100)
        if ($matchingNumbers.Count -ne 1 -or $matchingNumbers[0] -ne $number) {
            throw 'Pull request identity is ambiguous or does not match the triggering workflow run.'
        }
    }
    $owner = [string] $pullRequest.user.login
    $excludedOwners = @($settings['excludedOwners'])
    $eligible = $settings['enabled'] -is [bool] -and $settings['enabled'] -eq $true -and
        $pullRequest.state -eq 'open' -and -not $pullRequest.draft -and $owner -notin $excludedOwners
    $targetBranch = [string] $pullRequest.base.ref

    Write-ReviewOutput -Name eligible -Value $eligible.ToString().ToLowerInvariant()
    Write-ReviewOutput -Name model -Value ([string] $settings['model'])
    Write-ReviewOutput -Name leafModel -Value ([string] $settings['leafModel'])
    Write-ReviewOutput -Name prNumber -Value $number
    Write-ReviewOutput -Name headSha -Value $headSha
    Write-ReviewOutput -Name baseRef -Value $targetBranch
    Write-ReviewOutput -Name bcqualitySettingsJson -Value ($bcqualitySettings | ConvertTo-Json -Compress -Depth 10)
}

function Assert-CopilotCliVersion {
    if ([string]::IsNullOrWhiteSpace($copilotCliVersion)) {
        $script:copilotCliVersion = [string] (GetPackageVersion -packageName '@github/copilot')
    }
    if ($copilotCliVersion -notmatch '\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*))?\z') {
        throw "copilotCliVersion must be an exact semantic version; received '$copilotCliVersion'."
    }
}

function Initialize-ReviewEnvironment {
    if ($agentVersion -notmatch '\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z') {
        throw "agentVersion must be an exact X.Y.Z semantic version; received '$agentVersion'."
    }

    $env:GITHUB_TOKEN = $token
    $env:GITHUB_REPOSITORY = $repository
    $env:REVIEW_WORKSPACE = $reviewWorkspace
    $env:REVIEW_OUTPUT_DIR = $reviewOutputDir
    $env:PR_NUMBER = $prNumber
    $env:PR_HEAD_SHA = $prHeadSha
    $env:BASE_BRANCH = $baseRef
    $env:MINIMUM_SEVERITY = 'Medium'
    $env:AGENT_MINIMUM_SEVERITY = 'Medium'
    $env:MAX_FINDINGS_PER_DOMAIN = '25'
    $env:COPILOT_REVIEW_FAIL_ON_PARSE_ERROR = 'true'
    $env:COPILOT_REVIEW_AGENT_LABEL = 'copilot-pr-review'
    $env:COPILOT_REVIEW_AGENT_VERSION = $agentVersion
    $env:COPILOT_REVIEW_AGENT_RELEASE_DATE = ''
    $env:COPILOT_REVIEW_AGENT_RELEASE_VERSION = ''
}

function Invoke-PreparePhase {
    Assert-CopilotCliVersion

    $npmExecutable = (Get-Command npm -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    & $npmExecutable install --global "@github/copilot@$copilotCliVersion"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install GitHub Copilot CLI $copilotCliVersion."
    }
    & copilot --version
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to execute GitHub Copilot CLI after installation.'
    }
}

function Invoke-GeneratePhase {
    Assert-CopilotCliVersion
    $bcqualitySettings = Get-BCQualitySettings
    if ([string]::IsNullOrWhiteSpace($bcqualityRoot) -or -not (Test-Path -LiteralPath $bcqualityRoot -PathType Container)) {
        throw "The prepared BCQuality plugin was not found at '$bcqualityRoot'."
    }

    Initialize-ReviewEnvironment
    $env:REVIEW_PHASE = 'generate'
    $env:GH_TOKEN = $token
    $env:BCQUALITY_ROOT = $bcqualityRoot
    $env:BCQUALITY_REPO = [string] $bcqualitySettings.marketplaceRepo
    $env:BCQUALITY_VERSION = [string] $bcqualitySettings.version
    $env:BCQUALITY_SETTINGS_JSON = ($bcqualitySettings | ConvertTo-Json -Compress -Depth 10)
    $env:BCQUALITY_CONSUME = 'plugin'
    $env:COPILOT_MODEL = $model
    $env:COPILOT_REVIEW_CLI_VERSION = $copilotCliVersion
    $env:COPILOT_REVIEW_LEAF_MODEL = $leafModel
    $env:COPILOT_REVIEW_LEAF_EXECUTION = 'serial'
    $env:COPILOT_REVIEW_MAX_LEAF_CONCURRENCY = '4'
    $env:COPILOT_REVIEW_EMBED_DIFF = 'false'
    $env:COPILOT_REVIEW_CLI_TIMEOUT_MINUTES = '30'

    & (Join-Path $PSScriptRoot 'scripts\Invoke-CopilotPRReview.ps1')
}

function Invoke-PostPhase {
    $bcqualitySettings = Get-BCQualitySettings
    Initialize-ReviewEnvironment
    $env:REVIEW_PHASE = 'post'
    $env:BCQUALITY_REPO = [string] $bcqualitySettings.marketplaceRepo
    $env:BCQUALITY_VERSION = [string] $bcqualitySettings.version
    $env:BCQUALITY_SETTINGS_JSON = ($bcqualitySettings | ConvertTo-Json -Compress -Depth 10)
    $env:COPILOT_REVIEW_POST_SUMMARY = 'false'

    & (Join-Path $PSScriptRoot 'scripts\Invoke-CopilotPRReview.ps1')
}

switch ($phase.Trim().ToLowerInvariant()) {
    'context' { Invoke-ContextPhase }
    'prepare' { Invoke-PreparePhase }
    'generate' { Invoke-GeneratePhase }
    'post' { Invoke-PostPhase }
    default { throw "Unsupported Copilot PR review phase '$phase'." }
}
