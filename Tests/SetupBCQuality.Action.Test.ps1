[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test callbacks mirror action inputs')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0

Describe 'SetupBCQuality action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/SetupBCQuality' -Resolve
        $script:setupScriptPath = Join-Path $scriptRoot 'SetupBCQuality.ps1'
        Import-Module (Join-Path $scriptRoot 'SetupBCQuality.psm1') -Force

        function New-TestBCQualityPlugin {
            param([string] $Root)

            New-Item -ItemType Directory -Force -Path $Root | Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'plugin.json') -Value '{"name":"bcquality","version":"0.3.0"}' -Encoding UTF8
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
        $env:SETUP_BCQUALITY_PLUGIN_ROOT = $pluginRoot
        $env:SETUP_BCQUALITY_RUNNER_ENVIRONMENT = 'github-hosted'
    }

    AfterEach {
        Remove-Item Env:SETUP_BCQUALITY_PLUGIN_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:SETUP_BCQUALITY_RUNNER_ENVIRONMENT -ErrorAction SilentlyContinue
        Remove-Item Env:SETUP_BCQUALITY_COPILOT_HOME -ErrorAction SilentlyContinue
    }

    It 'Matches the standard action wrapper and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'SetupBCQuality.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'SetupBCQuality' -actionScript $actionScript -DefaultShell pwsh -outputs ([ordered]@{
            pluginRoot = 'Path to the installed and filtered BCQuality plugin'
            pluginVersion = 'Resolved BCQuality plugin version'
            marketplaceRef = 'Marketplace ref used to install BCQuality'
            sourceHash = 'Source hash recorded by Copilot CLI for the installed plugin'
            contentHash = 'Deterministic SHA-256 of the filtered plugin contents'
            filterReport = 'Path to the BCQuality filter report'
            knowledgeIndex = 'Path to the regenerated BCQuality knowledge index'
        })
    }

    It 'Does not ship a separate BCQuality policy file' {
        Test-Path (Join-Path $scriptRoot 'bcquality.config.yaml') | Should -BeFalse
        Test-Path (Join-Path $scriptRoot 'Get-BCQualityConfig.ps1') | Should -BeFalse
    }

    It 'Maps validated BCQuality settings into setup inputs' {
        $settingsJson = @{
            marketplaceRepo = 'https://github.com/contoso/BCQuality'
            version = '2.0'
            enabledLayers = @('microsoft')
            disabledSkills = @('microsoft/skills/review/microsoft.md')
            knowledge = @{
                allow = @('microsoft/knowledge/**')
                deny = @()
            }
        } | ConvertTo-Json -Compress -Depth 5

        & $script:setupScriptPath -bcqualitySettingsJson $settingsJson

        $report = Get-Content (Join-Path $pluginRoot '_filter-report.json') -Raw | ConvertFrom-Json
        $report.marketplace | Should -Be 'contoso/BCQuality'
        $report.marketplaceRef | Should -Be 'v2.0'
        $report.pluginVersion | Should -Be '0.3.0'
        $report.enabledLayers | Should -Be 'microsoft'
        $report.disabledSkills | Should -Be 'microsoft/skills/review/microsoft.md'
        $report.knowledgeAllow | Should -Be 'microsoft/knowledge/**'
    }

    It 'Retains only the enabled layer and regenerates the index' {
        & $script:setupScriptPath -enabledLayers microsoft

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

    It 'Defaults standalone setup to the centralized BCQuality version' {
        & $script:setupScriptPath

        $defaultVersion = & (Get-Module ReadSettings) { (GetDefaultSettings).BCQuality.version }
        $report = Get-Content (Join-Path $pluginRoot '_filter-report.json') -Raw | ConvertFrom-Json
        $report.marketplaceRef | Should -Be "v$defaultVersion"
    }

    It 'Retains all layers for an empty merged enabledLayers setting' {
        $settingsJson = @{
            marketplaceRepo = 'https://github.com/microsoft/BCQuality'; version = '2.0'
            enabledLayers = @(); disabledSkills = @()
            knowledge = @{ allow = @(); deny = @() }
        } | ConvertTo-Json -Compress -Depth 5

        & $script:setupScriptPath -bcqualitySettingsJson $settingsJson

        $report = Get-Content (Join-Path $pluginRoot '_filter-report.json') -Raw | ConvertFrom-Json
        @($report.enabledLayers) | Should -Be @('microsoft', 'community', 'custom')
    }

    It 'Preserves commas in JSON knowledge filters and disabled skill paths' {
        foreach ($name in @('keep,article', 'deny,article', 'unrelated')) {
            Set-Content -LiteralPath (Join-Path $pluginRoot "microsoft/knowledge/domain/$name.md") -Value '# article' -Encoding UTF8
        }
        $skill = 'microsoft/skills/review/extra,skill.md'
        Set-Content -LiteralPath (Join-Path $pluginRoot $skill) -Value '# skill' -Encoding UTF8
        $settingsJson = @{
            marketplaceRepo = 'https://github.com/microsoft/BCQuality'; version = '2.0'
            enabledLayers = @('microsoft'); disabledSkills = @($skill)
            knowledge = @{
                allow = @('microsoft/knowledge/**/keep,article.md', 'microsoft/knowledge/**/deny,article.md')
                deny = @('microsoft/knowledge/**/deny,article.md')
            }
        } | ConvertTo-Json -Compress -Depth 5

        & $script:setupScriptPath -bcqualitySettingsJson $settingsJson

        Test-Path -LiteralPath (Join-Path $pluginRoot $skill) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep,article.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/deny,article.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/unrelated.md') | Should -BeFalse
    }

    It 'Applies allow then deny filtering and removes article samples' {
        Set-Content -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.md') -Value '# keep' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.bad.al') -Value 'bad' -Encoding UTF8

        & $script:setupScriptPath -enabledLayers microsoft `
            -knowledgeAllow 'microsoft/knowledge/domain/*.md' -knowledgeDeny 'microsoft/knowledge/domain/keep.md'

        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/microsoft.md') | Should -BeTrue
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/keep.bad.al') | Should -BeFalse
    }

    It 'Preserves directory boundaries in recursive allow and deny globs' {
        foreach ($path in @('microsoft/knowledge/finance.md', 'microsoft/knowledge/domain/finance.md', 'microsoft/knowledge/domain/notfinance.md')) {
            Set-Content -LiteralPath (Join-Path $pluginRoot $path) -Value '# article' -Encoding UTF8
        }

        Test-GlobMatch -Path 'microsoft/knowledge/finance.md' -Pattern 'microsoft/knowledge/**/finance.md' | Should -BeTrue
        Test-GlobMatch -Path 'microsoft/knowledge/domain/finance.md' -Pattern 'microsoft/knowledge/**/finance.md' | Should -BeTrue
        Test-GlobMatch -Path 'microsoft/knowledge/domain/notfinance.md' -Pattern 'microsoft/knowledge/**/finance.md' | Should -BeFalse

        & $script:setupScriptPath -enabledLayers microsoft -knowledgeAllow 'microsoft/knowledge/**' `
            -knowledgeDeny 'microsoft/knowledge/**/finance.md'

        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/finance.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/finance.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'microsoft/knowledge/domain/notfinance.md') | Should -BeTrue
    }

    It 'Removes an explicitly disabled skill' {
        & $script:setupScriptPath -enabledLayers microsoft `
            -disabledSkills 'microsoft/skills/review/microsoft.md'

        Test-Path (Join-Path $pluginRoot 'microsoft/skills/review/microsoft.md') | Should -BeFalse
        Test-Path (Join-Path $pluginRoot 'skills/entry.md') | Should -BeTrue
    }

    It 'Fails closed outside a GitHub-hosted runner' {
        {
            $env:SETUP_BCQUALITY_RUNNER_ENVIRONMENT = 'self-hosted'
            & $script:setupScriptPath
        } | Should -Throw '*only ephemeral GitHub-hosted runners*'
    }

    It 'Rejects unsafe disabled-skill paths and raw commit refs' {
        {
            & $script:setupScriptPath -disabledSkills 'microsoft/skills/../../skills/entry.md'
        } | Should -Throw '*must be a repo-relative markdown path*'

        {
            & $script:setupScriptPath -marketplaceRef '0123456789012345678901234567890123456789'
        } | Should -Throw '*branches and tags, not raw commit SHAs*'
    }

    It 'Scopes private marketplace authentication to child processes' {
        $previousCount = $env:GIT_CONFIG_COUNT
        $previousKey = $env:GIT_CONFIG_KEY_0
        $previousValue = $env:GIT_CONFIG_VALUE_0
        try {
            $env:GIT_CONFIG_COUNT = '2'
            $env:GIT_CONFIG_KEY_0 = 'existing.key'
            $env:GIT_CONFIG_VALUE_0 = 'existing-value'

            $observed = Invoke-WithGitHubToken -Repository 'contoso/BCQuality' -Token 'test-token' -ScriptBlock {
                [pscustomobject]@{
                    Count = $env:GIT_CONFIG_COUNT
                    Key = $env:GIT_CONFIG_KEY_0
                    Value = $env:GIT_CONFIG_VALUE_0
                }
            }

            $observed.Count | Should -Be '1'
            $observed.Key | Should -Be 'http.https://github.com/.extraheader'
            $observed.Value | Should -Match '^AUTHORIZATION: basic '
            $observed.Value | Should -Not -Match 'test-token'
            $env:GIT_CONFIG_COUNT | Should -Be '2'
            $env:GIT_CONFIG_KEY_0 | Should -Be 'existing.key'
            $env:GIT_CONFIG_VALUE_0 | Should -Be 'existing-value'
        }
        finally {
            $env:GIT_CONFIG_COUNT = $previousCount
            $env:GIT_CONFIG_KEY_0 = $previousKey
            $env:GIT_CONFIG_VALUE_0 = $previousValue
        }
    }

    It 'Does not authenticate the default public marketplace' {
        $previousCount = $env:GIT_CONFIG_COUNT
        $previousKey = $env:GIT_CONFIG_KEY_0
        $previousValue = $env:GIT_CONFIG_VALUE_0
        try {
            $env:GIT_CONFIG_COUNT = '2'
            $env:GIT_CONFIG_KEY_0 = 'existing.key'
            $env:GIT_CONFIG_VALUE_0 = 'existing-value'

            $observed = Invoke-WithGitHubToken -Repository 'Microsoft/BCQuality' -Token 'test-token' -ScriptBlock {
                [pscustomobject]@{
                    Count = $env:GIT_CONFIG_COUNT
                    Key = $env:GIT_CONFIG_KEY_0
                    Value = $env:GIT_CONFIG_VALUE_0
                }
            }

            $observed.Count | Should -Be '2'
            $observed.Key | Should -Be 'existing.key'
            $observed.Value | Should -Be 'existing-value'
        }
        finally {
            $env:GIT_CONFIG_COUNT = $previousCount
            $env:GIT_CONFIG_KEY_0 = $previousKey
            $env:GIT_CONFIG_VALUE_0 = $previousValue
        }
    }

    Context 'Marketplace installation without a plugin-root override' {
        BeforeAll {
            function copilot {}
        }

        BeforeEach {
            Remove-Item Env:SETUP_BCQUALITY_PLUGIN_ROOT -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $pluginRoot '_filter-report.json') -Force -ErrorAction SilentlyContinue
            $env:SETUP_BCQUALITY_COPILOT_HOME = Join-Path $TestDrive 'copilot-home'
            New-Item -ItemType Directory -Path $env:SETUP_BCQUALITY_COPILOT_HOME -Force | Out-Null
            $script:copilotConfigPath = Join-Path $env:SETUP_BCQUALITY_COPILOT_HOME 'config.json'
            $script:installedPlugin = @{
                name = 'bcquality'; marketplace = 'bcquality'; version = '0.3.0'
                cache_path = $pluginRoot; source_sha = ('a' * 40)
            }
            @{ installedPlugins = @($script:installedPlugin) } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $script:copilotConfigPath -Encoding UTF8
            Mock copilot { $global:LASTEXITCODE = 0 }
        }

        It 'registers the requested marketplace and filters the installed plugin from configuration' {
            & $script:setupScriptPath -marketplace 'contoso/BCQuality' -marketplaceRef 'v1.7' -enabledLayers microsoft

            Should -Invoke copilot -Times 1 -Exactly -ParameterFilter {
                $args.Count -eq 4 -and ($args -join ' ') -eq 'plugin marketplace add contoso/BCQuality#v1.7'
            }
            Should -Invoke copilot -Times 1 -Exactly -ParameterFilter {
                $args.Count -eq 3 -and ($args -join ' ') -eq 'plugin install bcquality@bcquality'
            }
            $report = Get-Content -LiteralPath (Join-Path $pluginRoot '_filter-report.json') -Raw | ConvertFrom-Json
            $report.sourceHash | Should -Be ('a' * 40)
            $report.pluginVersion | Should -Be '0.3.0'
            Test-Path -LiteralPath (Join-Path $pluginRoot 'community/knowledge/domain/community.md') | Should -BeFalse
            Get-Content -LiteralPath $env:GITHUB_OUTPUT | Should -Contain "pluginRoot=$pluginRoot"
        }

        It 'propagates a nonzero <Operation> exit' -TestCases @(
            @{ Operation = 'marketplace'; Expected = '*Failed to register BCQuality marketplace*'; Calls = 1 }
            @{ Operation = 'install'; Expected = '*Failed to install the BCQuality plugin*'; Calls = 2 }
        ) {
            param($Operation, $Expected, $Calls)
            Mock copilot { $global:LASTEXITCODE = 9 } -ParameterFilter { $args[1] -eq $Operation }

            { & $script:setupScriptPath -marketplace 'contoso/BCQuality' -marketplaceRef 'v1.7' } |
                Should -Throw $Expected
            Should -Invoke copilot -Times $Calls -Exactly
            Test-Path -LiteralPath (Join-Path $pluginRoot '_filter-report.json') | Should -BeFalse
        }

        It 'rejects <Case> installed-plugin configuration' -TestCases @(
            @{ Case = 'missing'; Expected = '*configuration not found*' }
            @{ Case = 'malformed'; Expected = '*configuration is malformed*' }
            @{ Case = 'invalid JSON'; Expected = '*configuration is malformed*' }
            @{ Case = 'no matching plugin'; Expected = '*found 0*' }
            @{ Case = 'ambiguous plugin'; Expected = '*found 2*' }
        ) {
            param($Case, $Expected)
            switch ($Case) {
                'missing' { Remove-Item -LiteralPath $script:copilotConfigPath -Force }
                'malformed' { Set-Content -LiteralPath $script:copilotConfigPath -Value 'not JSON' -Encoding UTF8 }
                'invalid JSON' { Set-Content -LiteralPath $script:copilotConfigPath -Value '{broken' -Encoding UTF8 }
                'no matching plugin' {
                    '{"installedPlugins":[{"name":"other","marketplace":"bcquality"}]}' |
                        Set-Content -LiteralPath $script:copilotConfigPath -Encoding UTF8
                }
                'ambiguous plugin' {
                    @{ installedPlugins = @($script:installedPlugin, $script:installedPlugin) } |
                        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:copilotConfigPath -Encoding UTF8
                }
            }

            { & $script:setupScriptPath -marketplace 'contoso/BCQuality' -marketplaceRef 'v1.7' } |
                Should -Throw $Expected
            Test-Path -LiteralPath (Join-Path $pluginRoot '_filter-report.json') | Should -BeFalse
        }

        It 'rejects an installed-plugin version that differs from its manifest' {
            $script:installedPlugin.version = '9.9.9'
            @{ installedPlugins = @($script:installedPlugin) } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $script:copilotConfigPath -Encoding UTF8

            { & $script:setupScriptPath -marketplace 'contoso/BCQuality' -marketplaceRef 'v1.7' } |
                Should -Throw "*version '9.9.9' does not match plugin manifest version '0.3.0'*"
        }
    }
}
