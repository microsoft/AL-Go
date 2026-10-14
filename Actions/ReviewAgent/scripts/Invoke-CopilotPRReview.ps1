<#
.SYNOPSIS
    Orchestrates a Copilot CLI review of a pull request against the
    BCQuality knowledge base and posts structured findings as inline PR
    review comments.

.DESCRIPTION
    Boundary contract: this script is orchestration only. All skills and
    knowledge live in BCQuality (https://github.com/microsoft/BCQuality, or
    a partner fork). AL-Go's BCQuality setting controls plugin filtering and
    task context.
    The runner workflow installs BCQuality as a Copilot plugin, filters that
    ephemeral installation, and hands this script the resulting
    BCQUALITY_ROOT path.

    Flow:
      1. Resolve PR metadata; check out the PR head into a detached
         worktree (review-target) so the agent can diff against
         origin/<base>.
      2. Build a `task-context` JSON document per BCQuality's entry.md
         schema and persist it inside BCQUALITY_ROOT.
      3. Resolve al-code-review from BCQuality's generated skill index.
         Launch one isolated Copilot CLI process per enabled leaf with the
         configured leaf model, using serial or bounded-parallel scheduling.
         After every validated leaf report is available, launch one root-model
         process for self-review and ordered consolidation.
      4. Parse the agent's findings-report (DO contract), map BCQuality
         severities (blocker/major/minor/info) to the existing
         Critical/High/Medium/Low taxonomy, prefer each finding's emitted
         domain label (with a legacy from-sub-skill fallback), and surface
         knowledge references in each inline comment.
      5. Upsert a single PR summary comment that reports per-domain
         counts, knowledge-files suppressed by layer precedence, skill
         sub-skills the super-skill skipped, and the orchestrator's own
         pre-filter removals from _filter-report.json.

.NOTES
    Required environment variables:
        GITHUB_TOKEN       - workflow token (write:pull-requests, write:issues)
        GITHUB_REPOSITORY  - owner/repo
        PR_NUMBER          - pull request number
        PR_HEAD_SHA        - head commit SHA of the pull request
        BCQUALITY_ROOT     - path to the filtered BCQuality plugin (all/generate)
        BCQUALITY_VERSION  - configured BCQuality major.minor content version

    Optional environment variables:
        REVIEW_WORKSPACE                     - trusted base checkout path (default: GITHUB_WORKSPACE)
        REVIEW_OUTPUT_DIR                    - artifact output folder
        REVIEW_TARGET_WORKSPACE              - detached PR-head worktree path
        GH_TOKEN                              - Copilot-enabled token for CI/PR
                                                generation.
        COPILOT_GITHUB_TOKEN                  - Copilot-enabled token forwarded only
                                                for local reviews running in CI.
                                                Other local reviews use the Copilot
                                                CLI credential store.
        COPILOT_MODEL                        - explicit model name for Copilot CLI
        COPILOT_REVIEW_CLI_VERSION           - requested pinned Copilot CLI version
        COPILOT_REVIEW_LEAF_MODEL            - model for leaf processes (defaults in review.yml)
        COPILOT_REVIEW_LEAF_EXECUTION        - serial|parallel (default serial)
        COPILOT_REVIEW_MAX_LEAF_CONCURRENCY  - positive concurrency bound for parallel mode
        MINIMUM_SEVERITY                     - Critical | High | Medium | Low (default: Medium)
        AGENT_MINIMUM_SEVERITY               - severity floor applied only to agent findings
                                               (findings BCQuality knowledge does not back).
                                               Defaults to MINIMUM_SEVERITY.
        MAX_FINDINGS_PER_DOMAIN              - per-domain cap on posted findings (default: 25)
        COMMENT_DELAY_SECONDS                - sleep between API posts (default: 0.5)
        COPILOT_REVIEW_POST_SUMMARY          - true|false: post the single overview summary comment (default: false)
        COPILOT_REVIEW_FAIL_ON_PARSE_ERROR   - true|false (default: true)
        COPILOT_REVIEW_AGENT_LABEL           - agent label for comment metadata
        COPILOT_REVIEW_AGENT_VERSION         - full X.Y.Z version; derived from the engine tag when omitted
        COPILOT_REVIEW_AGENT_RELEASE_DATE    - YYYY-MM-DD
        COPILOT_REVIEW_AGENT_RELEASE_VERSION - non-negative integer
        AGENT_COMMENT_DOC_URL                - URL surfaced in comment feedback line
        BASE_BRANCH                          - PR base branch (default: main)
        COPILOT_REVIEW_CLI_TIMEOUT_MINUTES   – Copilot CLI timeout in minutes (default: 30)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$GithubToken      = $env:GITHUB_TOKEN
$CopilotToken     = $env:GH_TOKEN
$CopilotGithubToken = $env:COPILOT_GITHUB_TOKEN
$Repository       = $env:GITHUB_REPOSITORY
$ReviewRoot       = Split-Path -Parent $PSScriptRoot
$ActionsRoot      = Split-Path -Parent $ReviewRoot
$EngineRoot       = if ((Split-Path -Leaf $ActionsRoot) -eq 'Actions') {
    Split-Path -Parent $ActionsRoot
}
else {
    $ActionsRoot
}
# GitHub host. Actions sets GITHUB_SERVER_URL / GITHUB_API_URL on every runner,
# including GitHub Enterprise Cloud with data residency (*.ghe.com) and GHES,
# so honouring them keeps the review host-neutral. Defaults keep local runs on
# github.com.
$GitHubServerUrl  = (($env:GITHUB_SERVER_URL ?? 'https://github.com') + '').Trim().TrimEnd('/')
$GitHubApiUrl     = (($env:GITHUB_API_URL ?? 'https://api.github.com') + '').Trim().TrimEnd('/')
$TrustedWorkspace = $env:REVIEW_WORKSPACE ?? $env:GITHUB_WORKSPACE ?? (Get-Location).Path
$PrNumber         = [int]($env:PR_NUMBER ?? 0)
$PrHeadSha        = $env:PR_HEAD_SHA
$BCQualityRoot    = $env:BCQUALITY_ROOT
# Review phase. Splits the privileged single-job runner into a minimal-
# permission "generate" phase (runs the tool-enabled Copilot CLI with a
# read-only token) and a write-capable "post" phase (posts comments from the
# saved agent output). 'all' preserves the original single-process behaviour
# for local development.
$ReviewPhase      = (($env:REVIEW_PHASE ?? 'all') + '').Trim().ToLowerInvariant()
function Resolve-BCQualityVersion {
    param([string] $Version)

    $resolvedVersion = ($Version + '').Trim()
    if ($resolvedVersion -notmatch '\A[0-9]+\.[0-9]+\z') {
        throw "BCQUALITY_VERSION must use major.minor format; received '$resolvedVersion'."
    }
    return $resolvedVersion
}

$BCQualityVersion = Resolve-BCQualityVersion -Version $env:BCQUALITY_VERSION
# BCQuality is trusted reviewer knowledge, not a model-writable workspace. Mount
# it as a plugin and keep every generated artifact in the per-run output tree.
$BCQualityConsume = (($env:BCQUALITY_CONSUME ?? 'plugin') + '').Trim().ToLowerInvariant()
if ($BCQualityConsume -ne 'plugin') {
    throw "BCQUALITY_CONSUME must be 'plugin' (got '$BCQualityConsume'). The legacy writable 'cwd' mode is not supported."
}
$CopilotModel     = ($env:COPILOT_MODEL ?? '').Trim()
$CopilotCliVersion = ($env:COPILOT_REVIEW_CLI_VERSION ?? '').Trim()
$LeafModel        = ($env:COPILOT_REVIEW_LEAF_MODEL ?? '').Trim()
$LeafExecution = (($env:COPILOT_REVIEW_LEAF_EXECUTION ?? 'serial') + '').Trim().ToLowerInvariant()
if ($LeafExecution -notin @('serial', 'parallel')) {
    throw "COPILOT_REVIEW_LEAF_EXECUTION must be 'serial' or 'parallel' (got '$LeafExecution')."
}
$MaxLeafConcurrency = [int]($env:COPILOT_REVIEW_MAX_LEAF_CONCURRENCY ?? 4)
if ($MaxLeafConcurrency -lt 1) {
    throw 'COPILOT_REVIEW_MAX_LEAF_CONCURRENCY must be a positive integer.'
}
$RequireLeafModel = $true
$MinimumSeverity  = $env:MINIMUM_SEVERITY ?? 'Medium'
$AgentMinimumSeverity = $env:AGENT_MINIMUM_SEVERITY ?? $MinimumSeverity
$MaxFindings      = [int]($env:MAX_FINDINGS_PER_DOMAIN ?? 25)
$CopilotCliTimeoutMinutes = [int]($env:COPILOT_REVIEW_CLI_TIMEOUT_MINUTES ?? 30)
if ($CopilotCliTimeoutMinutes -lt 0) {
    throw "COPILOT_REVIEW_CLI_TIMEOUT_MINUTES must be 0 (unlimited) or a positive number."
}
$CopilotLogLevel  = (($env:COPILOT_REVIEW_LOG_LEVEL ?? 'error') + '').Trim().ToLowerInvariant()
if ($CopilotLogLevel -notin @('none', 'error', 'warning', 'info', 'debug', 'all')) {
    throw "COPILOT_REVIEW_LOG_LEVEL must be one of: none, error, warning, info, debug, all."
}
$FailOnParseErrorRaw = (($env:COPILOT_REVIEW_FAIL_ON_PARSE_ERROR ?? 'true') + '').Trim().ToLowerInvariant()
$FailOnParseError = @('1','true','yes','on') -contains $FailOnParseErrorRaw
# The overview summary comment is opt-in noise: it is off by default so only
# actionable inline comments remain. Set COPILOT_REVIEW_POST_SUMMARY=true to
# restore the single per-run summary comment.
$PostSummaryRaw   = (($env:COPILOT_REVIEW_POST_SUMMARY ?? 'false') + '').Trim().ToLowerInvariant()
$PostSummaryComment = @('1','true','yes','on') -contains $PostSummaryRaw
$CommentDelay     = [double]($env:COMMENT_DELAY_SECONDS ?? 0.5)
$ReviewApplyTo    = $env:REVIEW_APPLY_TO ?? '**'
# Optional git pathspec (semicolon-separated) that scopes the diff itself.
# Used by local wrappers to review a subfolder without shadowing the diff at
# post-processing time. Empty = review the full diff.
$ReviewPathSpec   = ($env:REVIEW_PATH_SPEC ?? '').Trim()
$ReviewOutputDirRaw = $env:REVIEW_OUTPUT_DIR ?? (Join-Path ([IO.Path]::GetTempPath()) (
    'bc-review-output-{0}' -f [guid]::NewGuid().ToString('N')
))
$ReviewOutputDir  = [IO.Path]::GetFullPath($ReviewOutputDirRaw)
$BaseBranch       = $env:BASE_BRANCH ?? 'main'
$AgentLabelRaw    = ($env:COPILOT_REVIEW_AGENT_LABEL ?? '').Trim()
$AgentSemVerRaw   = ($env:COPILOT_REVIEW_AGENT_VERSION ?? '').Trim()
$AgentDateRaw     = ($env:COPILOT_REVIEW_AGENT_RELEASE_DATE ?? '').Trim()
$AgentVersionRaw  = ($env:COPILOT_REVIEW_AGENT_RELEASE_VERSION ?? '').Trim()
$AgentCommentDocUrlRaw = ($env:AGENT_COMMENT_DOC_URL ?? '').Trim()
$AnalysisWorkspace = $env:REVIEW_TARGET_WORKSPACE ?? (Join-Path (Split-Path -Parent $TrustedWorkspace) 'review-target')
# Review source. 'pr' (default) fetches the PR head from origin into a detached
# worktree (GitHub-hosted review). 'local' reviews a caller-provided worktree
# ($AnalysisWorkspace / REVIEW_TARGET_WORKSPACE, already checked out at the head
# to review) against a local base ref ($BASE_REF), with no network fetch and no
# GitHub posting. Used by offline execution-based harnesses (e.g. BC-Bench).
$ReviewSource = (($env:REVIEW_SOURCE ?? 'pr') + '').Trim().ToLowerInvariant()
$BaseRef = ($env:BASE_REF ?? '').Trim()
$DiffBaseRef = if ($ReviewSource -eq 'local') { $BaseRef } else { "origin/$BaseBranch" }
# Diff range used for all change discovery. Default is three-dot
# ($base...HEAD): the diff from the merge-base of $base and HEAD, which is
# correct for normal branch/PR reviews. When the caller sets
# REVIEW_DIFF_STYLE=direct, use two-dot ($base..HEAD) instead. Two-dot is
# required when $base is a synthesized parent-less commit (e.g. Existing-mode
# whole-tree review against an empty base), which has no merge-base with HEAD
# and would make three-dot fail with "no merge base".
$DiffRange = if ((($env:REVIEW_DIFF_STYLE ?? '') + '').Trim().ToLowerInvariant() -eq 'direct') { "$DiffBaseRef..HEAD" } else { "$DiffBaseRef...HEAD" }
$SummaryMarker    = '<!-- copilot-pr-review-summary -->'
$BaseUrl          = "$GitHubApiUrl/repos/$Repository"

$AgentOutputFile  = 'agent-output.txt'
$CopilotOtelPath  = if ($ReviewPhase -eq 'post') {
    $null
} else {
    Join-Path ([System.IO.Path]::GetTempPath()) (
        'bc-al-review-copilot-otel-{0}.jsonl' -f [guid]::NewGuid().ToString('N')
    )
}
$ReviewStartedAt  = [DateTime]::UtcNow

# Deterministic file the model writes its final JSON findings-report to, inside
# the Copilot CLI working directory ($BCQualityRoot). The CLI renders tool/shell
# output as a human TUI and truncates large blocks ("… N lines"), so a report
# echoed to the terminal can be silently cut off and lost to stdout scraping.
# Harvesting the report from this file instead makes result capture reliable.
$ReportFileName   = '_review-report.json'

# Role-specific findings-report contracts derived from BCQuality's shared schema
# (see New-FindingsReportRoleSchemas). Leaves generate against the leaf schema;
# root consolidation generates against the root schema.
$LeafReportSchemaFileName = '_review-findings-report.leaf.schema.json'
$RootReportSchemaFileName = '_review-findings-report.root.schema.json'

# Working directory for the Copilot CLI and the home of per-run artifacts.
$AgentWorkDir = $ReviewOutputDir
$ReviewDataRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'bc-al-review-data-{0}' -f [guid]::NewGuid().ToString('N')
)
$ReviewDiffFileName = '_review-diff.patch'
$reviewDataCleanupPath = $ReviewDataRoot
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-Item -LiteralPath $reviewDataCleanupPath -Recurse -Force -ErrorAction SilentlyContinue
}.GetNewClosure()

# Severity taxonomy used by the comment renderer and the MINIMUM_SEVERITY gate.
# Lower rank = more severe. BCQuality emits blocker/major/minor/info; we map
# into this taxonomy so the existing comment-format precedent is preserved.
$SeverityOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
$BCQualitySeverityMap = @{ blocker = 'Critical'; major = 'High'; minor = 'Medium'; info = 'Low' }

# Legacy fallback mapping for BCQuality refs that predate findings[].domain.
# Current producers own their human-readable labels, so new domains must not be
# duplicated here. Unmapped legacy sub-skills fall back to Other.
$DomainMap = @{
    'al-security-review'     = 'Security'
    'al-privacy-review'      = 'Privacy'
    'al-performance-review'  = 'Performance'
    'al-style-review'        = 'Style'
    'al-ui-review'           = 'Accessibility'
    'al-upgrade-review'      = 'Upgrade'
    'al-code-review'         = 'Other'  # super-skill rollups with no nested origin
    # Findings the agent surfaced from its own judgement when no BCQuality
    # knowledge article directly backs the issue. BCQuality is an additive
    # knowledge layer, not the sole source of findings; the agent may emit
    # these with `from-sub-skill: "agent"` (or `knowledge-backed: false`).
    'agent'                  = 'Agent'
}

$script:LastParsingErrors = [System.Collections.Generic.List[string]]::new()
$script:FilterReport      = $null   # populated from BCQUALITY_ROOT/_filter-report.json
$script:BCQualityWebRepoUrl = $null # cached BCQuality web URL for reference links
$script:AgentTranscript   = ''      # interleaved Copilot CLI transcript (set by Invoke-CopilotCli)
$script:CopilotOtelRecords = $null  # cached after the raw temporary JSONL is deleted
$script:CopilotOtelMalformedRecords = 0
$script:LastCopilotInvocationMetrics = $null
$script:CurrentCopilotInvocationStartedAt = $null
$script:ReviewProcessTelemetry = [System.Collections.Generic.List[object]]::new()
$script:ReviewPlanIds = @()
$script:ReviewPlanSourceSnapshot = ''
$script:ReviewRunCompletedAt = $null
$script:CopilotExecutable = $null
$script:ObservedCopilotCliVersion = $null
$script:CopilotCliCompatibility = $null

# Load private helpers into this script scope. These remain dot-sourced until
# their shared state is replaced with explicit context objects.
$ReviewHelperScripts = @(
    'LoggingAndValidation.ps1'
    'GitHub.ps1'
    'Git.ps1'
    'FindingPlacement.ps1'
    'BCQualityContextAndMetrics.ps1'
    'ReviewExecution.ps1'
    'CopilotCli.ps1'
    'ReportParsing.ps1'
    'FindingDeduplication.ps1'
    'CommentPublishing.ps1'
    'Artifacts.ps1'
)
foreach ($reviewHelperScript in $ReviewHelperScripts) {
    . (Join-Path (Join-Path $PSScriptRoot 'private') $reviewHelperScript)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Assert-Config

$AgentLabel          = Resolve-AgentLabel
$AgentCommentDocUrl  = Resolve-AgentCommentDocUrl
$AgentVersion        = Resolve-AgentVersion
# Resolving the iteration reads existing PR comments, for which the generate
# phase holds no token; only the posting phases need it.
$ReviewIteration     = if ($ReviewPhase -eq 'generate' -or $ReviewSource -eq 'local') { 0 } else { Resolve-ReviewIteration }
$script:FilterReport = Import-FilterReport

# --- Configuration banner ---------------------------------------------------
Write-Host ''
Write-Host "Copilot PR Review — phase $ReviewPhase, iteration $ReviewIteration"
Write-LogPhaseDetail "PR:        $Repository#$PrNumber @ $PrHeadSha"
Write-LogPhaseDetail "Base:      $BaseBranch"
$modelDisplay = if ($CopilotModel) {
    $CopilotModel
} else {
    $resolvedDefault = $null
    $settingsPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot/settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settingsJson = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
            $settingsObj = $settingsJson | ConvertFrom-Json -ErrorAction Stop
            if ($settingsObj.PSObject.Properties.Match('model').Count -gt 0) {
                $modelValue = ($settingsObj.model + '').Trim()
                if ($modelValue) { $resolvedDefault = $modelValue }
            }
        } catch {
            # Best-effort; leave $resolvedDefault as $null.
            Write-Verbose "Could not read default model from ${settingsPath}: $_"
        }
    }
    if ($resolvedDefault) { "(default: $resolvedDefault)" } else { '(default: unknown)' }
}
Write-LogPhaseDetail "Model:     $modelDisplay"
Write-LogPhaseDetail "Leaves:    $LeafModel ($LeafExecution, max concurrency $MaxLeafConcurrency)"
if ($script:ObservedCopilotCliVersion) {
    Write-LogPhaseDetail "Copilot CLI: requested $CopilotCliVersion; startup-probed $script:ObservedCopilotCliVersion ($($script:CopilotCliCompatibility.otel_cli_version) OTel CLI version)"
}
Write-LogPhaseDetail "Agent:     $AgentLabel v$AgentVersion"
Write-LogPhaseDetail "Severity:  knowledge≥$MinimumSeverity, agent≥$AgentMinimumSeverity (max $MaxFindings findings/domain)"
Write-LogPhaseDetail "BCQuality: $BCQualityRoot @ v$BCQualityVersion"
Write-Host ''

# Clear stale per-run artifacts from the installed BCQuality plugin BEFORE the
# Discovery phase writes this run's worklist; the cleanup matches _review-*, so
# running it after Discovery (as before) deleted the freshly written changed-file
# manifest and object index, leaving a read-only generate agent with no worklist.
# Post never writes these artifacts, so guard on phase.
if ($ReviewPhase -ne 'post') {
    Clear-CopilotMetricsArtifacts `
        -AgentWorkDir $AgentWorkDir `
        -OutputDir $ReviewOutputDir `
        -OtelPath $CopilotOtelPath
    Clear-BCQualityRunArtifacts
    $staleLeafResults = Join-Path $ReviewOutputDir 'leaf-results'
    if (Test-Path -LiteralPath $staleLeafResults -PathType Container) {
        Remove-Item -LiteralPath $staleLeafResults -Recurse -Force
    }
}

# --- Phase 1: Discovery -----------------------------------------------------
Write-LogGroup 'Discovery'
if ($ReviewSource -eq 'local') {
    Write-Host "Local review: using provided worktree at $AnalysisWorkspace (base $DiffBaseRef); skipping PR fetch."
}
else {
    New-PrAnalysisWorktree
}

Write-Host "Fetching changed files via git diff ($DiffRange)"
$changedFileNames = @(Get-GitChangedFiles)
Write-Host "Found $($changedFileNames.Count) changed file(s)"
# The changed-file manifest and object index are inputs to the Copilot CLI /
# leaf sub-skills and are written into BCQUALITY_ROOT, which is only set in the
# generate/all phases (the publish/post job never installs BCQuality). Skip them
# in post to avoid Join-Path binding against a null $BCQualityRoot.
if ($ReviewPhase -ne 'post') {
    $null = New-Item -ItemType Directory -Path $AgentWorkDir -Force
    New-ReviewDataProjection
    Save-ReviewDiff
    $changedFilesManifest = Join-Path $AgentWorkDir '_review-changed-files.txt'
    Set-Content -LiteralPath $changedFilesManifest -Value $changedFileNames -Encoding UTF8
    Write-LogPhaseDetail "Changed-file manifest written to $changedFilesManifest"
    Initialize-FindingsConsumerContext -SourcePaths $changedFileNames

    # Shared object index: pre-compute the AL object inventory ONCE so leaf
    # sub-skills can locate objects without each re-grepping the whole tree
    # (cuts the cached re-ingestion cost that dominates large runs).
    $objectIndexPath = Join-Path $AgentWorkDir '_review-object-index.txt'
    $objHeaderRe = '^\s*(tableextension|pageextension|enumextension|permissionsetextension|reportextension|table|page|codeunit|report|xmlport|query|enum|interface|controladdin|permissionset|profile|entitlement|dotnet)\b'
    $objIndexLines = New-Object System.Collections.Generic.List[string]
    foreach ($cf in $changedFileNames) {
        if ($cf -notmatch '\.al$') { continue }
        $objFull = Join-Path $AnalysisWorkspace $cf
        if (-not (Test-Path -LiteralPath $objFull)) { continue }
        try {
            foreach ($line in [System.IO.File]::ReadLines($objFull)) {
                $t = $line.Trim()
                if ($t -and $t -match $objHeaderRe) { $objIndexLines.Add("$cf`t$t"); break }
            }
        }
        catch {
            Write-Verbose "Could not index AL object header from '$cf': $($_.Exception.Message)"
        }
    }
    Set-Content -LiteralPath $objectIndexPath -Value $objIndexLines -Encoding UTF8
    Write-LogPhaseDetail "Object index written to $objectIndexPath ($($objIndexLines.Count) objects)"
}
$displayCap = 50
$displayFiles = @($changedFileNames | Select-Object -First $displayCap)
foreach ($cf in $displayFiles) { Write-LogPhaseDetail "- $cf" }
if ($changedFileNames.Count -gt $displayCap) {
    Write-LogPhaseDetail "… and $($changedFileNames.Count - $displayCap) more"
}

$changedFileSet = @{}
foreach ($filename in $changedFileNames) {
    $normalized = ($filename -replace '\\', '/')
    if ($normalized) { $changedFileSet[$normalized] = $true }
}

# Line maps place inline comments; only the posting phases consume them.
$lineMaps = @{}
if ($ReviewPhase -ne 'generate') {
    foreach ($filename in $changedFileNames) {
        $patch = Get-GitFilePatch -FilePath $filename
        if ($patch) { $lineMaps[$filename] = Build-LineMap -Patch $patch }
    }
}

# Task context feeds each leaf process (generate) and is also persisted as a
# review artifact. Build-TaskContext re-parses the BCQuality config and
# Save-TaskContext writes into BCQUALITY_ROOT, both of which are only meaningful
# in the generate/all phases; skip them entirely in post.
$taskContext = $null
if ($ReviewPhase -ne 'post') {
    $taskContext = Build-TaskContext
    $null = Save-TaskContext -TaskContext $taskContext
    Initialize-FindingsReportRoleSchemas
}
Pop-LogGroup

# --- Phase 2: Agent run (generate) or load saved output (post) ---------------
if ($ReviewPhase -ne 'post') {
    Write-LogGroup 'Agent run (Copilot CLI, streaming)'
    Write-Host '--- Bootstrapping Copilot agent against BCQuality ---'
    $enabledLayers   = @($taskContext['enabled-layers'])
    $disabledSkills  = @($taskContext['disabled-skills'])
    if ($enabledLayers.Count -gt 0)  { Write-LogPhaseDetail "Enabled layers:  $($enabledLayers -join ', ')" }
    if ($disabledSkills.Count -gt 0) { Write-LogPhaseDetail "Disabled skills: $($disabledSkills -join ', ')" }
    $leafPlan = @(Get-ReviewLeafPlan)
    Write-LogPhaseDetail "Resolved $($leafPlan.Count) ordered review leaves from BCQuality's generated skill index."
    Save-ReviewRunManifest -Status running
    $leafResults = @(Invoke-DeterministicLeafReviews -Plan $leafPlan)
    $reviewCompletionStatus = Assert-UsableLeafReviewCoverage -Plan $leafPlan -LeafResults $leafResults
    Write-LogPhaseDetail "$($leafResults.Count) leaf process(es) produced usable reports; $(@($script:FailedLeafReviews).Count) failed. Starting root consolidation on $CopilotModel."
    $prompt = Build-ConsolidationPrompt `
        -LeafResults $leafResults `
        -FailedLeaves $script:FailedLeafReviews
    foreach ($relativePath in @('.github', '.agents', '.claude', 'AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
        $candidate = Join-Path $AgentWorkDir $relativePath
        if (Test-Path -LiteralPath $candidate) {
            Remove-Item -LiteralPath $candidate -Recurse -Force
        }
    }
    $rootStartedAt = [DateTime]::UtcNow
    try {
        $output = Invoke-CopilotCli -Prompt $prompt
        Assert-CopilotInvocationMetrics `
            -Metrics $script:LastCopilotInvocationMetrics `
            -RequestedModel $CopilotModel `
            -InvocationLabel 'Root consolidation'
        Assert-RequestedLeafModelObserved
    }
    catch {
        $rootFailure = $_
        Add-ReviewProcessTelemetry `
            -Role root `
            -Ordinal ($leafPlan.Count + 1) `
            -SkillId 'al-code-review' `
            -RequestedModel $CopilotModel `
            -Status failed `
            -StartedAt $rootStartedAt `
            -CompletedAt ([DateTime]::UtcNow) `
            -Metrics $script:LastCopilotInvocationMetrics `
            -ExitCode $null `
            -FailureReason $rootFailure.Exception.Message
        Save-ReviewRunManifest -Status failed -FailureReason $rootFailure.Exception.Message
        throw $rootFailure
    }
    Pop-LogGroup

    # Prefer the structured report file the model wrote to its working directory.
    # The Copilot CLI renders shell/tool output as a human TUI and truncates
    # large blocks ("… N lines"), so a findings-report echoed to the terminal
    # can be silently cut off mid-JSON and lost to stdout scraping. The bootstrap
    # prompt directs the model to also write the complete report to
    # $ReportFileName in $BCQualityRoot; when present, that file is the
    # authoritative, untruncated source and supersedes the scraped stdout.
    $reportFilePath = Join-Path $AgentWorkDir $ReportFileName
    if (Test-Path -LiteralPath $reportFilePath) {
        $reportContent = Get-Content -LiteralPath $reportFilePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($reportContent)) {
            # The agent occasionally writes POSIX shell-escaped single quotes
            # ('\'') into suggested-code, which is invalid JSON. Normalize the
            # on-disk report so every downstream consumer reads valid JSON: this
            # process's parser AND the local-review wrapper that copies the file
            # to its OutputDir for BC-Bench (which never runs this parser).
            $normalizedReport = Repair-ShellEscapedQuotes -Text $reportContent
            if ($normalizedReport -ne $reportContent) {
                Set-Content -LiteralPath $reportFilePath -Value $normalizedReport -Encoding UTF8
                Write-LogPhaseDetail "Normalized shell-escaped quotes in '$reportFilePath'."
                $reportContent = $normalizedReport
            }
            Write-LogPhaseDetail "Harvested structured report from '$reportFilePath' ($($reportContent.Length) chars); superseding scraped stdout."
            $output = $reportContent
        } else {
            Write-LogNotice 'Empty report file' "'$reportFilePath' exists but is empty; falling back to scraped stdout."
        }
    } else {
        Write-LogNotice 'No report file' "Model did not write '$reportFilePath'; falling back to scraped stdout parsing."
    }

    try {
        $consolidatedReport = Assert-ConsolidatedReport -ReportText $output -Plan $leafPlan
    }
    catch {
        $rootFailure = $_
        Add-ReviewProcessTelemetry `
            -Role root `
            -Ordinal ($leafPlan.Count + 1) `
            -SkillId 'al-code-review' `
            -RequestedModel $CopilotModel `
            -Status failed `
            -StartedAt $rootStartedAt `
            -CompletedAt ([DateTime]::UtcNow) `
            -Metrics $script:LastCopilotInvocationMetrics `
            -ExitCode 0 `
            -ReportPath $(if (Test-Path -LiteralPath $reportFilePath -PathType Leaf) { $reportFilePath } else { $null }) `
            -FailureReason $rootFailure.Exception.Message
        Save-ReviewRunManifest -Status failed -FailureReason $rootFailure.Exception.Message
        throw $rootFailure
    }
    Add-ReviewProcessTelemetry `
        -Role root `
        -Ordinal ($leafPlan.Count + 1) `
        -SkillId 'al-code-review' `
        -RequestedModel $CopilotModel `
        -Status completed `
        -StartedAt $rootStartedAt `
        -CompletedAt ([DateTime]::UtcNow) `
        -Metrics $script:LastCopilotInvocationMetrics `
        -ExitCode 0 `
        -ReportPath $reportFilePath
    $reviewCompletionStatus = Get-ConsolidatedReviewStatus `
        -Plan $leafPlan `
        -LeafResults $leafResults `
        -Report $consolidatedReport
    Save-ReviewRunManifest `
        -Status $reviewCompletionStatus `
        -FailureReason $(if ($reviewCompletionStatus -eq 'failed') { [string]$consolidatedReport.'outcome-reason' } else { $null })

    # Persist the raw agent output (plus transcript and filter report) so the
    # separate, write-capable publish phase can post findings without the
    # tool-enabled model process ever holding a write-scoped token.
    New-Item -Path $ReviewOutputDir -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ReviewOutputDir $AgentOutputFile) -Value $output -Encoding UTF8
    if ($script:AgentTranscript) {
        Set-Content -LiteralPath (Join-Path $ReviewOutputDir 'agent-transcript.log') -Value $script:AgentTranscript -Encoding UTF8
    }
    if ($BCQualityRoot) {
        $srcFilterReport = Join-Path $BCQualityRoot '_filter-report.json'
        if (Test-Path $srcFilterReport) {
            Copy-Item -LiteralPath $srcFilterReport -Destination (Join-Path $ReviewOutputDir '_filter-report.json') -Force
        }
    }

    if ($ReviewPhase -eq 'generate') {
        Save-CurrentCopilotRunMetrics
        Write-LogNotice 'Generate phase complete' "Saved agent output to $AgentOutputFile; posting deferred to the publish phase."
        Write-Host 'Review (generate phase) complete.'
        return
    }
} else {
    Write-LogGroup 'Load agent output'
    $outputPath = Join-Path $ReviewOutputDir $AgentOutputFile
    if (-not (Test-Path $outputPath)) {
        throw "REVIEW_PHASE=post requires '$outputPath' from the generate phase, but it was not found."
    }
    $output = Get-Content -LiteralPath $outputPath -Raw
    Write-Host "Loaded saved agent output from $outputPath ($($output.Length) chars)."
    Pop-LogGroup
}

# --- Phase 3: Parse & filter ------------------------------------------------
Write-LogGroup 'Parse & filter'
$report = ConvertFrom-BCQualityReport -Output $output
Write-Host "Outcome: $($report.Outcome). Findings parsed: $($report.Findings.Count)"
if ($report.OutcomeReason) { Write-LogPhaseDetail "Reason: $($report.OutcomeReason)" }
Write-FindingsBreakdown -Findings $report.Findings
Write-SuggestedCodeDiagnostics -Findings $report.Findings
Write-ConsumedBCQualityLog -Report $report

Write-LogPhaseDetail "Deterministic execution verified: $($report.SubResultCount) ordered leaf sub-results followed by one root consolidation process."

$preFilterCount = $report.Findings.Count
$report.Findings = @(Group-RegionalFindings -Findings $report.Findings)
$collapsed = $preFilterCount - $report.Findings.Count
if ($collapsed -gt 0) {
    Write-LogPhaseDetail "Regional duplicates collapsed: $collapsed"
}
Pop-LogGroup

Save-ReviewArtifacts `
    -RawOutput $output `
    -Report $report `
    -ParseErrors $script:LastParsingErrors `
    -TaskContext $taskContext `
    -Transcript $script:AgentTranscript

if ($FailOnParseError -and $report.Outcome -eq 'failed' -and $script:LastParsingErrors.Count -gt 0) {
    $errorPreview = ($script:LastParsingErrors | Select-Object -First 3) -join ' || '
    Write-LogErr 'Review failed' "Copilot output JSON parsing failed. Parse errors: $errorPreview"
    throw "Copilot output JSON parsing failed; refusing to post an empty review summary. Set COPILOT_REVIEW_FAIL_ON_PARSE_ERROR=false to bypass. Parse errors: $errorPreview"
}

if ($ReviewSource -eq 'local') {
    Save-CurrentCopilotRunMetrics
    Write-Host "Local review complete: findings saved to $ReviewOutputDir; posting skipped (REVIEW_SOURCE=local)."
    return
}

# --- Phase 4: Post comments -------------------------------------------------
Write-LogGroup 'Post comments'
$domainSummary = Get-OrdinalDictionary
$shouldPostFindings = $report.Outcome -in @('completed', 'partial')

if ($shouldPostFindings -and $report.Findings.Count -gt 0) {
    $domainSummary = Publish-FindingsByDomain -Findings $report.Findings `
        -LineMaps $lineMaps -ChangedFileSet $changedFileSet
} elseif ($report.Outcome -in @('not-applicable', 'no-knowledge')) {
    Write-Host "Outcome '$($report.Outcome)' — no findings posted; updating summary only."
} elseif ($report.Outcome -eq 'failed') {
    Write-Warning "Outcome 'failed' — no findings posted; updating summary only."
} else {
    Write-Host 'No findings to post.'
}

$summaryBody = Build-SummaryBody `
    -Outcome $report.Outcome `
    -OutcomeReason $report.OutcomeReason `
    -DomainSummary $domainSummary `
    -Suppressed $report.Suppressed `
    -SkippedSubSkills $report.SkippedSubSkills `
    -FailedSubSkills $report.FailedSubSkills `
    -FilterReport $script:FilterReport

if ($PostSummaryComment) {
    Set-SummaryComment -Body $summaryBody
} else {
    Write-Host 'Summary comment disabled (COPILOT_REVIEW_POST_SUMMARY not set); posting inline findings only.'
}
Pop-LogGroup

# --- Finalize ---------------------------------------------------------------
Save-CurrentCopilotRunMetrics
$totalPosted = 0
foreach ($entry in $domainSummary.Values) { $totalPosted += [int]$entry.inline + [int]$entry.fallback }
$domainCount = $domainSummary.Count

if ($report.Outcome -eq 'failed') {
    Write-LogErr 'Review failed' ("Review outcome was 'failed'. " + ($report.OutcomeReason ?? ''))
    throw "Review outcome was 'failed'. Reason: $($report.OutcomeReason)"
} elseif ($report.Outcome -eq 'partial') {
    Write-LogWarn 'Review partial' "Posted $totalPosted finding(s) across $domainCount domain(s). $($report.OutcomeReason)"
} elseif ($report.Outcome -in @('not-applicable', 'no-knowledge')) {
    Write-LogNotice 'Review complete (no findings)' "Outcome: $($report.Outcome). $($report.OutcomeReason)"
} else {
    Write-LogNotice 'Review complete' "Posted $totalPosted finding(s) across $domainCount domain(s)."
}

Write-Host 'Review complete.'
