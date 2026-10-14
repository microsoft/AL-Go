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
    [string] $settingsJson = '',
    [Parameter(HelpMessage = "Path to the pull request event metadata")]
    [string] $metadataPath = '',
    [Parameter(HelpMessage = "Head SHA reported by the completed intake workflow")]
    [string] $workflowHeadSha = '',
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
    [Parameter(HelpMessage = "Token with read access to a private BCQuality marketplace")]
    [string] $bcqualityToken = '',
    [Parameter(HelpMessage = "GitHub repository URL containing the BCQuality marketplace")]
    [string] $bcqualityRepo = 'https://github.com/microsoft/BCQuality',
    [Parameter(HelpMessage = "BCQuality content version")]
    [string] $bcqualityVersion = '1.7',
    [Parameter(HelpMessage = "Path to the installed and filtered BCQuality plugin")]
    [string] $bcqualityRoot = '',
    [Parameter(HelpMessage = "Compatibility-validated Copilot CLI version")]
    [string] $copilotCliVersion = '1.0.88'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0

function Write-ReviewOutput {
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowEmptyString()][string] $Value
    )

    if ($env:GITHUB_OUTPUT) {
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
}

function Enable-PowerShellYaml {
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module powershell-yaml -Scope CurrentUser -Force -AllowClobber
    }
}

function Invoke-ContextPhase {
    if ([string]::IsNullOrWhiteSpace($settingsJson)) {
        throw 'settingsJson is required for the context phase.'
    }
    if ([string]::IsNullOrWhiteSpace($metadataPath) -or -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Pull request metadata was not found at '$metadataPath'."
    }

    $settings = $settingsJson | ConvertFrom-Json
    $metadata = Get-Content -LiteralPath $metadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $owner = [string] $metadata.pull_request.user.login
    $excludedOwners = @($settings.excludedOwners)
    $eligible = -not $metadata.pull_request.draft -and $owner -notin $excludedOwners
    $number = [string] $metadata.pull_request.number
    $headSha = [string] $metadata.pull_request.head.sha
    $targetBranch = [string] $metadata.pull_request.base.ref
    $resolvedBCQualityRepo = [string] $settings.bcqualityRepo
    $resolvedBCQualityVersion = [string] $settings.bcqualityVersion

    if ([string]::IsNullOrWhiteSpace($workflowHeadSha) -or $headSha -ne $workflowHeadSha) {
        throw 'Pull request head SHA does not match the triggering workflow run.'
    }
    if ([string]::IsNullOrWhiteSpace($resolvedBCQualityRepo) -or $resolvedBCQualityVersion -notmatch '\A[0-9]+\.[0-9]+\z') {
        throw 'CodeReviewAgent.bcqualityRepo and a major.minor CodeReviewAgent.bcqualityVersion are required.'
    }

    Write-ReviewOutput -Name eligible -Value $eligible.ToString().ToLowerInvariant()
    Write-ReviewOutput -Name model -Value ([string] $settings.model)
    Write-ReviewOutput -Name leafModel -Value ([string] $settings.leafModel)
    Write-ReviewOutput -Name prNumber -Value $number
    Write-ReviewOutput -Name headSha -Value $headSha
    Write-ReviewOutput -Name baseRef -Value $targetBranch
    Write-ReviewOutput -Name bcqualityRepo -Value $resolvedBCQualityRepo
    Write-ReviewOutput -Name bcqualityVersion -Value $resolvedBCQualityVersion
}

function Assert-CopilotCliVersion {
    if ($copilotCliVersion -notmatch '\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*))?\z') {
        throw "copilotCliVersion must be an exact semantic version; received '$copilotCliVersion'."
    }

    $policy = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'copilot-cli-compatibility.psd1') -ErrorAction Stop
    if ($policy.schema_version -ne 1 -or -not $policy.supported_versions.ContainsKey($copilotCliVersion)) {
        throw "Copilot CLI version '$copilotCliVersion' has not been compatibility-validated by the action policy."
    }
}

function Invoke-SetupBCQuality {
    param(
        [Parameter(Mandatory)] $Configuration
    )

    $repoUri = [Uri] $Configuration.bcquality.repo
    if ($repoUri.Host -ne 'github.com') {
        throw "BCQuality marketplace must be hosted on github.com; received '$($Configuration.bcquality.repo)'."
    }
    $marketplace = $repoUri.AbsolutePath.Trim('/')
    if ($marketplace -notmatch '^[^/]+/[^/]+$') {
        throw "BCQuality marketplace URL must identify one owner/repository; received '$($Configuration.bcquality.repo)'."
    }
    $pluginVersion = [string] $Configuration.bcquality['plugin-version']
    if (-not $pluginVersion) {
        throw 'bcquality.plugin-version is required for plugin identity validation.'
    }

    $setupOutput = [System.IO.Path]::GetTempFileName()
    $originalOutput = $env:GITHUB_OUTPUT
    try {
        $env:GITHUB_OUTPUT = $setupOutput
        $setupToken = if ($marketplace -eq 'microsoft/BCQuality') { '' } else { $bcqualityToken }
        & (Join-Path $PSScriptRoot '..\SetupBCQuality\SetupBCQuality.ps1') `
            -marketplace $marketplace `
            -marketplaceRef ([string] $Configuration.bcquality.ref) `
            -expectedPluginVersion $pluginVersion `
            -enabledLayers (@($Configuration['enabled-layers']) -join ',') `
            -disabledSkills (@($Configuration['disabled-skills']) -join ',') `
            -knowledgeAllow (@($Configuration.knowledge.allow) -join ',') `
            -knowledgeDeny (@($Configuration.knowledge.deny) -join ',') `
            -token $setupToken

        $outputs = @{}
        Get-Content -LiteralPath $setupOutput -Encoding UTF8 | ForEach-Object {
            $pair = $_ -split '=', 2
            if ($pair.Count -eq 2) {
                $outputs[$pair[0]] = $pair[1]
            }
        }
        return $outputs
    }
    finally {
        $env:GITHUB_OUTPUT = $originalOutput
        Remove-Item -LiteralPath $setupOutput -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-ReviewEnvironment {
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
    $env:COPILOT_REVIEW_AGENT_VERSION = ''
    $env:COPILOT_REVIEW_AGENT_RELEASE_DATE = ''
    $env:COPILOT_REVIEW_AGENT_RELEASE_VERSION = ''
}

function Invoke-PreparePhase {
    Assert-CopilotCliVersion
    Write-ReviewOutput -Name copilotCliVersion -Value $copilotCliVersion

    & npm install --global "@github/copilot@$copilotCliVersion"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install GitHub Copilot CLI $copilotCliVersion."
    }
    & copilot --version
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to execute GitHub Copilot CLI after installation.'
    }

    Enable-PowerShellYaml
    $configuration = & (Join-Path $PSScriptRoot 'scripts\Get-BCQualityConfig.ps1')
    if ($bcqualityVersion -notmatch '\A[0-9]+\.[0-9]+\z') {
        throw "bcqualityVersion must use major.minor format; received '$bcqualityVersion'."
    }
    $configuration.bcquality.repo = $bcqualityRepo
    $configuration.bcquality.ref = "v$bcqualityVersion"
    $configuration.bcquality.version = $bcqualityVersion
    $setup = Invoke-SetupBCQuality -Configuration $configuration
    if (-not $setup.pluginRoot) {
        throw 'SetupBCQuality did not return the plugin root.'
    }

    Write-ReviewOutput -Name bcqualityRoot -Value $setup.pluginRoot
    Write-ReviewOutput -Name filterReport -Value $setup.filterReport
}

function Invoke-GeneratePhase {
    if ([string]::IsNullOrWhiteSpace($bcqualityRoot) -or -not (Test-Path -LiteralPath $bcqualityRoot -PathType Container)) {
        throw "The prepared BCQuality plugin was not found at '$bcqualityRoot'."
    }
    if ($bcqualityVersion -notmatch '\A[0-9]+\.[0-9]+\z') {
        throw "bcqualityVersion must use major.minor format; received '$bcqualityVersion'."
    }

    Enable-PowerShellYaml
    Initialize-ReviewEnvironment
    $env:REVIEW_PHASE = 'generate'
    $env:GH_TOKEN = $token
    $env:BCQUALITY_ROOT = $bcqualityRoot
    $env:BCQUALITY_VERSION = $bcqualityVersion
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
    Enable-PowerShellYaml
    Initialize-ReviewEnvironment
    $env:REVIEW_PHASE = 'post'
    $env:BCQUALITY_VERSION = $bcqualityVersion
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
