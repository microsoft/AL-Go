Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "ReadSettings Action Tests" {
    BeforeAll {
        $actionName = "ReadSettings"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
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
        foreach ($name in @('GITHUB_WORKSPACE', 'GITHUB_ENV', 'GITHUB_OUTPUT', 'GITHUB_RUN_NUMBER', 'GITHUB_RUN_ATTEMPT', 'ALGoOrgSettings', 'ALGoRepoSettings', 'ALGoEnvSettings')) {
            $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }

        try {
            New-Item -ItemType Directory -Path $workspace | Out-Null
            $env:GITHUB_WORKSPACE = $workspace
            $env:GITHUB_ENV = Join-Path $workspace 'github-env.txt'
            $env:GITHUB_OUTPUT = Join-Path $workspace 'github-output.txt'
            $env:GITHUB_RUN_NUMBER = '1'
            $env:GITHUB_RUN_ATTEMPT = '1'
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
        }
        finally {
            foreach ($name in $originalEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name])
            }
            Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
