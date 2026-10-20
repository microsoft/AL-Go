Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "ReadSettings Action Tests" {
    BeforeAll {
        $actionName = "ReadSettings"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        . (Join-Path $scriptRoot '..\AL-Go-Helper.ps1' -Resolve)
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "GitHubRunnerJson" = "GitHubRunner in compressed Json format"
            "GitHubRunnerShell" = "Shell for GitHubRunner jobs"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Emits skipped settings and a single balanced sources group' {
        $workspace = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $originalEnvironment = @{}
        foreach ($name in @('GITHUB_WORKSPACE', 'GITHUB_ENV', 'GITHUB_OUTPUT', 'GITHUB_RUN_NUMBER', 'GITHUB_RUN_ATTEMPT', 'GITHUB_EVENT_NAME', 'ALGoOrgSettings', 'ALGoRepoSettings', 'ALGoEnvSettings')) {
            $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }

        try {
            New-Item -ItemType Directory -Path $workspace | Out-Null
            $env:GITHUB_WORKSPACE = $workspace
            $env:GITHUB_ENV = Join-Path $workspace 'github-env.txt'
            $env:GITHUB_OUTPUT = Join-Path $workspace 'github-output.txt'
            $env:GITHUB_RUN_NUMBER = '1'
            $env:GITHUB_RUN_ATTEMPT = '1'
            $env:GITHUB_EVENT_NAME = 'push'
            $env:ALGoOrgSettings = '{"protectedSettings":["country"],"country":"de"}'
            $env:ALGoRepoSettings = '{"country":"ch"}'
            $env:ALGoEnvSettings = ''

            $transcriptPath = Join-Path $workspace 'action-log.txt'
            Start-Transcript -Path $transcriptPath -Force | Out-Null
            try {
                & $scriptPath -workflowName '' -project '' | Out-Null
            }
            finally {
                Stop-Transcript | Out-Null
            }
            $output = Get-Content -Path $transcriptPath -Raw -Encoding UTF8
            $notice = 'Skipped setting country from settings ALGoRepoSettings (Variable): protected by settings ALGoOrgSettings (Variable)'
            $groupStart = [regex]::Matches($output, '(?m)(::group::Settings sources|==== Group start: Settings sources ====)')
            $groupEnd = [regex]::Matches($output, '(?m)(::endgroup::|==== Group end ====)')

            $output.Contains($notice) | Should -BeTrue
            ([regex]::Matches($output, [regex]::Escape($notice))).Count | Should -Be 1
            $groupStart.Count | Should -Be 1
            $groupEnd.Count | Should -Be 1
            $output.IndexOf($notice) | Should -BeLessThan $groupStart[0].Index
            $groupEnd[0].Index | Should -BeGreaterThan $groupStart[0].Index
            $sourcesGroup = $output.Substring($groupStart[0].Index, $groupEnd[0].Index - $groupStart[0].Index)
            $sourcesGroup | Should -Match '(?m)^country: settings ALGoOrgSettings \(Variable\) \(protected\)\r?$'
            $sourcesGroup | Should -Match '(?m)^shell: default, derived from runs-on\r?$'
            $sourcesGroup | Should -Match '(?m)^alDoc\.includeProjects: default\r?$'
            $sourcesGroup | Should -Match '(?m)^appBuild: default, derived from versioning strategy 0 \(runNumberOffset and GITHUB_RUN_NUMBER\)\r?$'
            $sourcesGroup | Should -Match '(?m)^appRevision: default, derived from versioning strategy 0 \(GITHUB_RUN_ATTEMPT minus 1\)\r?$'
        }
        finally {
            foreach ($name in $originalEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name])
            }
            Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Action-level source derivations' {
        BeforeAll {
            $invokeAction = {
                $transcriptPath = Join-Path $workspace 'action-log.txt'
                $startedAt = [DateTime]::UtcNow
                Start-Transcript -Path $transcriptPath -Force | Out-Null
                try {
                    & $scriptPath -workflowName '' -project '' | Out-Null
                }
                finally {
                    Stop-Transcript | Out-Null
                }
                $finishedAt = [DateTime]::UtcNow
                $output = Get-Content -Path $transcriptPath -Raw -Encoding UTF8
                $groupStart = [regex]::Matches($output, '(?m)(::group::Settings sources|==== Group start: Settings sources ====)')
                $groupEnd = [regex]::Matches($output, '(?m)(::endgroup::|==== Group end ====)')
                $groupStart.Count | Should -Be 1
                $groupEnd.Count | Should -Be 1
                $groupEnd[0].Index | Should -BeGreaterThan $groupStart[0].Index
                $settingsLine = Get-Content -Path $env:GITHUB_ENV -Encoding UTF8 | Where-Object { $_.StartsWith('Settings=') } | Select-Object -Last 1
                @{
                    sources = $output.Substring($groupStart[0].Index, $groupEnd[0].Index - $groupStart[0].Index)
                    settings = $settingsLine.Substring('Settings='.Length) | ConvertFrom-Json | ConvertTo-HashTable -recurse
                    startedAt = $startedAt
                    finishedAt = $finishedAt
                }
            }
        }

        BeforeEach {
            $workspace = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $originalEnvironment = @{}
            foreach ($name in @('GITHUB_WORKSPACE', 'GITHUB_ENV', 'GITHUB_OUTPUT', 'GITHUB_RUN_NUMBER', 'GITHUB_RUN_ATTEMPT', 'GITHUB_EVENT_NAME', 'ALGoOrgSettings', 'ALGoRepoSettings', 'ALGoEnvSettings')) {
                $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            }
            New-Item -ItemType Directory -Path $workspace | Out-Null
            $env:GITHUB_WORKSPACE = $workspace
            $env:GITHUB_ENV = Join-Path $workspace 'github-env.txt'
            $env:GITHUB_OUTPUT = Join-Path $workspace 'github-output.txt'
            $env:GITHUB_RUN_NUMBER = '42'
            $env:GITHUB_RUN_ATTEMPT = '3'
            $env:GITHUB_EVENT_NAME = 'push'
            $env:ALGoOrgSettings = ''
            $env:ALGoRepoSettings = '{"runNumberOffset":100}'
            $env:ALGoEnvSettings = ''
        }

        AfterEach {
            foreach ($name in $originalEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name])
            }
            Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Traces and exports versioning strategy <strategy>' -TestCases @(
            @{ strategy = 0; expectedBuild = 142; expectedRevision = 2; buildDerivation = 'runNumberOffset and GITHUB_RUN_NUMBER'; revisionDerivation = 'GITHUB_RUN_ATTEMPT minus 1' }
            @{ strategy = 16; expectedBuild = 142; expectedRevision = 2; buildDerivation = 'runNumberOffset and GITHUB_RUN_NUMBER'; revisionDerivation = 'GITHUB_RUN_ATTEMPT minus 1' }
            @{ strategy = 3; expectedBuild = -1; expectedRevision = 142; buildDerivation = 'use build from app.json'; revisionDerivation = 'runNumberOffset and GITHUB_RUN_NUMBER' }
            @{ strategy = 15; expectedBuild = [int32]::MaxValue; expectedRevision = 142; buildDerivation = 'maxValue'; revisionDerivation = 'runNumberOffset and GITHUB_RUN_NUMBER' }
        ) {
            Param($strategy, $expectedBuild, $expectedRevision, $buildDerivation, $revisionDerivation)

            $env:ALGoRepoSettings = @{ versioningStrategy = $strategy; runNumberOffset = 100 } | ConvertTo-Json
            $result = & $invokeAction
            $effectiveStrategy = $strategy -band 15

            $result.settings.versioningStrategy | Should -Be $strategy
            $result.settings.appBuild | Should -Be $expectedBuild
            $result.settings.appRevision | Should -Be $expectedRevision
            $result.sources | Should -Match ('(?m)^appBuild: ' + [regex]::Escape("default, derived from versioning strategy $effectiveStrategy ($buildDerivation)") + '\r?$')
            $result.sources | Should -Match ('(?m)^appRevision: ' + [regex]::Escape("default, derived from versioning strategy $effectiveStrategy ($revisionDerivation)") + '\r?$')
            $result.sources | Should -Match '(?m)^versioningStrategy: settings ALGoRepoSettings \(Variable\)\r?$'
            $result.settings.doNotSignApps | Should -BeFalse
            $result.sources | Should -Not -Match 'derived from GitHub pull request or merge group event'
        }

        It 'Traces UTC date and time for versioning strategy 2' {
            $env:ALGoRepoSettings = '{"versioningStrategy":2}'
            $result = & $invokeAction

            $result.settings.versioningStrategy | Should -Be 2
            @([int32]$result.startedAt.ToString('yyyyMMdd'), [int32]$result.finishedAt.ToString('yyyyMMdd')) | Should -Contain $result.settings.appBuild
            $startTime = [int32]$result.startedAt.ToString('HHmmss')
            $endTime = [int32]$result.finishedAt.ToString('HHmmss')
            if ($result.startedAt.Date -eq $result.finishedAt.Date) {
                ($result.settings.appRevision -ge $startTime -and $result.settings.appRevision -le $endTime) | Should -BeTrue
            }
            else {
                ($result.settings.appRevision -ge $startTime -or $result.settings.appRevision -le $endTime) | Should -BeTrue
            }
            $result.sources | Should -Match '(?m)^appBuild: default, derived from versioning strategy 2 \(UTC date\)\r?$'
            $result.sources | Should -Match '(?m)^appRevision: default, derived from versioning strategy 2 \(UTC time\)\r?$'
        }

        It 'Leaves explicit build and revision sources unchanged for versioning strategy -1' {
            $env:ALGoRepoSettings = '{"versioningStrategy":-1,"appBuild":7,"appRevision":9}'
            $result = & $invokeAction

            $result.settings.versioningStrategy | Should -Be -1
            $result.settings.appBuild | Should -Be 7
            $result.settings.appRevision | Should -Be 9
            $result.sources | Should -Match '(?m)^appBuild: settings ALGoRepoSettings \(Variable\)\r?$'
            $result.sources | Should -Match '(?m)^appRevision: settings ALGoRepoSettings \(Variable\)\r?$'
        }

        It 'Traces event-derived settings for <eventName>' -TestCases @(
            @{ eventName = 'pull_request' }
            @{ eventName = 'pull_request_target' }
            @{ eventName = 'merge_group' }
        ) {
            Param($eventName)

            $env:GITHUB_EVENT_NAME = $eventName
            $env:ALGoRepoSettings = '{"runNumberOffset":100,"versioningStrategy":-1,"doNotSignApps":false}'
            $result = & $invokeAction

            $result.settings.doNotSignApps | Should -BeTrue
            $result.settings.versioningStrategy | Should -Be 15
            $result.settings.appBuild | Should -Be ([int32]::MaxValue)
            $result.settings.appRevision | Should -Be 142
            foreach ($setting in @('doNotSignApps', 'versioningStrategy')) {
                $result.sources | Should -Match ('(?m)^' + $setting + ': settings ALGoRepoSettings \(Variable\), derived from GitHub pull request or merge group event\r?$')
            }
            $result.sources | Should -Match '(?m)^appBuild: default, derived from versioning strategy 15 \(maxValue\)\r?$'
            $result.sources | Should -Match '(?m)^appRevision: default, derived from versioning strategy 15 \(runNumberOffset and GITHUB_RUN_NUMBER\)\r?$'
        }

        It 'Traces strategy 15 derived from a maximum appBuild' {
            $env:ALGoRepoSettings = '{"runNumberOffset":100,"versioningStrategy":0,"appBuild":2147483647}'
            $result = & $invokeAction

            $result.settings.versioningStrategy | Should -Be 15
            $result.settings.appBuild | Should -Be ([int32]::MaxValue)
            $result.settings.appRevision | Should -Be 142
            $result.sources | Should -Match '(?m)^versioningStrategy: settings ALGoRepoSettings \(Variable\), derived from appBuild set to maxValue\r?$'
            $result.sources | Should -Match '(?m)^appBuild: settings ALGoRepoSettings \(Variable\), derived from versioning strategy 15 \(maxValue\)\r?$'
            $result.sources | Should -Match '(?m)^appRevision: default, derived from versioning strategy 15 \(runNumberOffset and GITHUB_RUN_NUMBER\)\r?$'
        }

        It 'Preserves earlier sources and protection flags when appending action derivations' {
            $env:GITHUB_EVENT_NAME = 'pull_request'
            $env:ALGoOrgSettings = '{"protectedSettings":["doNotSignApps","versioningStrategy","appBuild","appRevision"],"doNotSignApps":false,"versioningStrategy":-1,"appBuild":7,"appRevision":9}'
            $result = & $invokeAction

            $result.settings.doNotSignApps | Should -BeTrue
            $result.settings.versioningStrategy | Should -Be 15
            $result.settings.appBuild | Should -Be ([int32]::MaxValue)
            $result.settings.appRevision | Should -Be 142
            foreach ($setting in @('doNotSignApps', 'versioningStrategy')) {
                $result.sources | Should -Match ('(?m)^' + $setting + ': settings ALGoOrgSettings \(Variable\), derived from GitHub pull request or merge group event \(protected\)\r?$')
            }
            $result.sources | Should -Match '(?m)^appBuild: settings ALGoOrgSettings \(Variable\), derived from versioning strategy 15 \(maxValue\) \(protected\)\r?$'
            $result.sources | Should -Match '(?m)^appRevision: settings ALGoOrgSettings \(Variable\), derived from versioning strategy 15 \(runNumberOffset and GITHUB_RUN_NUMBER\) \(protected\)\r?$'
        }
    }
}
