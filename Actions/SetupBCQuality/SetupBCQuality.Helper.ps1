<#
.SYNOPSIS
Installs and physically filters the BCQuality Copilot plugin.

.DESCRIPTION
Registers a BCQuality marketplace tag or prototype branch, installs the BCQuality
plugin into Copilot's default plugin directory, removes content excluded by
the requested layer and allow/deny policy, and regenerates the knowledge
index. The action intentionally supports only ephemeral GitHub-hosted runners
because it mutates the default installed plugin in place.
#>
[CmdletBinding()]
param(
    [string] $marketplace = 'microsoft/BCQuality',
    [string] $marketplaceRef = 'main',
    [string] $expectedPluginVersion = '0.2.0',
    [string] $enabledLayers = 'microsoft',
    [string] $disabledSkills = '',
    [string] $knowledgeAllow = '',
    [string] $knowledgeDeny = '',
    [string] $runnerEnvironment = $env:RUNNER_ENVIRONMENT,
    [string] $pluginRoot = '',
    [string] $copilotHome = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0

function ConvertFrom-CsvSetting {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-GlobMatch {
    param(
        [string] $Path,
        [string] $Pattern
    )

    $normalizedPattern = ($Pattern -replace '\\', '/').Trim()
    if (-not $normalizedPattern) {
        return $false
    }

    $regex = [System.Text.StringBuilder]::new()
    [void] $regex.Append('^')
    for ($index = 0; $index -lt $normalizedPattern.Length; $index++) {
        $character = $normalizedPattern[$index]
        if ($character -eq '*' -and ($index + 1) -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '*') {
            [void] $regex.Append('.*')
            $index++
            if (($index + 1) -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '/') {
                $index++
            }
        }
        elseif ($character -eq '*') {
            [void] $regex.Append('[^/]*')
        }
        elseif ($character -eq '?') {
            [void] $regex.Append('[^/]')
        }
        elseif (@('.', '\', '+', '(', ')', '{', '}', '[', ']', '^', '$', '|') -contains $character) {
            [void] $regex.Append('\').Append($character)
        }
        else {
            [void] $regex.Append($character)
        }
    }
    [void] $regex.Append('$')
    return $Path -match $regex.ToString()
}

function Get-RelativePluginPath {
    param(
        [string] $Root,
        [string] $FullName
    )

    return ($FullName.Substring($Root.Length).TrimStart([char] '/', [char] '\') -replace '\\', '/')
}

function Resolve-SafePluginPath {
    param(
        [string] $Root,
        [string] $RelativePath
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $RelativePath))
    $prefix = "$resolvedRoot$([System.IO.Path]::DirectorySeparatorChar)"
    if (-not $resolvedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "BCQuality path '$RelativePath' escapes the installed plugin root."
    }
    return $resolvedPath
}

function Read-CopilotConfig {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Copilot plugin configuration not found: $Path"
    }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $jsonStart = $raw.IndexOf('{')
    if ($jsonStart -lt 0) {
        throw "Copilot plugin configuration is malformed: $Path"
    }
    try {
        return $raw.Substring($jsonStart) | ConvertFrom-Json
    }
    catch {
        throw "Copilot plugin configuration is malformed: $Path"
    }
}

function Get-FilteredContentHash {
    param([string] $Root)

    $lines = foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relativePath = Get-RelativePluginPath -Root $Root -FullName $file.FullName
        if ($relativePath -in @('_filter-report.json', '_skill-index.json', 'knowledge-index.json')) {
            continue
        }

        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relativePath`0$fileHash"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Resolve-MarketplaceCommit {
    param(
        [string] $Repository,
        [string] $Ref
    )

    $remoteUrl = "https://github.com/$Repository.git"
    $lines = @(& git ls-remote $remoteUrl "refs/tags/$Ref" "refs/tags/$Ref^{}" "refs/heads/$Ref")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve BCQuality marketplace ref '$Repository#$Ref'."
    }

    $resolved = @{}
    foreach ($line in $lines) {
        if ($line -match '^([0-9a-f]{40})\s+(.+)$') {
            $resolved[$Matches[2]] = $Matches[1]
        }
    }
    if ($resolved.ContainsKey("refs/tags/$Ref^{}")) {
        return $resolved["refs/tags/$Ref^{}"]
    }
    if ($resolved.ContainsKey("refs/tags/$Ref")) {
        return $resolved["refs/tags/$Ref"]
    }
    if ($resolved.ContainsKey("refs/heads/$Ref")) {
        return $resolved["refs/heads/$Ref"]
    }
    throw "BCQuality marketplace ref '$Repository#$Ref' did not resolve to a branch or tag."
}

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
    $sourceCommit = Resolve-MarketplaceCommit -Repository $marketplace -Ref $marketplaceRef

    & copilot plugin marketplace add "$marketplace#$marketplaceRef"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register BCQuality marketplace $marketplace#$marketplaceRef."
    }

    & copilot plugin install 'bcquality@bcquality'
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
