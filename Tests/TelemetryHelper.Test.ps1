$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot '../Actions/TelemetryHelper.psm1') -Force -DisableNameChecking

Describe 'Repository environment telemetry' {
    InModuleScope TelemetryHelper {
        BeforeEach {
            $savedServerUrl = $env:GITHUB_SERVER_URL
            $savedEventPath = $env:GITHUB_EVENT_PATH
            $env:GITHUB_SERVER_URL = 'https://github.com'
            $env:GITHUB_EVENT_PATH = Join-Path $TestDrive 'event.json'
            '{"repository":{"fork":false}}' | Set-Content -LiteralPath $env:GITHUB_EVENT_PATH -Encoding UTF8
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
    }
}
