[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0

Describe 'SetupBCQuality action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/SetupBCQuality' -Resolve
        $script:setupScriptPath = Join-Path $scriptRoot 'SetupBCQuality.Helper.ps1'

        function New-TestBCQualityPlugin {
            param([string] $Root)

            New-Item -ItemType Directory -Force -Path (Join-Path $Root 'skills') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $Root 'tools') | Out-Null
            foreach ($path in @('skills/entry.md', 'skills/read.md', 'skills/do.md')) {
                Set-Content -LiteralPath (Join-Path $Root $path) -Value "# $path" -Encoding UTF8
            }
            Set-Content -LiteralPath (Join-Path $Root 'tools/Build-KnowledgeIndex.ps1') -Encoding UTF8 -Value @'
param(
    [string] $BCQualityRoot,
    [string] $IndexPath,
    [string[]] $EnabledLayers,
    [string[]] $KnowledgeAllow,
    [string[]] $KnowledgeDeny
)
$articles = @(Get-ChildItem -Path $BCQualityRoot -Recurse -File -Filter '*.md' |
    Where-Object { $_.FullName -match '[\\/](microsoft|community|custom)[\\/]knowledge[\\/]' } |
    ForEach-Object { @{ path = ($_.FullName.Substring($BCQualityRoot.Length).TrimStart('\','/') -replace '\\','/') } })
@{
    enabledLayers = $EnabledLayers
    knowledgeAllow = $KnowledgeAllow
    knowledgeDeny = $KnowledgeDeny
    articles = $articles
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
'@
            Set-Content -LiteralPath (Join-Path $Root 'tools/Build-SkillIndex.ps1') -Encoding UTF8 -Value @'
param([string] $BCQualityRoot, [string] $IndexPath)
@{ skills = @('microsoft/skills/review/microsoft.md', 'community/skills/review/community.md', 'custom/skills/review/custom.md') } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
'@
            foreach ($layer in @('microsoft', 'community', 'custom')) {
                New-Item -ItemType Directory -Force -Path (Join-Path $Root "$layer/knowledge/domain") | Out-Null
                New-Item -ItemType Directory -Force -Path (Join-Path $Root "$layer/skills/review") | Out-Null
                Set-Content -LiteralPath (Join-Path $Root "$layer/knowledge/domain/$layer.md") -Value "# $layer" -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $Root "$layer/knowledge/domain/$layer.good.al") -Value "codeunit 1 Test {}" -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $Root "$layer/skills/review/$layer.md") -Value "# $layer review" -Encoding UTF8
            }
        }
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
        Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value '' -Encoding UTF8
        $pluginRoot = Join-Path $TestDrive 'bcquality'
        New-TestBCQualityPlugin -Root $pluginRoot
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'SetupBCQuality.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'SetupBCQuality' -actionScript $actionScript -outputs ([ordered]@{
            pluginRoot = 'Path to the installed and filtered BCQuality plugin'
            pluginVersion = 'Resolved BCQuality plugin version'
            marketplaceRef = 'Marketplace ref used to install BCQuality'
            sourceHash = 'Source hash recorded by Copilot CLI for the installed plugin'
            sourceCommit = 'Git commit resolved from the installed marketplace tag or branch'
            contentHash = 'Deterministic SHA-256 of the filtered plugin contents'
            filterReport = 'Path to the BCQuality filter report'
            knowledgeIndex = 'Path to the regenerated BCQuality knowledge index'
        })
    }

    It 'Retains only the enabled layer and regenerates the index' {
        & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment github-hosted -enabledLayers microsoft

        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/microsoft.md') | Should -BeTrue
        Test-Path (Join-Path $pluginRoot 'community/knowledge/domain/community.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'community/skills/review/community.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'custom/knowledge/domain/custom.good.al') | Should -BeFalse

        $index = Get-Content (Join-Path $pluginRoot 'knowledge-index.json') -Raw | ConvertFrom-Json
        @($index.articles.path) | Should -Contain 'microsoft/knowledge/domain/microsoft.md'
        @($index.articles.path) | Should -Not -Contain 'community/knowledge/domain/community.md'
        @($index.enabledLayers) | Should -Be 'microsoft'
        Test-Path (Join-Path $pluginRoot '_skill-index.json') | Should -BeTrue

        $report = Get-Content (Join-Path $pluginRoot '_filter-report.json') -Raw | ConvertFrom-Json
        $report.enabledLayers | Should -Be 'microsoft'
        $report.removedCount | Should -BeGreaterThan 0
    }

    It 'Applies allow then deny filtering and removes article samples' {
        Set-Content -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.md') -Value '# keep' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.bad.al') -Value 'bad' -Encoding UTF8

        & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment github-hosted -enabledLayers microsoft `
            -knowledgeAllow 'microsoft/knowledge/domain/*.md' -knowledgeDeny 'microsoft/knowledge/domain/keep.md'

        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/microsoft.md') | Should -BeTrue
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.bad.al') | Should -BeFalse
    }

    It 'Removes an explicitly disabled skill' {
        & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment github-hosted -enabledLayers microsoft `
            -disabledSkills 'microsoft/skills/review/microsoft.md'

        Test-Path (Join-Path $pluginRoot 'microsoft/skills/review/microsoft.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'skills/entry.md') | Should -BeTrue
    }

    It 'Fails closed outside a GitHub-hosted runner' {
        {
            & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment self-hosted
        } | Should -Throw '*only ephemeral GitHub-hosted runners*'
    }

    It 'Rejects unsafe disabled-skill paths and raw commit refs' {
        {
            & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment github-hosted `
                -disabledSkills 'microsoft/skills/../../skills/entry.md'
        } | Should -Throw '*must be a repo-relative markdown path*'

        {
            & $script:setupScriptPath -pluginRoot $pluginRoot -runnerEnvironment github-hosted `
                -marketplaceRef '0123456789012345678901234567890123456789'
        } | Should -Throw '*branches and tags, not raw commit SHAs*'
    }
}
