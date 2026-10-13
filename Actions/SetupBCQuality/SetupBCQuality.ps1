<#
.SYNOPSIS
Installs and physically filters the BCQuality Copilot plugin.
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "GitHub owner/repository containing the BCQuality marketplace")]
    [string] $marketplace = 'microsoft/BCQuality',
    [Parameter(HelpMessage = "Immutable BCQuality marketplace tag")]
    [string] $marketplaceRef = 'v1.7',
    [Parameter(HelpMessage = "Expected version from the BCQuality marketplace entry")]
    [string] $expectedPluginVersion = '0.2.0',
    [Parameter(HelpMessage = "Comma-separated BCQuality layers to retain")]
    [string] $enabledLayers = 'microsoft',
    [Parameter(HelpMessage = "Comma-separated repo-relative skill paths to remove")]
    [string] $disabledSkills = '',
    [Parameter(HelpMessage = "Comma-separated knowledge globs to retain; empty retains all enabled-layer knowledge")]
    [string] $knowledgeAllow = '',
    [Parameter(HelpMessage = "Comma-separated knowledge globs to remove")]
    [string] $knowledgeDeny = '',
    [Parameter(HelpMessage = "GitHub token with read access to a private marketplace repository")]
    [string] $token = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'SetupBCQuality.psm1' -Resolve) -Force -DisableNameChecking

$runnerEnvironment = if ($env:SETUP_BCQUALITY_RUNNER_ENVIRONMENT) { $env:SETUP_BCQUALITY_RUNNER_ENVIRONMENT } else { $env:RUNNER_ENVIRONMENT }
$pluginRoot = $env:SETUP_BCQUALITY_PLUGIN_ROOT
$copilotHome = $env:SETUP_BCQUALITY_COPILOT_HOME

if ($runnerEnvironment -ne 'github-hosted') {
    throw "SetupBCQuality supports only ephemeral GitHub-hosted runners because it filters the default plugin installation in place. Runner environment: '$runnerEnvironment'."
}

if ([string]::IsNullOrWhiteSpace($marketplace) -or $marketplace -notmatch '^[^/\s]+/[^#\s]+$') {
    throw "marketplace must use the GitHub owner/repository form. Received '$marketplace'."
}
if ([string]::IsNullOrWhiteSpace($marketplaceRef)) {
    throw 'marketplaceRef must be a non-empty immutable tag, or a branch for prototype testing.'
}
if ($marketplaceRef -match '^[0-9a-fA-F]{40}$') {
    throw 'Copilot CLI marketplace refs support branches and tags, not raw commit SHAs. Use an immutable BCQuality release tag.'
}
if ([string]::IsNullOrWhiteSpace($expectedPluginVersion)) {
    throw 'expectedPluginVersion must be specified.'
}

$layers = @(ConvertFrom-CsvSetting $enabledLayers)
$disabledSkillPaths = @(ConvertFrom-CsvSetting $disabledSkills)
$allowPatterns = @(ConvertFrom-CsvSetting $knowledgeAllow)
$denyPatterns = @(ConvertFrom-CsvSetting $knowledgeDeny)
$knownLayers = @('microsoft', 'community', 'custom')

if ($layers.Count -eq 0) {
    throw 'At least one enabled BCQuality layer is required.'
}
foreach ($layer in $layers) {
    if ($knownLayers -notcontains $layer) {
        throw "Unknown BCQuality layer '$layer'. Allowed values: $($knownLayers -join ', ')."
    }
}

if (-not $copilotHome) {
    $copilotHome = $env:COPILOT_HOME
}
if (-not $copilotHome) {
    $copilotHome = Join-Path $HOME '.copilot'
}

$sourceHash = ''
$sourceCommit = ''
$pluginVersion = $expectedPluginVersion
if (-not $pluginRoot) {
    $sourceCommit = Invoke-WithGitHubToken -Repository $marketplace -Token $token -ScriptBlock {
        Resolve-MarketplaceCommit -Repository $marketplace -Ref $marketplaceRef
    }
    Invoke-WithGitHubToken -Repository $marketplace -Token $token -ScriptBlock {
        & copilot plugin marketplace add "$marketplace#$marketplaceRef"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register BCQuality marketplace $marketplace#$marketplaceRef."
    }
    Invoke-WithGitHubToken -Repository $marketplace -Token $token -ScriptBlock {
        & copilot plugin install 'bcquality@bcquality'
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to install the BCQuality plugin.'
    }

    $config = Read-CopilotConfig -Path (Join-Path $copilotHome 'config.json')
    $installed = @($config.installedPlugins | Where-Object { $_.name -eq 'bcquality' -and $_.marketplace -eq 'bcquality' })
    if ($installed.Count -ne 1) {
        throw "Expected exactly one installed bcquality@bcquality plugin, found $($installed.Count)."
    }
    $plugin = $installed[0]
    $pluginVersion = [string] $plugin.version
    if ($pluginVersion -ne $expectedPluginVersion) {
        throw "Installed BCQuality plugin version '$pluginVersion' does not match expected version '$expectedPluginVersion'."
    }
    $pluginRoot = [string] $plugin.cache_path
    $sourceHash = [string] $plugin.source_sha
}

if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
    throw "Installed BCQuality plugin root not found: $pluginRoot"
}
$pluginRoot = (Resolve-Path -LiteralPath $pluginRoot).Path

foreach ($requiredPath in @(
    'skills/entry.md',
    'skills/read.md',
    'skills/do.md',
    'tools/Build-KnowledgeIndex.ps1',
    'tools/Build-SkillIndex.ps1'
)) {
    $fullPath = Resolve-SafePluginPath -Root $pluginRoot -RelativePath $requiredPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Installed BCQuality plugin is missing required file '$requiredPath'."
    }
}

$skillIndex = Join-Path $pluginRoot '_skill-index.json'
& (Join-Path $pluginRoot 'tools/Build-SkillIndex.ps1') -BCQualityRoot $pluginRoot -IndexPath $skillIndex | Out-Null
if (-not (Test-Path -LiteralPath $skillIndex -PathType Leaf)) {
    throw 'BCQuality skill-index generation failed.'
}

$removed = [System.Collections.Generic.List[object]]::new()

foreach ($layer in $knownLayers) {
    $knowledgeRoot = Join-Path $pluginRoot "$layer/knowledge"
    if (Test-Path -LiteralPath $knowledgeRoot -PathType Container) {
        Get-ChildItem -LiteralPath $knowledgeRoot -Recurse -File -Filter '*.md' | ForEach-Object {
            $relativePath = Get-RelativePluginPath -Root $pluginRoot -FullName $_.FullName
            $reason = ''
            if ($layers -notcontains $layer) {
                $reason = 'layer-disabled'
            }
            elseif ($allowPatterns.Count -gt 0 -and -not @($allowPatterns | Where-Object { Test-GlobMatch -Path $relativePath -Pattern $_ }).Count) {
                $reason = 'allow-list-miss'
            }
            elseif (@($denyPatterns | Where-Object { Test-GlobMatch -Path $relativePath -Pattern $_ }).Count) {
                $reason = 'deny-list-hit'
            }

            if ($reason) {
                $articlePath = $_.FullName
                $articleDirectory = $_.DirectoryName
                $slug = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                Remove-Item -LiteralPath $articlePath -Force
                $removed.Add([pscustomobject]@{ path = $relativePath; kind = 'knowledge'; reason = $reason }) | Out-Null
                Get-ChildItem -LiteralPath $articleDirectory -File -Filter "$slug.*.al" -ErrorAction SilentlyContinue | ForEach-Object {
                    $samplePath = Get-RelativePluginPath -Root $pluginRoot -FullName $_.FullName
                    Remove-Item -LiteralPath $_.FullName -Force
                    $removed.Add([pscustomobject]@{ path = $samplePath; kind = 'knowledge-sample'; reason = $reason }) | Out-Null
                }
            }
        }
    }

    $skillsRoot = Join-Path $pluginRoot "$layer/skills"
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) {
        continue
    }
    if ($layers -notcontains $layer) {
        Get-ChildItem -LiteralPath $skillsRoot -Recurse -File -Filter '*.md' | ForEach-Object {
            $relativePath = Get-RelativePluginPath -Root $pluginRoot -FullName $_.FullName
            Remove-Item -LiteralPath $_.FullName -Force
            $removed.Add([pscustomobject]@{ path = $relativePath; kind = 'skill'; reason = 'layer-disabled' }) | Out-Null
        }
    }
}

foreach ($disabledSkill in $disabledSkillPaths) {
    $normalizedPath = ($disabledSkill -replace '\\', '/').Trim()
    if ($normalizedPath -notmatch '^(microsoft|community|custom)/skills/.+\.md$' -or @($normalizedPath.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
        throw "Disabled skill '$disabledSkill' must be a repo-relative markdown path under a BCQuality layer's skills directory."
    }
    $resolvedPath = Resolve-SafePluginPath -Root $pluginRoot -RelativePath $normalizedPath
    if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
        Remove-Item -LiteralPath $resolvedPath -Force
        $removed.Add([pscustomobject]@{ path = $normalizedPath; kind = 'skill'; reason = 'configuration' }) | Out-Null
    }
}

$knowledgeIndex = Join-Path $pluginRoot 'knowledge-index.json'
& (Join-Path $pluginRoot 'tools/Build-KnowledgeIndex.ps1') `
    -BCQualityRoot $pluginRoot `
    -IndexPath $knowledgeIndex `
    -EnabledLayers $layers `
    -KnowledgeAllow $allowPatterns `
    -KnowledgeDeny $denyPatterns | Out-Null
if (-not (Test-Path -LiteralPath $knowledgeIndex -PathType Leaf)) {
    throw 'BCQuality knowledge-index generation failed.'
}
$indexedKnowledge = @((Get-Content -LiteralPath $knowledgeIndex -Raw | ConvertFrom-Json).articles | ForEach-Object { [string]$_.path })
foreach ($removedKnowledge in @($removed | Where-Object { $_.kind -eq 'knowledge' })) {
    if ($indexedKnowledge -contains [string]$removedKnowledge.path) {
        throw "Removed BCQuality knowledge remains in the generated index: $($removedKnowledge.path)"
    }
}

$contentHash = Get-FilteredContentHash -Root $pluginRoot
$filterReport = Join-Path $pluginRoot '_filter-report.json'
[pscustomobject]@{
    marketplace = $marketplace
    marketplaceRef = $marketplaceRef
    pluginVersion = $pluginVersion
    sourceHash = $sourceHash
    sourceCommit = $sourceCommit
    contentHash = $contentHash
    enabledLayers = $layers
    disabledSkills = $disabledSkillPaths
    knowledgeAllow = $allowPatterns
    knowledgeDeny = $denyPatterns
    removedCount = $removed.Count
    removed = @($removed)
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $filterReport -Encoding UTF8

Write-Host "BCQuality $pluginVersion from $marketplace#$marketplaceRef prepared at $pluginRoot."
Write-Host "Removed $($removed.Count) file(s); filtered content hash: $contentHash"

if ($env:GITHUB_OUTPUT) {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "pluginRoot=$pluginRoot"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "pluginVersion=$pluginVersion"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "marketplaceRef=$marketplaceRef"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "sourceHash=$sourceHash"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "sourceCommit=$sourceCommit"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "contentHash=$contentHash"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "filterReport=$filterReport"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "knowledgeIndex=$knowledgeIndex"
}
