[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Test case parameters are used in Pester mock parameter filters')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot '../Actions/TelemetryHelper.psm1') -Force -DisableNameChecking

Describe 'Action telemetry authentication' {
    It 'Keeps the telemetry token out of the action environment after module import' {
        $previousToken = $env:_ALGO_TELEMETRY_TOKEN
        $previousModulePath = $env:_ALGO_TEST_MODULE
        try {
            $env:_ALGO_TELEMETRY_TOKEN = 'telemetry-token'
            $env:_ALGO_TEST_MODULE = (Join-Path $PSScriptRoot '../Actions/TelemetryHelper.psm1' -Resolve)
            $powerShellPath = (Get-Process -Id $PID).Path
            & $powerShellPath -NoLogo -NoProfile -NonInteractive -Command @'
$ErrorActionPreference = 'Stop'
Import-Module $env:_ALGO_TEST_MODULE -Force -DisableNameChecking
if ($env:_ALGO_TELEMETRY_TOKEN) { exit 1 }
& (Get-Module TelemetryHelper) { if ($script:telemetryToken -ne 'telemetry-token') { exit 2 } }
'@
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            $env:_ALGO_TELEMETRY_TOKEN = $previousToken
            $env:_ALGO_TEST_MODULE = $previousModulePath
        }
    }

    It 'Provides a scoped token to every telemetry wrapper step' {
        $actionFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot '../Actions') -Filter 'action.yaml' -Recurse
        $wrapperSteps = 0
        foreach ($file in $actionFiles) {
            $yaml = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $steps = $yaml -split '(?m)(?=^    - (?:name:|uses:|run:))'
            foreach ($step in $steps) {
                if ($step -notmatch 'Invoke-AlGoAction\.ps1') {
                    continue
                }
                $wrapperSteps++
                if ($file.Directory.Name -eq 'ReadSettings') {
                    $step | Should -Match '(?m)^        _ALGO_TELEMETRY_TOKEN: \$\{\{ inputs\.githubToken \|\| env\.GITHUB_TOKEN \|\| github\.token \}\}'
                }
                else {
                    $step | Should -Match '(?m)^        (GITHUB_TOKEN|_ALGO_TELEMETRY_TOKEN): \$\{\{ env\.GITHUB_TOKEN \|\| github\.token \}\}'
                }
            }
        }
        $wrapperSteps | Should -BeGreaterThan 0
    }
}

Describe 'Structured action telemetry' {
    InModuleScope TelemetryHelper {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'wrapperPath', Justification = 'Used by tests in separate Pester scriptblocks')]
            $wrapperPath = Join-Path $PSScriptRoot '../Actions/Invoke-AlGoAction.ps1' -Resolve
        }

        BeforeEach {
            $additionalData = [System.Collections.Generic.Dictionary[string, string]]::new()
            $additionalData.Add('CustomProperty', 'preserved')
            Mock AddTelemetryEvent {}
            Mock Write-Host {}
        }

        It 'Adds the action name without inferring a conclusion from <command>' -TestCases @(
            @{ command = 'Trace-Information'; expectedMessage = 'AL-Go action ran: Test'; expectedSeverity = 'Information' }
            @{ command = 'Trace-Exception'; expectedMessage = 'AL-Go action failed: Test'; expectedSeverity = 'Error' }
        ) {
            param($command, $expectedMessage, $expectedSeverity)
            & $command -ActionName 'Test' -AdditionalData $additionalData

            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                $Data['ActionName'] -eq 'Test' -and
                -not $Data.ContainsKey('ActionConclusion') -and
                $Data['CustomProperty'] -eq 'preserved' -and
                $Message -eq $expectedMessage -and $Severity -eq $expectedSeverity
            }
        }

        It 'Does not add action dimensions to message-only <command> events' -TestCases @(
            @{ command = 'Trace-Information' }
            @{ command = 'Trace-Exception' }
            @{ command = 'Trace-Warning' }
        ) {
            param($command)
            & $command -Message 'Custom message'

            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                -not $Data.ContainsKey('ActionName') -and
                -not $Data.ContainsKey('ActionConclusion') -and
                $Message -eq 'Custom message'
            }
        }

        It 'Reports successful completion with the existing duration and additional data' {
            & $wrapperPath -ActionName 'Test' -Action {} -AdditionalData $additionalData

            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                $Data['ActionName'] -eq 'Test' -and
                $Data['ActionConclusion'] -eq 'Success' -and
                $Data.ContainsKey('ActionDuration') -and [double]$Data['ActionDuration'] -ge 0 -and
                $Data['CustomProperty'] -eq 'preserved'
            }
        }

        It 'Reports a terminating failure and preserves the error and exit code' {
            & $wrapperPath -ActionName 'Test' -Action { throw 'Action failed' }

            $LASTEXITCODE | Should -Be 1
            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                $Data['ActionName'] -eq 'Test' -and
                $Data['ActionConclusion'] -eq 'Failure' -and
                $Data['ErrorMessage'] -eq 'Action failed' -and
                $Data.ContainsKey('ActionDuration') -and [double]$Data['ActionDuration'] -ge 0
            }
        }

        It 'Does not count a handled error as a failed action execution' {
            & $wrapperPath -ActionName 'Test' -Action {
                try {
                    throw 'Handled error'
                }
                catch {
                    Trace-Exception -ActionName 'Test' -ErrorRecord $_
                }
            }

            Assert-MockCalled AddTelemetryEvent -Times 2 -Exactly
            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                $Data['ActionName'] -eq 'Test' -and
                $Data['ErrorMessage'] -eq 'Handled error' -and
                -not $Data.ContainsKey('ActionConclusion')
            }
            Assert-MockCalled AddTelemetryEvent -Times 1 -Exactly -ParameterFilter {
                $Data['ActionConclusion'] -eq 'Success'
            }
        }

        It 'Honors SkipTelemetry when the action fails: <fail>' -TestCases @(
            @{ fail = $false }
            @{ fail = $true }
        ) {
            param($fail)
            & $wrapperPath -ActionName 'Test' -SkipTelemetry -Action {
                if ($fail) { throw 'Action failed' }
            }

            Assert-MockCalled AddTelemetryEvent -Times 0 -Exactly
            if ($fail) {
                $LASTEXITCODE | Should -Be 1
            }
        }
    }
}

Describe 'Repository environment telemetry' {
    InModuleScope TelemetryHelper {
        BeforeEach {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'savedServerUrl', Justification = 'Restored in AfterEach')]
            $savedServerUrl = $env:GITHUB_SERVER_URL
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'savedEventPath', Justification = 'Restored in AfterEach')]
            $savedEventPath = $env:GITHUB_EVENT_PATH
            $env:GITHUB_SERVER_URL = 'https://github.com'
            $env:GITHUB_EVENT_PATH = Join-Path $TestDrive 'event.json'
            '{"repository":{"fork":false}}' | Set-Content -LiteralPath $env:GITHUB_EVENT_PATH -Encoding UTF8
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'data', Justification = 'Used by tests in separate Pester scriptblocks')]
            $data = [System.Collections.Generic.Dictionary[string, string]]::new()
            Mock Write-Host {}
        }

        AfterEach {
            $env:GITHUB_SERVER_URL = $savedServerUrl
            $env:GITHUB_EVENT_PATH = $savedEventPath
        }

        It 'Classifies <url> as <expected>' -TestCases @(
            @{ url = 'https://github.com'; expected = 'GitHub.com' }
            @{ url = 'https://GITHUB.COM/'; expected = 'GitHub.com' }
            @{ url = 'https://contoso.ghe.com'; expected = 'GHEC' }
            @{ url = 'https://CONTOSO.GHE.COM/'; expected = 'GHEC' }
            @{ url = 'https://github.contoso.com'; expected = 'GHES' }
            @{ url = 'https://github.contoso.com:8443/'; expected = 'GHES' }
            @{ url = 'https://notghe.com'; expected = 'GHES' }
            @{ url = 'https://contoso.ghe.com.example.org'; expected = 'GHES' }
            @{ url = 'https://github.com.example.org'; expected = 'GHES' }
        ) {
            param($url, $expected)
            $env:GITHUB_SERVER_URL = $url

            Get-GitHubHostingType | Should -Be $expected
            Assert-MockCalled Write-Host -Times 0
        }

        It 'Reports Unknown for invalid server URL <url>' -TestCases @(
            @{ url = '' }
            @{ url = 'not a URL' }
            @{ url = 'github.com' }
            @{ url = 'file:///tmp/github.com' }
        ) {
            param($url)
            $env:GITHUB_SERVER_URL = $url

            Get-GitHubHostingType | Should -Be 'Unknown'
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -like '::Warning::*GITHUB_SERVER_URL*' }
        }

        It 'Uses the workflow repository fork flag, not the pull request source' -TestCases @(
            @{ repositoryFork = $true; headFork = $false; expected = 'true' }
            @{ repositoryFork = $false; headFork = $true; expected = 'false' }
        ) {
            param($repositoryFork, $headFork, $expected)
            @{
                repository = @{ fork = $repositoryFork }
                pull_request = @{ head = @{ repo = @{ fork = $headFork } } }
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:GITHUB_EVENT_PATH -Encoding UTF8

            Get-RepositoryIsFork | Should -Be $expected
            Assert-MockCalled Write-Host -Times 0
        }

        It 'Reports Unknown for unavailable or invalid fork metadata: <json>' -TestCases @(
            @{ json = '{}' }
            @{ json = '{"repository":{}}' }
            @{ json = '{"repository":{"fork":null}}' }
            @{ json = '{"repository":{"fork":"false"}}' }
            @{ json = '{"repository":{"fork":0}}' }
            @{ json = '{"repository":null}' }
            @{ json = 'null' }
            @{ json = '{invalid json' }
        ) {
            param($json)
            $json | Set-Content -LiteralPath $env:GITHUB_EVENT_PATH -Encoding UTF8

            Get-RepositoryIsFork | Should -Be 'Unknown'
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -like '::Warning::*GITHUB_EVENT_PATH*' }
        }

        It 'Reports Unknown when the event file is unavailable' -TestCases @(
            @{ missingPath = $true }
            @{ missingPath = $false }
        ) {
            param($missingPath)
            if ($missingPath) {
                $env:GITHUB_EVENT_PATH = $null
            }
            else {
                $env:GITHUB_EVENT_PATH = Join-Path $TestDrive 'missing.json'
            }

            Get-RepositoryIsFork | Should -Be 'Unknown'
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -like '::Warning::*GITHUB_EVENT_PATH*' }
        }

        It 'Adds repository dimensions to events without replacing existing data' {
            Mock ReadSettings { return @{ microsoftTelemetryConnectionString = ''; partnerTelemetryConnectionString = '' } }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'BcContainerHelper' }
            Mock Get-ApplicationInsightsTelemetryClient { throw 'Telemetry must not be sent when disabled.' }
            $data.Add('ActionDuration', '42')

            AddTelemetryEvent -Message 'AL-Go action ran: Test' -Data $data

            $data['RepositoryIsFork'] | Should -Be 'false'
            $data['GitHubHostingType'] | Should -Be 'GitHub.com'
            $data['PowerShellVersion'] | Should -Be $PSVersionTable.PSVersion.ToString()
            $data['ActionDuration'] | Should -Be '42'
            Assert-MockCalled ReadSettings -Times 1 -Exactly
            Assert-MockCalled Get-ApplicationInsightsTelemetryClient -Times 0
        }

        It 'Continues logging existing telemetry when new metadata is invalid' {
            Mock ReadSettings { return @{ microsoftTelemetryConnectionString = ''; partnerTelemetryConnectionString = '' } }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'BcContainerHelper' }
            $env:GITHUB_SERVER_URL = 'invalid'
            '{invalid json' | Set-Content -LiteralPath $env:GITHUB_EVENT_PATH -Encoding UTF8

            AddTelemetryEvent -Message 'AL-Go workflow ran' -Data $data

            $data['RepositoryIsFork'] | Should -Be 'Unknown'
            $data['GitHubHostingType'] | Should -Be 'Unknown'
            $data['PowerShellVersion'] | Should -Be $PSVersionTable.PSVersion.ToString()
            Assert-MockCalled ReadSettings -Times 1 -Exactly
            Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like 'Failed to log telemetry event:*' }
        }

        It 'Uses the action telemetry token when resolving conditional settings' {
            $savedTelemetryToken = $script:telemetryToken
            $savedGitHubToken = $env:GITHUB_TOKEN
            try {
                $script:telemetryToken = 'telemetry-token'
                $env:GITHUB_TOKEN = 'workflow-token'
                Mock ReadSettings { return @{ microsoftTelemetryConnectionString = ''; partnerTelemetryConnectionString = '' } }
                Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'BcContainerHelper' }

                AddTelemetryEvent -Message 'Action completed' -Data $data

                Assert-MockCalled ReadSettings -Times 1 -Exactly -ParameterFilter { $githubToken -eq 'telemetry-token' }
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like 'Failed to log telemetry event:*' }
            }
            finally {
                $script:telemetryToken = $savedTelemetryToken
                $env:GITHUB_TOKEN = $savedGitHubToken
            }
        }

        It 'Falls back to the existing GitHub token for telemetry settings' {
            $savedTelemetryToken = $script:telemetryToken
            $savedGitHubToken = $env:GITHUB_TOKEN
            try {
                $script:telemetryToken = ''
                $env:GITHUB_TOKEN = 'workflow-token'
                Mock ReadSettings { return @{ microsoftTelemetryConnectionString = ''; partnerTelemetryConnectionString = '' } }
                Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'BcContainerHelper' }

                AddTelemetryEvent -Message 'Action completed' -Data $data

                Assert-MockCalled ReadSettings -Times 1 -Exactly -ParameterFilter { $githubToken -eq 'workflow-token' }
            }
            finally {
                $script:telemetryToken = $savedTelemetryToken
                $env:GITHUB_TOKEN = $savedGitHubToken
            }
        }

        It 'Resolves telemetry settings through an authenticated custom-property request' {
            $savedTelemetryToken = $script:telemetryToken
            $savedEnvironment = @{}
            foreach ($name in @('GITHUB_TOKEN', 'GITHUB_API_URL', 'GITHUB_REPOSITORY', 'GITHUB_WORKSPACE', 'ALGoOrgSettings', 'ALGoRepoSettings', 'ALGoEnvSettings')) {
                $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            }
            try {
                $script:telemetryToken = 'telemetry-token'
                $env:GITHUB_TOKEN = ''
                $env:GITHUB_API_URL = 'https://api.example.test'
                $env:GITHUB_REPOSITORY = 'owner/telemetry-test'
                $env:GITHUB_WORKSPACE = $TestDrive
                $env:ALGoRepoSettings = ''
                $env:ALGoEnvSettings = ''
                $env:ALGoOrgSettings = @{
                    microsoftTelemetryConnectionString = ''
                    ConditionalSettings = @(
                        @{
                            customProperties = @{ BusinessUnit = @('Food') }
                            settings = @{ partnerTelemetryConnectionString = '' }
                        }
                    )
                } | ConvertTo-Json -Depth 10
                InModuleScope ReadSettings { $script:CustomPropertiesCache.Clear() }
                Mock GetHeaders -ModuleName ReadSettings { @{ Authorization = "token $token" } }
                Mock InvokeWebRequest -ModuleName ReadSettings {
                    if ($headers.Authorization -ne 'token telemetry-token') {
                        throw '404 Not Found: missing authentication'
                    }
                    [PSCustomObject]@{ Content = '[{"property_name":"BusinessUnit","value":"Food"}]' }
                }
                Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'BcContainerHelper' }
                Mock Get-ApplicationInsightsTelemetryClient { throw 'Telemetry must not be sent when disabled.' }

                AddTelemetryEvent -Message 'Action completed' -Data $data

                Assert-MockCalled Get-ApplicationInsightsTelemetryClient -Times 0
                Should -Invoke InvokeWebRequest -ModuleName ReadSettings -Times 1 -Exactly -ParameterFilter {
                    $headers.Authorization -eq 'token telemetry-token'
                }
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like 'Failed to log telemetry event:*' }
            }
            finally {
                $script:telemetryToken = $savedTelemetryToken
                foreach ($name in $savedEnvironment.Keys) {
                    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
                }
                InModuleScope ReadSettings { $script:CustomPropertiesCache.Clear() }
            }
        }
    }
}
