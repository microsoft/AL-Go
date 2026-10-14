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
        [string]$settings.version -notmatch '\A[0-9]+\.[0-9]+\z' -or
        [string]::IsNullOrWhiteSpace([string] $settings.pluginVersion)) {
        throw 'BCQuality.marketplaceRepo, BCQuality.pluginVersion, and a major.minor BCQuality.version are required.'
    }
    if (@($settings.enabledLayers).Count -eq 0) {
        throw 'BCQuality.enabledLayers must contain at least one layer.'
    }
    if (-not ($settings.knowledge -is [System.Collections.IDictionary]) -or
        -not ($settings.taskContext -is [System.Collections.IDictionary])) {
        throw 'BCQuality.knowledge and BCQuality.taskContext are required.'
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

    $settings = $codeReviewSettingsJson | ConvertFrom-Json
    $bcqualitySettings = Get-BCQualitySettings
    $metadata = Get-Content -LiteralPath $metadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $owner = [string] $metadata.pull_request.user.login
    $excludedOwners = @($settings.excludedOwners)
    $eligible = -not $metadata.pull_request.draft -and $owner -notin $excludedOwners
    $number = [string] $metadata.pull_request.number
    $headSha = [string] $metadata.pull_request.head.sha
    $targetBranch = [string] $metadata.pull_request.base.ref

    if ([string]::IsNullOrWhiteSpace($workflowHeadSha) -or $headSha -ne $workflowHeadSha) {
        throw 'Pull request head SHA does not match the triggering workflow run.'
    }

    Write-ReviewOutput -Name eligible -Value $eligible.ToString().ToLowerInvariant()
    Write-ReviewOutput -Name model -Value ([string] $settings.model)
    Write-ReviewOutput -Name leafModel -Value ([string] $settings.leafModel)
    Write-ReviewOutput -Name prNumber -Value $number
    Write-ReviewOutput -Name headSha -Value $headSha
    Write-ReviewOutput -Name baseRef -Value $targetBranch
    Write-ReviewOutput -Name bcqualitySettingsJson -Value ($bcqualitySettings | ConvertTo-Json -Compress -Depth 10)
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
        [Parameter(Mandatory)] $Settings
    )

    $marketplaceRepo = [string] $Settings.marketplaceRepo
    $version = [string] $Settings.version
    $repoUri = [Uri] $marketplaceRepo
    if ($repoUri.Host -ne 'github.com') {
        throw "BCQuality marketplace must be hosted on github.com; received '$marketplaceRepo'."
    }
    $marketplace = $repoUri.AbsolutePath.Trim('/')
    if ($marketplace -notmatch '^[^/]+/[^/]+$') {
        throw "BCQuality marketplace URL must identify one owner/repository; received '$marketplaceRepo'."
    }

    $setupOutput = [System.IO.Path]::GetTempFileName()
    $originalOutput = $env:GITHUB_OUTPUT
    try {
        $env:GITHUB_OUTPUT = $setupOutput
        $setupToken = if ($marketplace -eq 'microsoft/BCQuality') { '' } else { $bcqualityToken }
        & (Join-Path $PSScriptRoot '..\SetupBCQuality\SetupBCQuality.ps1') `
            -marketplace $marketplace `
            -marketplaceRef "v$version" `
            -expectedPluginVersion ([string] $Settings.pluginVersion) `
            -enabledLayers (@($Settings.enabledLayers) -join ',') `
            -disabledSkills (@($Settings.disabledSkills) -join ',') `
            -knowledgeAllow (@($Settings.knowledge.allow) -join ',') `
            -knowledgeDeny (@($Settings.knowledge.deny) -join ',') `
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
    $bcqualitySettings = Get-BCQualitySettings
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

    $setup = Invoke-SetupBCQuality -Settings $bcqualitySettings
    if (-not $setup.pluginRoot) {
        throw 'SetupBCQuality did not return the plugin root.'
    }

    Write-ReviewOutput -Name bcqualityRoot -Value $setup.pluginRoot
    Write-ReviewOutput -Name filterReport -Value $setup.filterReport
}

function Invoke-GeneratePhase {
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
