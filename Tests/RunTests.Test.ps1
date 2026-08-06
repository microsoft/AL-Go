[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

# Stub for the BcContainerHelper function so it can be mocked within the module scope
function Get-AppJsonFromAppFile { param($appFile) }

Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/RunTests.psm1' -Resolve) -DisableNameChecking -Force

Describe 'RunTests.psm1 Tests' {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testCredential', Justification = 'Used in tests')]
        $testCredential = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "password" -AsPlainText -Force))

        function New-TestProject {
            Param(
                [string[]] $CompiledTestApps = @()
            )
            $projectPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $testAppsFolder = Join-Path $projectPath ".buildartifacts\TestApps"
            New-Item -Path $testAppsFolder -ItemType Directory -Force | Out-Null
            foreach ($app in $CompiledTestApps) {
                New-Item -Path (Join-Path $testAppsFolder $app) -ItemType File -Force | Out-Null
            }
            return $projectPath
        }
    }

    Context 'Get-TestAppsToRun' {
        It 'Collects compiled test apps from the build artifacts folder' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{ runTestsInAllInstalledTestApps = $false }

            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath

            $testApps.Count | Should -Be 2
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Includes installed test apps (unwrapping parentheses) when runTestsInAllInstalledTestApps is set' {
            $projectPath = New-TestProject
            $installedApp1 = Join-Path $projectPath 'Installed1.app'
            $installedApp2 = Join-Path $projectPath 'Installed2.app'
            New-Item -Path $installedApp1 -ItemType File -Force | Out-Null
            New-Item -Path $installedApp2 -ItemType File -Force | Out-Null
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($installedApp1, "($installedApp2)") | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{ runTestsInAllInstalledTestApps = $true }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            $testApps.Count | Should -Be 2
            $testApps | Should -Contain $installedApp1
            $testApps | Should -Contain $installedApp2
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Ignores installed test apps when runTestsInAllInstalledTestApps is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $installedApp = Join-Path $projectPath 'Installed1.app'
            New-Item -Path $installedApp -ItemType File -Force | Out-Null
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($installedApp) | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{ runTestsInAllInstalledTestApps = $false }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            $testApps.Count | Should -Be 1
            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Invoke-AlGoTestRun' {
        It 'Does not run tests when doNotRunTests is set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:runnerCalls = 0
            $override = { param($parameters) $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $true; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:runnerCalls | Should -Be 0
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not run tests when doNotPublishApps is set (no container kept alive)' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:runnerCalls = 0
            $override = { param($parameters) $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $false; doNotPublishApps = $true; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:runnerCalls | Should -Be 0
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not run tests when there are no test apps' {
            $projectPath = New-TestProject
            $script:runnerCalls = 0
            $override = { param($parameters) $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:runnerCalls | Should -Be 0
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Runs tests in every test app when tests pass' {
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $script:runnerCalls = 0
            $override = { param($parameters) $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            $script:runnerCalls | Should -Be 2
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Throws when a test fails and treatTestFailuresAsWarnings is not set' {
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $override = { param($parameters) return $false }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not throw when a test fails but treatTestFailuresAsWarnings is set' {
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $override = { param($parameters) return $false }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $true }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity error when treatTestFailuresAsWarnings is not set' {
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedSeverity | Should -Be 'error'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity warning when treatTestFailuresAsWarnings is set' {
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $true }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedSeverity | Should -Be 'warning'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Builds a parameter set that is valid for the real Run-TestsInBcContainer cmdlet' {
            # Guard against parameter drift: every key/value passed to the BcContainerHelper test
            # runner is validated against the real cmdlet signature (parameter names and ValidateSet
            # values). This catches invalid parameter names and out-of-set values locally instead of
            # only surfacing them in CI, where the real cmdlet is actually invoked.
            $command = Get-Command -Name 'Run-TestsInBcContainer' -ErrorAction SilentlyContinue
            if (-not $command) {
                Set-ItResult -Skipped -Because 'BcContainerHelper (Run-TestsInBcContainer) is not available in this environment'
                return
            }
            if ($command.ResolvedCommand) { $command = $command.ResolvedCommand }

            Mock -ModuleName RunTests Get-AppJsonFromAppFile { [PSCustomObject]@{ id = [Guid]::NewGuid().ToString(); name = 'TestApp' } }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedParams = $null
            $override = { param($parameters) $script:capturedParams = $parameters; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedParams | Should -Not -BeNullOrEmpty
            foreach ($key in $script:capturedParams.Keys) {
                $parameter = $command.Parameters[$key]
                $parameter | Should -Not -BeNullOrEmpty -Because "'$key' must be a real parameter of Run-TestsInBcContainer"

                $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1
                if ($validateSet) {
                    $validateSet.ValidValues | Should -Contain $script:capturedParams[$key] -Because "the value for '$key' must be one of its allowed ValidateSet values"
                }
            }

            Remove-Item -Path $projectPath -Recurse -Force
        }
    }
}
