[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Test doubles mirror BcContainerHelper cmdlet names')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/PipelinePhases.psm1' -Resolve) -DisableNameChecking -Force

Describe 'PipelinePhases.psm1 Tests' {
    BeforeAll {
        # Define global test doubles for the BcContainerHelper / AL-Go-Helper cmdlets the phases call.
        # The module resolves these unqualified names via the global scope; Mock (from InModuleScope)
        # then intercepts them. They don't exist on the test host (no Docker / BcContainerHelper).
        function global:New-BcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Set-BcContainerKeyVaultAadAppAndCertificate { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Publish-BcContainerApp { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Import-TestToolkitToBcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Backup-BcContainerDatabases { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Run-TestsInBcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Run-BCPTTestsInBcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Test-BcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) return $true }
        function global:Get-BcContainerEventLog { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Remove-BcContainer { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
        function global:Assert-DockerIsRunning { param([Parameter(ValueFromRemainingArguments = $true)] $rest) }
    }

    AfterAll {
        'New-BcContainer', 'Set-BcContainerKeyVaultAadAppAndCertificate', 'Publish-BcContainerApp',
        'Import-TestToolkitToBcContainer', 'Backup-BcContainerDatabases', 'Run-TestsInBcContainer',
        'Run-BCPTTestsInBcContainer', 'Test-BcContainer', 'Get-BcContainerEventLog',
        'Remove-BcContainer', 'Assert-DockerIsRunning' | ForEach-Object {
            Remove-Item "function:global:$_" -ErrorAction SilentlyContinue
        }
    }


    Context 'Get-PipelineContextPath' {
        It 'Returns a deterministic, sanitized path per project' {
            $env:RUNNER_TEMP = $TestDrive
            $p1 = Get-PipelineContextPath -project 'MyProject'
            $p2 = Get-PipelineContextPath -project 'MyProject'
            $p1 | Should -Be $p2
            (Split-Path $p1 -Leaf) | Should -Be 'AlGoPipelineContext.MyProject.json'
        }
        It 'Maps root project to a stable file name' {
            $env:RUNNER_TEMP = $TestDrive
            (Split-Path (Get-PipelineContextPath -project '.') -Leaf) | Should -Be 'AlGoPipelineContext.root.json'
        }
        It 'Sanitizes unsafe project names' {
            $env:RUNNER_TEMP = $TestDrive
            (Split-Path (Get-PipelineContextPath -project 'a/b c') -Leaf) | Should -Be 'AlGoPipelineContext.a_b_c.json'
        }
    }

    Context 'Save/Restore-PipelineContext' {
        It 'Round-trips context through disk' {
            $env:RUNNER_TEMP = $TestDrive
            $ctx = @{ containerName = 'bc123'; environmentCreated = $true; publishedApps = @('a.app', 'b.app') }
            Save-PipelineContext -context $ctx -project 'P' | Out-Null
            $restored = Restore-PipelineContext -project 'P'
            $restored.containerName | Should -Be 'bc123'
            $restored.environmentCreated | Should -Be $true
            @($restored.publishedApps).Count | Should -Be 2
        }
        It 'Throws a helpful error when context is missing' {
            $env:RUNNER_TEMP = $TestDrive
            { Restore-PipelineContext -project 'DoesNotExist' } | Should -Throw '*context file not found*'
        }
    }

    Context 'Assert-ModularBuildSupported' {
        It 'Throws when useCompilerFolder is false' {
            { Assert-ModularBuildSupported -settings @{ useCompilerFolder = $false } } | Should -Throw '*useCompilerFolder*'
        }
        It 'Passes when useCompilerFolder is true' {
            { Assert-ModularBuildSupported -settings @{ useCompilerFolder = $true } } | Should -Not -Throw
        }
    }

    Context 'Get-CompiledApps' {
        It 'Returns .app files from the requested subfolder' {
            $buildArtifacts = Join-Path $TestDrive 'ba'
            $appsFolder = Join-Path $buildArtifacts 'Apps'
            New-Item -ItemType Directory -Path $appsFolder -Force | Out-Null
            'x' | Set-Content (Join-Path $appsFolder 'one.app')
            'x' | Set-Content (Join-Path $appsFolder 'two.app')
            'x' | Set-Content (Join-Path $appsFolder 'ignore.txt')
            $apps = Get-CompiledApps -buildArtifactFolder $buildArtifacts -subFolder 'Apps'
            @($apps).Count | Should -Be 2
        }
        It 'Returns empty when the subfolder is missing' {
            @(Get-CompiledApps -buildArtifactFolder (Join-Path $TestDrive 'nope') -subFolder 'TestApps').Count | Should -Be 0
        }
    }

    Context 'New-AlGoDevEnvironment' {
        It 'Skips creation when doNotPublishApps is set' {
            InModuleScope PipelinePhases {
                Mock New-BcContainer {}
                Mock Assert-DockerIsRunning {}
                $ctx = @{ settings = @{ doNotPublishApps = $true }; containerName = 'bc1' }
                $result = New-AlGoDevEnvironment -context $ctx
                $result.environmentCreated | Should -Be $false
                Should -Invoke New-BcContainer -Times 0
            }
        }
        It 'Creates the container and imports the test toolkit when tests will run' {
            InModuleScope PipelinePhases {
                Mock New-BcContainer {}
                Mock Assert-DockerIsRunning {}
                Mock Import-TestToolkitToBcContainer {}
                Mock Publish-BcContainerApp {}
                $ctx = @{
                    containerName = 'bc1'
                    artifactUrl   = 'https://bcartifacts/x'
                    auth          = 'UserPassword'
                    secrets       = @{ keyVaultCertificateUrl = ''; keyVaultCertificatePassword = ''; keyVaultClientId = '' }
                    buildArtifactFolder = (Join-Path $TestDrive 'ba2')
                    settings      = @{
                        doNotPublishApps = $false; doNotRunTests = $false; doNotRunBcptTests = $true
                        testFolders = @('Test'); bcptTestFolders = @(); installTestLibraries = $false
                        installPerformanceToolkit = $false; enableTaskScheduler = $false; assignPremiumPlan = $false; memoryLimit = ''
                    }
                }
                $result = New-AlGoDevEnvironment -context $ctx
                $result.environmentCreated | Should -Be $true
                $result.testToolkitInstalled | Should -Be $true
                Should -Invoke New-BcContainer -Times 1
                Should -Invoke Import-TestToolkitToBcContainer -Times 1
            }
        }
    }

    Context 'Publish-AlGoApps' {
        It 'Publishes each compiled app into the container' {
            InModuleScope PipelinePhases {
                Mock Publish-BcContainerApp {}
                $ba = Join-Path $TestDrive 'ba3'
                $appsFolder = Join-Path $ba 'Apps'
                New-Item -ItemType Directory -Path $appsFolder -Force | Out-Null
                'x' | Set-Content (Join-Path $appsFolder 'one.app')
                'x' | Set-Content (Join-Path $appsFolder 'two.app')
                $ctx = @{
                    containerName = 'bc1'; containerPassword = 'Aa1!secret'; buildArtifactFolder = $ba
                    settings = @{ doNotPublishApps = $false; skipUpgrade = $true; restoreDatabases = $false }
                }
                $result = Publish-AlGoApps -context $ctx
                @($result.publishedApps).Count | Should -Be 2
                Should -Invoke Publish-BcContainerApp -Times 2
            }
        }
        It 'Skips publishing when doNotPublishApps is set' {
            InModuleScope PipelinePhases {
                Mock Publish-BcContainerApp {}
                $ctx = @{ containerName = 'bc1'; settings = @{ doNotPublishApps = $true } }
                Publish-AlGoApps -context $ctx | Out-Null
                Should -Invoke Publish-BcContainerApp -Times 0
            }
        }
    }

    Context 'Invoke-AlGoTests' {
        It 'Runs tests when test folders are present' {
            InModuleScope PipelinePhases {
                Mock Run-TestsInBcContainer {}
                Mock Run-BCPTTestsInBcContainer {}
                $ctx = @{
                    containerName = 'bc1'; containerPassword = 'Aa1!secret'; projectPath = $TestDrive
                    companyName = 'CRONUS'; tenant = 'default'
                    settings = @{ doNotPublishApps = $false; doNotRunTests = $false; doNotRunBcptTests = $true; testFolders = @('Test'); bcptTestFolders = @() }
                }
                Invoke-AlGoTests -context $ctx | Out-Null
                Should -Invoke Run-TestsInBcContainer -Times 1
                Should -Invoke Run-BCPTTestsInBcContainer -Times 0
            }
        }

        It 'Skips tests (and does not require a container credential) when doNotPublishApps is set' {
            InModuleScope PipelinePhases {
                Mock Run-TestsInBcContainer {}
                Mock Run-BCPTTestsInBcContainer {}
                # No containerPassword in context - Get-PipelineCredential would throw if called.
                $ctx = @{
                    containerName = 'bc1'; projectPath = $TestDrive
                    settings = @{ doNotPublishApps = $true; doNotRunTests = $false; doNotRunBcptTests = $false; testFolders = @('Test'); bcptTestFolders = @() }
                }
                { Invoke-AlGoTests -context $ctx } | Should -Not -Throw
                Should -Invoke Run-TestsInBcContainer -Times 0
                Should -Invoke Run-BCPTTestsInBcContainer -Times 0
            }
        }
    }

    Context 'Remove-AlGoDevEnvironment' {
        It 'Removes the container by default' {
            InModuleScope PipelinePhases {
                Mock Test-BcContainer { return $true }
                Mock Get-BcContainerEventLog { return (Join-Path $TestDrive 'evt.evtx') }
                Mock Remove-BcContainer {}
                'x' | Set-Content (Join-Path $TestDrive 'evt.evtx')
                $ctx = @{ containerName = 'bc1'; projectPath = $TestDrive }
                Remove-AlGoDevEnvironment -context $ctx
                Should -Invoke Remove-BcContainer -Times 1
            }
        }
        It 'Keeps the container when keepEnvironment is set' {
            InModuleScope PipelinePhases {
                Mock Test-BcContainer { return $true }
                Mock Get-BcContainerEventLog { return (Join-Path $TestDrive 'evt2.evtx') }
                Mock Remove-BcContainer {}
                'x' | Set-Content (Join-Path $TestDrive 'evt2.evtx')
                $ctx = @{ containerName = 'bc1'; projectPath = $TestDrive }
                Remove-AlGoDevEnvironment -context $ctx -keepEnvironment
                Should -Invoke Remove-BcContainer -Times 0
            }
        }
        It 'Skips removal (and never probes Docker) when no environment was created' {
            InModuleScope PipelinePhases {
                Mock Test-BcContainer { return $true }
                Mock Get-BcContainerEventLog {}
                Mock Remove-BcContainer {}
                $ctx = @{ containerName = 'bc1'; projectPath = $TestDrive; environmentCreated = $false }
                Remove-AlGoDevEnvironment -context $ctx
                Should -Invoke Test-BcContainer -Times 0
                Should -Invoke Remove-BcContainer -Times 0
            }
        }
    }
}
