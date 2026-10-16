# ---------------------------------------------------------------------------
# Logging helpers
#
# The script emits a phased, GitHub-Actions-aware log so a follower can tag
# along during a review cycle. On CI we use `::group::` / `::endgroup::`
# folds and `::notice::` / `::warning::` / `::error::` annotations; locally
# (no GITHUB_ACTIONS) we degrade to plain prefixed lines.
# ---------------------------------------------------------------------------
$script:IsGitHubActions = (($env:GITHUB_ACTIONS ?? '') -eq 'true')

function Write-LogGroup {
    param([string] $Title)
    if ($script:IsGitHubActions) {
        Write-Host "::group::$Title"
    } else {
        Write-Host ''
        Write-Host "--- $Title ---"
    }
}

function Pop-LogGroup {
    if ($script:IsGitHubActions) {
        Write-Host '::endgroup::'
    } else {
        Write-Host '--- end ---'
    }
}

function Invoke-WithWorkflowCommandsSuspended {
    param([Parameter(Mandatory)][scriptblock] $Action)

    if (-not $script:IsGitHubActions) {
        & $Action
        return
    }

    $token = [guid]::NewGuid().ToString('N')
    Write-Host "::stop-commands::$token"
    try {
        & $Action
    }
    finally {
        Write-Host "::$($token)::"
    }
}

function Write-LogPhaseDetail {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Line', Justification = 'The logging callback consumes the line through dynamic scope.')]
    param([string] $Line)
    Invoke-WithWorkflowCommandsSuspended { Write-Host "  $Line" }
}

function Format-AnnotationMessage {
    param([string] $Message)
    # GitHub Actions workflow commands treat literal newlines as command
    # terminators; escape them per the spec so multi-line messages survive.
    # Encode '%' first so agent-supplied literal '%0A'/'%0D' cannot be replayed
    # as injected command terminators.
    return (($Message -replace '%', '%25') -replace "`r", '%0D') -replace "`n", '%0A'
}

function Write-LogNotice {
    param([string] $Title, [string] $Message)
    if ($script:IsGitHubActions) {
        Write-Host "::notice title=$Title::$(Format-AnnotationMessage $Message)"
    } else {
        Write-Host "[NOTICE] $Title — $Message"
    }
}

function Write-LogWarn {
    param([string] $Title, [string] $Message)
    if ($script:IsGitHubActions) {
        Write-Host "::warning title=$Title::$(Format-AnnotationMessage $Message)"
    } else {
        Write-Warning "$Title — $Message"
    }
}

function Write-LogErr {
    param([string] $Title, [string] $Message)
    if ($script:IsGitHubActions) {
        Write-Host "::error title=$Title::$(Format-AnnotationMessage $Message)"
    } else {
        Write-Host "[ERROR] $Title — $Message"
    }
}

function Format-Duration {
    param([TimeSpan] $Span)
    if ($Span.TotalHours -ge 1) {
        return ('{0:hh\:mm\:ss}' -f $Span)
    }
    return ('{0:mm\:ss}' -f $Span)
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
function Test-CopilotCliVersionFormat {
    param([Parameter(Mandatory)][string] $Version)

    return $Version -cmatch '\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*))?\z'
}

function Resolve-CopilotExecutable {
    $copilotCommand = Get-Command copilot.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $copilotCommand) {
        $copilotCommand = Get-Command copilot -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if (-not $copilotCommand -or -not $copilotCommand.Source) {
        throw 'Copilot CLI not found in PATH. Install the exact @github/copilot release selected by the runner workflow before running this script.'
    }

    return [string]$copilotCommand.Source
}

function New-CopilotProcessStartInfo {
    param(
        [Parameter(Mandatory)][string] $Executable,
        [string[]] $Arguments = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    if ([IO.Path]::GetExtension($Executable) -in @('.cmd', '.bat')) {
        $shimDirectory = Split-Path -Parent $Executable
        $loaderCandidates = @(
            (Join-Path $shimDirectory 'node_modules/@github/copilot/npm-loader.js')
            (Join-Path (Split-Path -Parent $shimDirectory) '@github/copilot/npm-loader.js')
        )
        $loader = $loaderCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $loader) {
            throw "Cannot find the npm Copilot loader for '$Executable'. Reinstall the pinned @github/copilot package."
        }
        $node = Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $startInfo.FileName = $node.Source
        $startInfo.ArgumentList.Add($loader)
    }
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    return $startInfo
}

function Invoke-CopilotVersionProbe {
    param([Parameter(Mandatory)][string] $Executable)

    $startInfo = New-CopilotProcessStartInfo -Executable $Executable -Arguments @('--version')
    $arguments = @($startInfo.ArgumentList)
    $output = @(& $startInfo.FileName @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Copilot CLI version probe failed for '$Executable' with exit code $LASTEXITCODE."
    }
    return $output
}

function Get-CopilotExecutableVersion {
    param([Parameter(Mandatory)][string] $Executable)

    $outputLines = @(
        Invoke-CopilotVersionProbe -Executable $Executable |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ }
    )
    $bannerLines = @($outputLines | Where-Object { $_ -cmatch '\AGitHub Copilot CLI ' })
    $bannerVersions = @(
        $bannerLines | ForEach-Object {
            if ($_ -cmatch '\AGitHub Copilot CLI (?<version>\S+)\.\z') {
                $Matches['version']
            }
        }
    )
    if (
        $bannerLines.Count -ne 1 -or
        $bannerVersions.Count -ne 1 -or
        -not (Test-CopilotCliVersionFormat -Version $bannerVersions[0])
    ) {
        $reported = if ($outputLines.Count -gt 0) { $outputLines -join ' | ' } else { '(no output)' }
        throw "Copilot CLI version probe for '$Executable' must return exactly one 'GitHub Copilot CLI <semantic-version>.' banner (for example 'GitHub Copilot CLI 1.0.88.'); received '$reported'."
    }

    return $bannerVersions[0]
}

function Initialize-CopilotCliRuntime {
    $executable = Resolve-CopilotExecutable
    $observedVersion = Get-CopilotExecutableVersion -Executable $executable
    $script:CopilotExecutable = $executable
    $script:ObservedCopilotCliVersion = $observedVersion
    if ($CopilotCliVersion -cne $observedVersion) {
        throw "COPILOT_REVIEW_CLI_VERSION '$CopilotCliVersion' does not match startup-probed Copilot CLI version '$observedVersion' from '$executable'."
    }
}

function Assert-Config {
    if ($ReviewPhase -notin @('all', 'generate', 'post')) {
        throw "Unsupported REVIEW_PHASE: $ReviewPhase (expected all | generate | post)"
    }
    $needsCli = $ReviewPhase -in @('all', 'generate')
    $needsPost = ($ReviewPhase -in @('all', 'post')) -and ($ReviewSource -ne 'local')

    if ($ReviewSource -notin @('pr', 'local')) { throw "Unsupported REVIEW_SOURCE: $ReviewSource (expected pr | local)" }
    if ($needsPost -and -not $GithubToken) { throw 'GITHUB_TOKEN is required for posting (REVIEW_PHASE all|post)' }
    if ($needsCli -and $ReviewSource -ne 'local' -and -not $CopilotToken) {
        throw 'GH_TOKEN is required for Copilot CLI authentication in PR review mode (REVIEW_PHASE all|generate)'
    }
    if ($ReviewSource -eq 'local') {
        if (-not $BaseRef) { throw 'BASE_REF is required when REVIEW_SOURCE=local (the base commit/ref to diff the worktree against)' }
        if ($ReviewPhase -eq 'post') { throw 'REVIEW_SOURCE=local does not support REVIEW_PHASE=post (local mode never posts to GitHub)' }
        if (-not (Test-Path $AnalysisWorkspace)) { throw "REVIEW_TARGET_WORKSPACE does not exist: $AnalysisWorkspace (local mode expects a pre-checked-out worktree at the head to review)" }
    }
    else {
        if ($PrNumber -eq 0) { throw 'PR_NUMBER is required' }
        if (-not $PrHeadSha) { throw 'PR_HEAD_SHA is required' }
        if ($PrHeadSha -notmatch '\A[a-fA-F0-9]{40}\z') {
            throw "PR_HEAD_SHA must be a full 40-character commit SHA; received '$PrHeadSha'."
        }
    }
    $null = & git check-ref-format "refs/heads/$BaseBranch" 2>&1
    if ($LASTEXITCODE -ne 0 -or $BaseBranch.StartsWith('-')) {
        throw "BASE_BRANCH is not a valid git branch name: '$BaseBranch'."
    }

    if ($needsCli) {
        $comparison = if ($IsWindows) {
            [StringComparison]::OrdinalIgnoreCase
        } else {
            [StringComparison]::Ordinal
        }
        $analysisPath = [IO.Path]::GetFullPath($AnalysisWorkspace).TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $outputPath = [IO.Path]::GetFullPath($ReviewOutputDir).TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $analysisPrefix = $analysisPath + [IO.Path]::DirectorySeparatorChar
        $outputPrefix = $outputPath + [IO.Path]::DirectorySeparatorChar
        if ($outputPath.StartsWith($analysisPrefix, $comparison) -or
            $analysisPath.StartsWith($outputPrefix, $comparison) -or
            $outputPath.Equals($analysisPath, $comparison)) {
            throw 'REVIEW_OUTPUT_DIR and REVIEW_TARGET_WORKSPACE must be disjoint so the Copilot working directory cannot inherit or expose untrusted repository configuration.'
        }
        if (-not $BCQualityRoot)   { throw 'BCQUALITY_ROOT is required (set by the runner workflow Setup BCQuality step)' }
        if (-not (Test-Path $BCQualityRoot)) {
            throw "BCQUALITY_ROOT does not exist: $BCQualityRoot"
        }
        if (-not (Test-Path (Join-Path $BCQualityRoot 'skills/entry.md'))) {
            throw "BCQuality plugin at $BCQualityRoot is missing skills/entry.md; check the configured marketplace and version."
        }
        if (-not $CopilotModel) {
            throw 'COPILOT_MODEL is required for deterministic root consolidation.'
        }
        if (-not (Test-CopilotCliVersionFormat -Version $CopilotCliVersion)) {
            throw 'COPILOT_REVIEW_CLI_VERSION must contain an exact semantic Copilot CLI version.'
        }
        if (-not $LeafModel) {
            throw 'COPILOT_REVIEW_LEAF_MODEL is required for deterministic leaf execution.'
        }
        if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
            throw 'PowerShell Test-Json is required for deterministic findings-report validation.'
        }
        $findingsSchema = Join-Path $BCQualityRoot 'schemas/findings-report.schema.json'
        if (-not (Test-Path -LiteralPath $findingsSchema -PathType Leaf)) {
            throw "Installed BCQuality plugin is missing the findings-report schema: $findingsSchema. BCQuality commit b74967bc5b7a454eae19d6a1250199afd869f064 or a newer ref is required (introduced by microsoft/BCQuality#182)."
        }
        Initialize-CopilotCliRuntime
        if ($CopilotCliTimeoutMinutes -lt 0) {
            throw "COPILOT_REVIEW_CLI_TIMEOUT_MINUTES must be 0 (unlimited) or a positive integer. Actual: $CopilotCliTimeoutMinutes"
        }
    }

    if (-not $SeverityOrder.ContainsKey($MinimumSeverity)) {
        throw "Unsupported MINIMUM_SEVERITY: $MinimumSeverity"
    }
    if (-not $SeverityOrder.ContainsKey($AgentMinimumSeverity)) {
        throw "Unsupported AGENT_MINIMUM_SEVERITY: $AgentMinimumSeverity"
    }
    if (-not (Test-Path $TrustedWorkspace)) {
        throw "Workspace not found: $TrustedWorkspace"
    }

    $null = (& git -C $TrustedWorkspace rev-parse --is-inside-work-tree 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Workspace is not a git repository: $TrustedWorkspace"
    }
}
