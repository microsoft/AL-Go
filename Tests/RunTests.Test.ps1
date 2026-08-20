[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

# Stub for the BcContainerHelper function so it can be mocked within the module scope
function Get-AppJsonFromAppFile { param($appFile) }
function Get-BcContainerEventLog { param($containerName, [switch] $doNotOpen) }

Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/RunTests.psm1' -Resolve) -DisableNameChecking -Force

Describe 'RunTests.psm1 Tests' {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testCredential', Justification = 'Used in tests')]
        $testCredential = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "password" -AsPlainText -Force))
        $script:compiledAppMetadataByPath = @{}
        $script:testFoldersByProject = @{}

        function New-TestProject {
            Param(
                [string[]] $CompiledTestApps = @(),
                [hashtable] $CompiledAppIds = @{}
            )
            $projectPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $testAppsFolder = Join-Path (Join-Path $projectPath ".buildartifacts") "TestApps"
            New-Item -Path $testAppsFolder -ItemType Directory -Force | Out-Null
            $testFolders = @()
            $index = 0
            foreach ($app in $CompiledTestApps) {
                $index++
                $appPath = Join-Path $testAppsFolder $app
                New-Item -Path $appPath -ItemType File -Force | Out-Null
                $appId = if ($CompiledAppIds.ContainsKey($app)) { "$($CompiledAppIds[$app])" } else { [Guid]::NewGuid().ToString() }
                $appName = [System.IO.Path]::GetFileNameWithoutExtension($app)
                $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($appPath)] = [PSCustomObject]@{
                    id   = $appId
                    name = $appName
                }

                $testFolder = "TestApp$index"
                $testFolderPath = Join-Path $projectPath $testFolder
                New-Item -Path $testFolderPath -ItemType Directory -Force | Out-Null
                @{ id = $appId; name = $appName } | ConvertTo-Json |
                    Set-Content -Path (Join-Path $testFolderPath "app.json") -Encoding UTF8
                $testFolders += $testFolder
            }
            $script:testFoldersByProject[$projectPath] = @($testFolders)
            return $projectPath
        }

        function Get-TestFoldersForProject {
            Param(
                [string] $ProjectPath
            )

            return @($script:testFoldersByProject[$ProjectPath])
        }
    }

    BeforeEach {
        $script:eventLogSource = Join-Path $TestDrive "$([Guid]::NewGuid()).evtx"
        Set-Content -Path $script:eventLogSource -Value 'post-test-events' -Encoding UTF8
        Mock -ModuleName RunTests Get-AppJsonFromAppFile {
            $fullPath = [System.IO.Path]::GetFullPath("$appFile")
            if (-not $script:compiledAppMetadataByPath.ContainsKey($fullPath)) {
                throw "No test metadata configured for '$appFile'."
            }
            return $script:compiledAppMetadataByPath[$fullPath]
        }
        Mock -ModuleName RunTests Get-BcContainerEventLog { return $script:eventLogSource }
        Mock -ModuleName RunTests Install-AlTool { return '1.2.3' }
    }

    Context 'Nested AlTool module integration' {
        It 'Resolves both public integration functions from the nested module' {
            InModuleScope RunTests {
                (Get-Command Install-AlTool -ErrorAction Stop).Name | Should -Be 'Install-AlTool'
                (Get-Command Invoke-AlToolTestRun -ErrorAction Stop).Name | Should -Be 'Invoke-AlToolTestRun'
            }
        }
    }

    Context 'Get-TestAppsToRun' {
        It 'Collects compiled test apps from the build artifacts folder' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath

            @($testApps).Count | Should -Be 2
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

            $settings = @{ runTestsInAllInstalledTestApps = $true; testFolders = @() }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            @($testApps).Count | Should -Be 2
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

            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            @($testApps).Count | Should -Be 1
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not throw and returns compiled test apps when installTestAppsJson is an empty array' {
            # Regression: in Windows PowerShell 5.1 ConvertFrom-Json emits a JSON array as a single
            # object, so an empty '[]' previously surfaced as a one-element System.Object[] and threw
            # "does not contain a method named 'TrimStart'". A test project with no installed test apps
            # (the common case) must still return its compiled test apps without throwing.
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @() | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{
                runTestsInAllInstalledTestApps = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            @($testApps).Count | Should -Be 1
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Includes a single installed test app when runTestsInAllInstalledTestApps is set' {
            # Regression: a single-element JSON array must enumerate to the string element (not the
            # whole array) on both Windows PowerShell 5.1 and PowerShell 7.
            $projectPath = New-TestProject
            $installedApp = Join-Path $projectPath 'Installed1.app'
            New-Item -Path $installedApp -ItemType File -Force | Out-Null
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @("($installedApp)") | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{ runTestsInAllInstalledTestApps = $true; testFolders = @() }
            $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson

            @($testApps).Count | Should -Be 1
            $testApps | Should -Contain $installedApp
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Selects only compiled apps whose IDs belong to normal test folders' {
            $projectPath = New-TestProject -CompiledTestApps @('Normal.Test.app', 'Performance.Test.app')
            $testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @($testFolders[0])
                bcptTestFolders                = @($testFolders[1])
            }

            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath)

            $testApps.Count | Should -Be 1
            [System.IO.Path]::GetFileName($testApps[0]) | Should -Be 'Normal.Test.app'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Selects one compiled artifact when normal test folders contain duplicate app IDs' {
            $duplicateAppId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('Duplicate1.Test.app', 'Duplicate2.Test.app') -CompiledAppIds @{
                'Duplicate1.Test.app' = $duplicateAppId
                'Duplicate2.Test.app' = $duplicateAppId
            }
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath)

            $testApps.Count | Should -Be 1
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports corrupt normal source app metadata clearly' {
            $projectPath = New-TestProject
            $testFolder = Join-Path $projectPath 'BrokenTestApp'
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $testFolder 'app.json') -Value '{invalid' -Encoding UTF8
            $settings = @{ runTestsInAllInstalledTestApps = $false; testFolders = @('BrokenTestApp') }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath } |
                Should -Throw "*Failed to read normal test app metadata*BrokenTestApp*app.json*"

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports unreadable compiled app metadata clearly' {
            $projectPath = New-TestProject -CompiledTestApps @('Broken.Test.app')
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { throw 'corrupt package' }
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath } |
                Should -Throw "*Failed to read compiled test app metadata*Broken.Test.app*corrupt package*"

            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Invoke-AlGoTestRun' {
        It 'Does not run tests when there are no test apps' {
            $projectPath = New-TestProject
            $script:runnerCalls = 0
            Mock -ModuleName RunTests Invoke-AlToolTestRun { $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false; testFolders = @() }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential

            $script:runnerCalls | Should -Be 0
            Should -Invoke -ModuleName RunTests Install-AlTool -Times 0 -Exactly
            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Test-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml') | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies passing test results to build artifacts and preserves the root result' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $script:runnerCalls = 0
            $script:capturedOverrideKeys = @()
            $script:resultContent = '<testsuites name="passing" />'
            $override = {
                param($parameters)
                $script:runnerCalls++
                $script:capturedOverrideKeys = @($parameters.Keys)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $true
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            $script:runnerCalls | Should -Be 2
            Should -Invoke -ModuleName RunTests Install-AlTool -Times 0 -Exactly
            @($script:capturedOverrideKeys | Sort-Object) | Should -Be @(
                'AppendToJUnitResultFile',
                'appName',
                'companyName',
                'containerName',
                'credential',
                'detailed',
                'disabledTests',
                'extensionId',
                'GitHubActions',
                'JUnitResultFileName',
                'returnTrueIfAllPassed'
            )
            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not create an artifact when test execution produces no result file' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            Set-Content -Path $artifactResult -Value '<testsuites name="stale" />' -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride { return $true }

            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Test-Path $artifactResult | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Invokes only the normal test app when compiled artifacts also contain a BCPT app' {
            $projectPath = New-TestProject -CompiledTestApps @('Normal.Test.app', 'Performance.Test.app')
            $testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            $script:invokedExtensionIds = @()
            $override = {
                param($parameters)
                $script:invokedExtensionIds += "$($parameters.extensionId)"
                return $true
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @($testFolders[0])
                bcptTestFolders                = @($testFolders[1])
            }
            $normalAppPath = Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestApps') 'Normal.Test.app'
            $normalAppId = "$($script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($normalAppPath)].id)"

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:invokedExtensionIds | Should -Be @($normalAppId)
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes nested and project-wide disabled tests to an override as recursive hashtables' {
            $appId = [Guid]::NewGuid().ToString()
            $otherAppId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }

            $testFolder = Join-Path $projectPath 'TestApp'
            $nestedFolder = Join-Path $testFolder 'Nested'
            New-Item -Path $nestedFolder -ItemType Directory -Force | Out-Null
            @{ id = $appId } | ConvertTo-Json | Set-Content -Path (Join-Path $testFolder 'app.json') -Encoding UTF8
            @(
                @{
                    codeunitName = 'Nested Tests'
                    method       = @('TestOne')
                    metadata     = @{ issue = @{ id = 123 } }
                }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nestedFolder 'disabledTests.json') -Encoding UTF8

            $otherTestFolder = Join-Path $projectPath 'OtherTestApp'
            New-Item -Path $otherTestFolder -ItemType Directory -Force | Out-Null
            @{ id = $otherAppId } | ConvertTo-Json | Set-Content -Path (Join-Path $otherTestFolder 'app.json') -Encoding UTF8
            @(@{ codeunitName = 'Other Tests'; method = 'Ignored' }) | ConvertTo-Json | Set-Content -Path (Join-Path $otherTestFolder 'disabledTests.json') -Encoding UTF8

            $projectSettingsFolder = Join-Path $projectPath '.AL-Go'
            New-Item -Path $projectSettingsFolder -ItemType Directory -Force | Out-Null
            @(@{ codeunitName = 'Project Tests'; method = 'TestTwo' }) | ConvertTo-Json | Set-Content -Path (Join-Path $projectSettingsFolder "$appId.disabledTests.json") -Encoding UTF8

            $script:capturedDisabledTests = @()
            $override = { param($parameters) $script:capturedDisabledTests = @($parameters.disabledTests); return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @('TestApp', 'OtherTestApp')
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedDisabledTests.Count | Should -Be 2
            $nestedDisabledTest = $script:capturedDisabledTests | Where-Object { $_.codeunitName -eq 'Nested Tests' }
            $nestedDisabledTest | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata.issue | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata.issue.id | Should -Be 123
            $script:capturedDisabledTests.codeunitName | Should -Contain 'Project Tests'
            $script:capturedDisabledTests.codeunitName | Should -Not -Contain 'Other Tests'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Fails with the disabled tests file path when its JSON is invalid' {
            $appId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            $testFolder = Join-Path $projectPath 'TestApp'
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            @{ id = $appId } | ConvertTo-Json | Set-Content -Path (Join-Path $testFolder 'app.json') -Encoding UTF8
            Set-Content -Path (Join-Path $testFolder 'disabledTests.json') -Value '{invalid' -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @('TestApp')
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride { return $true } } |
                Should -Throw '*disabledTests.json*'

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies failed test results before throwing when treatTestFailuresAsWarnings is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:resultContent = '<testsuites name="hard-failure" />'
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $false
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*There are test failures*'

            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies failed test results when treatTestFailuresAsWarnings is set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:resultContent = '<testsuites name="warning-failure" />'
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $false
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Surfaces artifact copy errors before a test failure message' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value '<testsuites name="copy-error" />' -Encoding UTF8
                return $false
            }
            Mock -ModuleName RunTests Copy-Item { throw 'copy blocked' }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*Failed to copy test results*copy blocked*'

            Should -Invoke -ModuleName RunTests Get-BcContainerEventLog -Times 1 -Exactly
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity error when treatTestFailuresAsWarnings is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedSeverity | Should -Be 'error'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity warning when treatTestFailuresAsWarnings is set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

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
            if (($command -is [System.Management.Automation.AliasInfo]) -and $command.ResolvedCommand) { $command = $command.ResolvedCommand }

            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedParams = $null
            $override = { param($parameters) $script:capturedParams = $parameters; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

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

    Context 'Invoke-AlGoTestRun (default AlTool runner)' {
        It 'Runs the AlTool runner for every test app when no override is supplied' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $true }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential } | Should -Not -Throw

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 2 -Exactly
            Should -Invoke -ModuleName RunTests Install-AlTool -Times 1 -Exactly
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Maps only the built-in runner parameters with the expected defaults' {
            $appId = [Guid]::NewGuid().ToString()
            $script:capturedAlToolParams = $null
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                param(
                    $ContainerName,
                    [System.Management.Automation.PSCredential] $Credential,
                    $ExtensionId,
                    $AppName,
                    $CompanyName,
                    $Tenant,
                    $DisabledTests,
                    $TestType,
                    $JUnitResultFileName
                )
                $script:capturedAlToolParams = @{
                    Keys                = @($PSBoundParameters.Keys)
                    ContainerName       = $ContainerName
                    Credential          = $Credential
                    ExtensionId         = $ExtensionId
                    AppName             = $AppName
                    CompanyName         = $CompanyName
                    Tenant              = $Tenant
                    DisabledTests       = @($DisabledTests)
                    TestType            = $TestType
                    JUnitResultFileName = $JUnitResultFileName
                }
                return $true
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = 'CRONUS'
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'mycontainer' -credential $testCredential

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly
            Should -Invoke -ModuleName RunTests Install-AlTool -Times 1 -Exactly
            @($script:capturedAlToolParams.Keys | Sort-Object) | Should -Be @(
                'AppName',
                'CompanyName',
                'ContainerName',
                'Credential',
                'DisabledTests',
                'ExtensionId',
                'JUnitResultFileName',
                'Tenant',
                'TestType'
            )
            $script:capturedAlToolParams.ContainerName | Should -Be 'mycontainer'
            $script:capturedAlToolParams.Credential | Should -BeOfType [System.Management.Automation.PSCredential]
            $script:capturedAlToolParams.ExtensionId | Should -Be $appId
            $script:capturedAlToolParams.AppName | Should -Be 'App1.Test'
            $script:capturedAlToolParams.CompanyName | Should -Be 'CRONUS'
            $script:capturedAlToolParams.Tenant | Should -Be 'default'
            $script:capturedAlToolParams.DisabledTests.Count | Should -Be 0
            $script:capturedAlToolParams.TestType | Should -Be ''
            $script:capturedAlToolParams.JUnitResultFileName | Should -Be (Join-Path $projectPath 'TestResults.xml')
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes project-wide disabled tests to the AlTool runner' {
            $appId = [Guid]::NewGuid().ToString()
            $script:capturedAlToolParams = $null
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                param($DisabledTests)
                $script:capturedAlToolParams = @($DisabledTests)
                return $true
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            @(@{ codeunitName = 'Project Tests'; method = 'TestOne' }) | ConvertTo-Json |
                Set-Content -Path (Join-Path $projectPath "$appId.disabledTests.json") -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly
            $script:capturedAlToolParams.Count | Should -Be 1
            $script:capturedAlToolParams[0].codeunitName | Should -Be 'Project Tests'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Throws when the AlTool runner reports failure and treatTestFailuresAsWarnings is not set' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $false }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential } | Should -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not throw when the AlTool runner reports failure but treatTestFailuresAsWarnings is set' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $false }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential } | Should -Not -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Invoke-AlGoTestRun event log lifecycle' {
        It 'Captures after a passing no-result test run with the expected root path and API parameters' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            Set-Content -Path $eventLogDestination -Value 'pre-test-events' -Encoding UTF8
            $script:invocationOrder = @()
            $runTestsOverride = {
                param($parameters)
                $script:invocationOrder += 'run'
                return $true
            }
            Mock -ModuleName RunTests Get-BcContainerEventLog {
                $script:invocationOrder += 'capture'
                return $script:eventLogSource
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride $runTestsOverride

            $script:invocationOrder | Should -Be @('run', 'capture')
            Should -Invoke -ModuleName RunTests Get-BcContainerEventLog -Times 1 -Exactly -ParameterFilter {
                $containerName -eq 'kept-container' -and $doNotOpen
            }
            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Captures after a hard test failure and rethrows that failure' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { return $false } } |
                Should -Throw '*There are test failures*'

            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Preserves the original hard test failure when event log capture also fails' {
            Mock -ModuleName RunTests OutputWarning {}
            Mock -ModuleName RunTests Get-BcContainerEventLog { throw 'event export failed' }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            try {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { return $false }
                throw 'Expected the test run to fail.'
            }
            catch {
                $_.Exception.Message | Should -Be 'There are test failures.'
            }

            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*Tests failed*event log could not be captured*event export failed*'
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Surfaces event log capture failure after passing tests and preserves the stale diagnostic' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            Set-Content -Path $eventLogDestination -Value 'pre-test-events' -Encoding UTF8
            Mock -ModuleName RunTests Get-BcContainerEventLog { return (Join-Path $TestDrive 'missing.evtx') }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { return $true } } |
                Should -Throw "*Failed to capture event log*did not return a readable event log file*"

            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'pre-test-events'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Captures after warning-mode test failures' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { return $false } } |
                Should -Not -Throw

            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Captures for a no-test run' {
            $projectPath = New-TestProject
            $script:runnerCalls = 0
            $runTestsOverride = { param($parameters) $script:runnerCalls++; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @()
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride $runTestsOverride

            $script:runnerCalls | Should -Be 0
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Captures after a runner exception and preserves that exception' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { throw 'runner failed' } } |
                Should -Throw '*runner failed*'

            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Remove-Item -Path $projectPath -Recurse -Force
        }
    }
}
