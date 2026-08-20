[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1' -Resolve) -DisableNameChecking -Force

Describe 'AlToolTestRunner.psm1 Tests' {

    BeforeAll {
        # Re-import in the run phase so the module functions are guaranteed to be available even when
        # this file runs in the same Invoke-Pester session as RunTests.Test.ps1. RunTests.psm1
        # imports AlToolTestRunner.psm1 as a nested module with -Force, which removes the standalone
        # module's functions from the global scope during discovery.
        Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1' -Resolve) -DisableNameChecking -Force
    }

    Context 'Module exports' {
        It 'Exports only the RunTests integration functions' {
            @(Get-Command -Module AlToolTestRunner).Name | Sort-Object |
                Should -Be @('Install-AlTool', 'Invoke-AlToolTestRun')
        }
    }

    Context 'Invoke-AlNativeCommand' {
        It 'Captures native stdout, stderr and exit code in Windows PowerShell 5 without terminating' {
            if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
                Set-ItResult -Skipped -Because 'Windows PowerShell 5 is only available on Windows'
                return
            }

            $modulePath = (Resolve-Path (Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1')).Path
            $windowsPowerShell = (Get-Command (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ErrorAction Stop).Source
            $childScript = '[Console]::Out.WriteLine("native-stdout"); [Console]::Error.WriteLine("native-stderr"); exit 23'
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
            $escapedModulePath = $modulePath.Replace("'", "''")
            $escapedWindowsPowerShell = $windowsPowerShell.Replace("'", "''")

            $parentScript = @"
`$ErrorActionPreference = 'Stop'
`$module = Import-Module '$escapedModulePath' -Force -PassThru
`$result = & `$module {
    Invoke-AlNativeCommand -FilePath '$escapedWindowsPowerShell' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-EncodedCommand', '$encodedChildScript'
    )
}
@{
    StandardOutput = @(`$result.StandardOutput)
    StandardError = @(`$result.StandardError)
    Output = @(`$result.Output)
    ExitCode = `$result.ExitCode
    ErrorActionPreference = "`$ErrorActionPreference"
} | ConvertTo-Json -Compress
"@
            $encodedParentScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($parentScript))

            $parentOutput = & $windowsPowerShell -NoLogo -NoProfile -EncodedCommand $encodedParentScript 2>&1
            $parentExitCode = $LASTEXITCODE

            $parentExitCode | Should -Be 0
            $payload = ($parentOutput -join "`n") | ConvertFrom-Json
            $payload.ExitCode | Should -Be 23
            $payload.ErrorActionPreference | Should -Be 'Stop'
            @($payload.StandardOutput) | Should -Be @('native-stdout')
            @($payload.StandardError) | Should -Be @('native-stderr')
            ($payload.Output -join "`n") | Should -Match 'native-stdout'
            ($payload.Output -join "`n") | Should -Match 'native-stderr'
        }

        It 'Separates native stdout and stderr in the current PowerShell process' {
            $powerShell = (Get-Process -Id $PID).Path
            $childScript = '[Console]::Out.WriteLine("native-stdout"); [Console]::Error.WriteLine("native-stderr"); exit 29'
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

            InModuleScope AlToolTestRunner -Parameters @{
                PowerShellPath = $powerShell
                EncodedScript  = $encodedChildScript
            } {
                $result = Invoke-AlNativeCommand -FilePath $PowerShellPath -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-EncodedCommand', $EncodedScript
                )

                $result.ExitCode | Should -Be 29
                $result.StandardOutput | Should -Be @('native-stdout')
                $result.StandardError | Should -Be @('native-stderr')
                $result.Output | Should -Be @('native-stdout', 'native-stderr')
            }
        }

        It 'Does not swallow command-not-found errors' {
            InModuleScope AlToolTestRunner {
                { Invoke-AlNativeCommand -FilePath 'al-go-command-that-does-not-exist' } |
                    Should -Throw
            }
        }

        It 'Does not swallow native invocation failures' {
            if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
                Set-ItResult -Skipped -Because 'The invalid Windows executable fixture is Windows-specific'
                return
            }

            $invalidExecutable = Join-Path $TestDrive 'invalid.exe'
            Set-Content -Path $invalidExecutable -Value 'not an executable' -Encoding ASCII

            InModuleScope AlToolTestRunner -Parameters @{ InvalidExecutable = $invalidExecutable } {
                { Invoke-AlNativeCommand -FilePath $InvalidExecutable } |
                    Should -Throw '*failed to run*'
            }
        }
    }

    Context 'Install-AlTool native command handling' {
        InModuleScope AlToolTestRunner {
        It 'Falls back to update after install failure only when al is still unavailable' {
            $script:availabilityChecks = 0
            Mock -ModuleName AlToolTestRunner Get-Command {
                $script:availabilityChecks++
                if ($script:availabilityChecks -eq 1) { return $null }
                return [PSCustomObject]@{ Source = 'al' }
            } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@('install failed')
                        Output         = [string[]]@('install failed')
                        ExitCode       = [int] 1
                    }
                }
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('1.2.3')
                    StandardError  = [string[]]@()
                    Output         = [string[]]@('1.2.3')
                    ExitCode       = [int] 0
                }
            }

            Install-AlTool | Should -Be '1.2.3'

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlNativeCommand -Times 0 -Exactly -ParameterFilter {
                $FilePath -eq 'dotnet' -and $ArgumentList[1] -eq 'update'
            }
        }

        It 'Reports a failed fallback update clearly' {
            Mock -ModuleName AlToolTestRunner Get-Command { return $null } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                if ($ArgumentList[1] -eq 'install') {
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@('install failed')
                        Output         = [string[]]@('install failed')
                        ExitCode       = [int] 1
                    }
                }
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@('update stderr')
                    Output         = [string[]]@('update stderr')
                    ExitCode       = [int] 17
                }
            }

            { Install-AlTool } | Should -Throw '*fallback dotnet tool update exited with code 17*update stderr*'
        }

        It 'Warns on forced update failure and uses the existing version' {
            Mock -ModuleName AlToolTestRunner Get-Command { return [PSCustomObject]@{ Source = 'al' } } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Write-Host {}
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@('update stderr')
                        Output         = [string[]]@('update stderr')
                        ExitCode       = [int] 9
                    }
                }
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('1.2.3')
                    StandardError  = [string[]]@()
                    Output         = [string[]]@('1.2.3')
                    ExitCode       = [int] 0
                }
            }

            Install-AlTool -Force | Should -Be '1.2.3'

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 1 -Exactly -ParameterFilter {
                "$Object" -like "WARNING: 'al' update check exited with code 9*"
            }
        }

        It 'Reports al version failure explicitly' {
            Mock -ModuleName AlToolTestRunner Get-Command { return [PSCustomObject]@{ Source = 'al' } } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@('version stderr')
                    Output         = [string[]]@('version stderr')
                    ExitCode       = [int] 11
                }
            }

            { Install-AlTool } | Should -Throw "*'al --version'*exited with code 11*version stderr*"
        }
        }
    }

    Context 'Get-DisabledTestKeySet' {
        InModuleScope AlToolTestRunner {
        It 'Builds per-method keys and whole-codeunit sets from a wildcard' {
            $disabled = @(
                [PSCustomObject]@{ codeunitName = 'My Tests'; method = 'TestOne' },
                [PSCustomObject]@{ codeunitName = 'Whole CU'; method = '*' }
            )

            $lookup = Get-DisabledTestKeySet -DisabledTests $disabled

            $lookup.Methods.ContainsKey('my tests::testone') | Should -BeTrue
            $lookup.Codeunits.ContainsKey('whole cu') | Should -BeTrue
            $lookup.Methods.ContainsKey('whole cu::*') | Should -BeFalse
        }

        It 'Returns empty sets for an empty list' {
            $lookup = Get-DisabledTestKeySet -DisabledTests @()
            $lookup.Methods.Count | Should -Be 0
            $lookup.Codeunits.Count | Should -Be 0
        }
        }
    }

    Context 'Get-AlToolTestCodeunits' {
        InModuleScope AlToolTestRunner {
        It 'Enumerates codeunits and filters disabled methods and whole codeunits' {
            Mock -ModuleName AlToolTestRunner Get-TestsFromBcContainer {
                @(
                    [PSCustomObject]@{ Id = 130001; Name = 'My Tests'; Tests = @('TestOne', 'TestTwo') },
                    [PSCustomObject]@{ Id = 130002; Name = 'Whole CU'; Tests = @('X', 'Y') }
                )
            }
            $testCodeunitParams = @{
                ContainerName = 'test'
                Credential    = (New-Object System.Management.Automation.PSCredential('admin', (ConvertTo-SecureString 'password' -AsPlainText -Force)))
                ExtensionId   = [Guid]::NewGuid().ToString()
                DisabledTests = @(
                    [PSCustomObject]@{ codeunitName = 'My Tests'; method = 'TestTwo' },
                    [PSCustomObject]@{ codeunitName = 'Whole CU'; method = '*' }
                )
            }

            $codeunits = @(Get-AlToolTestCodeunits @testCodeunitParams)

            $codeunits.Count | Should -Be 1
            $codeunits[0].Name | Should -Be 'My Tests'
            @($codeunits[0].Tests).Count | Should -Be 1
            $codeunits[0].Tests[0] | Should -Be 'TestOne'

            $groupsPath = InModuleScope AlToolTestRunner -Parameters @{ Codeunits = $codeunits } {
                New-AlTestGroupsFile -Codeunits $Codeunits
            }
            try {
                $groupsJson = Get-Content -LiteralPath $groupsPath -Raw -Encoding UTF8
                $groupsJson.TrimStart() | Should -Match '^\['
                $groupsJson.Trim() |
                    Should -Be '[{"codeunitId":130001,"testMethods":["TestOne"]}]'
            }
            finally {
                Remove-Item -LiteralPath $groupsPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns every codeunit when there are no disabled tests' {
            Mock -ModuleName AlToolTestRunner Get-TestsFromBcContainer {
                @([PSCustomObject]@{ Id = 130001; Name = 'My Tests'; Tests = @('TestOne') })
            }
            $testCodeunitParams = @{
                ContainerName = 'test'
                Credential    = (New-Object System.Management.Automation.PSCredential('admin', (ConvertTo-SecureString 'password' -AsPlainText -Force)))
                ExtensionId   = [Guid]::NewGuid().ToString()
            }

            $codeunits = @(Get-AlToolTestCodeunits @testCodeunitParams)
            $codeunits.Count | Should -Be 1
        }
        }
    }

    Context 'Get-AlToolConnection' {
        InModuleScope AlToolTestRunner {
        It 'Reads server instance and developer services port from the container configuration' {
            Mock -ModuleName AlToolTestRunner Get-BcContainerServerConfiguration {
                [PSCustomObject]@{ ServerInstance = 'MyBC'; DeveloperServicesPort = 7145 }
            }

            $connection = Get-AlToolConnection -ContainerName 'mycontainer'

            $connection.Server | Should -Be 'http://mycontainer'
            $connection.ServerInstance | Should -Be 'MyBC'
            $connection.Port | Should -Be 7145
        }

        It 'Falls back to conventional defaults when configuration cannot be read' {
            Mock -ModuleName AlToolTestRunner Get-BcContainerServerConfiguration { throw 'no such container' }

            $connection = Get-AlToolConnection -ContainerName 'mycontainer'

            $connection.Server | Should -Be 'http://mycontainer'
            $connection.ServerInstance | Should -Be 'BC'
            $connection.Port | Should -Be 7049
        }
        }
    }

    Context 'Get-AlToolCompany' {
        InModuleScope AlToolTestRunner {
        It 'Honors an explicitly requested company name without querying the container' {
            Mock -ModuleName AlToolTestRunner Get-CompanyInBcContainer { throw 'should not be called' }
            $company = Get-AlToolCompany -ContainerName 'test' -Tenant 'default' -CompanyName 'CRONUS'
            $company | Should -Be 'CRONUS'
        }

        It 'Falls back to the container default company, preferring an evaluation company' {
            Mock -ModuleName AlToolTestRunner Get-CompanyInBcContainer {
                @(
                    [PSCustomObject]@{ companyName = 'CRONUS Real'; evaluationCompany = $false },
                    [PSCustomObject]@{ companyName = 'CRONUS Eval'; evaluationCompany = $true }
                )
            }
            $company = Get-AlToolCompany -ContainerName 'test' -Tenant 'default'
            $company | Should -Be 'CRONUS Eval'
        }
        }
    }

    Context 'ConvertFrom-AlTestGroupsOutput' {
        InModuleScope AlToolTestRunner {
        It 'Maps pass, fail, and skip results by codeunit and method' {
            $response = @{
                succeeded = $false
                data      = @{
                    results = @(
                        @{ codeunitId = 130001; methodName = 'SameName'; status = 'passed'; output = ''; durationMs = 11 },
                        @{ codeunitId = 130001; methodName = 'Fails'; status = 'failed'; output = "assertion failed`nAL Callstack:`nline one`nline two"; durationMs = 12 },
                        @{ codeunitId = 130002; methodName = 'SameName'; status = 'skipped'; output = ''; durationMs = 0 }
                    )
                }
            } | ConvertTo-Json -Depth 6

            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @($response)

            $parsed.Parsed | Should -BeTrue
            $parsed.Issues.Count | Should -Be 0
            $parsed.Results['130001']['SameName'].Outcome | Should -Be 'Pass'
            $parsed.Results['130002']['SameName'].Outcome | Should -Be 'Skip'
            $parsed.Results['130001']['Fails'].Outcome | Should -Be 'Fail'
            $parsed.Results['130001']['Fails'].Message | Should -Be 'assertion failed'
            $parsed.Results['130001']['Fails'].Stacktrace | Should -Be 'line one;line two'
        }

        It 'Reports malformed structured output without producing results' {
            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @('{not-json')

            $parsed.Parsed | Should -BeFalse
            $parsed.ParseError | Should -Match 'could not be parsed as JSON'
            $parsed.Results.Count | Should -Be 0
        }

        It 'Invalidates conflicting duplicate results and does not allow later duplicates to re-add them' {
            $response = @{
                succeeded = $true
                data      = @{
                    results = @(
                        @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'passed'; output = ''; durationMs = 1 },
                        @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'failed'; output = 'failed'; durationMs = 2 },
                        @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'passed'; output = ''; durationMs = 3 }
                    )
                }
            } | ConvertTo-Json -Depth 6

            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @($response)

            $parsed.Parsed | Should -BeTrue
            $parsed.HasFailedOutcome | Should -BeTrue
            $parsed.Results['130001'].ContainsKey('Duplicate') | Should -BeFalse
            $parsed.Issues | Should -Contain 'The response contains duplicate results for 130001/Duplicate; the result was invalidated.'
        }
        }
    }

    Context 'Invoke-AlRunTestsBatch' {
        BeforeEach {
            $script:batchCodeunits = @(
                [PSCustomObject]@{ Id = 130001; Name = 'First Tests'; Tests = @('TestOne', 'TestTwo') },
                [PSCustomObject]@{ Id = 130002; Name = 'Second Tests'; Tests = @('TestThree') }
            )
            $script:batchConnection = @{ Server = 'http://test'; ServerInstance = 'BC'; Port = 7049 }
            $script:capturedBatchArguments = $null
            $script:capturedTestGroupsPath = $null
            $script:capturedTestGroupsJson = $null
        }

        It 'Uses one testgroups invocation with the exact enabled method lists and removes the temporary file' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $script:capturedBatchArguments = @($ArgumentList)
                $testGroupsIndex = [Array]::IndexOf($ArgumentList, '--testgroups')
                $script:capturedTestGroupsPath = $ArgumentList[$testGroupsIndex + 1]
                $script:capturedTestGroupsJson = Get-Content -LiteralPath $script:capturedTestGroupsPath -Raw -Encoding UTF8
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 2 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'passed'; output = ''; durationMs = 3 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@()
                    Output         = [string[]]@($stdout)
                    ExitCode       = [int] 0
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                $result.Results['130001'].Count | Should -Be 2
                $result.Results['130002'].Count | Should -Be 1
                @($result.Keys | Sort-Object) | Should -Be @('ElapsedSec', 'Results')
            }

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlNativeCommand -Times 1 -Exactly
            $script:capturedBatchArguments[0] | Should -Be 'runtests'
            $script:capturedBatchArguments | Should -Contain '--testgroups'
            $script:capturedBatchArguments | Should -Not -Contain '--raw'
            $script:capturedBatchArguments | Should -Not -Contain '--testmethods'
            $script:capturedBatchArguments | Should -Not -Contain '130001'
            $script:capturedBatchArguments | Should -Not -Contain '130002'
            $script:capturedTestGroupsJson.Trim() |
                Should -Be '[{"codeunitId":130001,"testMethods":["TestOne","TestTwo"]},{"codeunitId":130002,"testMethods":["TestThree"]}]'
            Test-Path -LiteralPath $script:capturedTestGroupsPath | Should -BeFalse
        }

        It 'Parses valid failed-test JSON when AlTool exits with code one' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'failed'; output = 'failed'; durationMs = 4 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 5 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'skipped'; output = ''; durationMs = 0 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('test diagnostics')
                    Output         = [string[]]@($stdout, 'test diagnostics')
                    ExitCode       = [int] 1
                }
            }
            Mock -ModuleName AlToolTestRunner Write-Host {}

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                $result.Results['130001']['TestOne'].Outcome | Should -Be 'Fail'
                $result.Results['130001']['TestTwo'].Outcome | Should -Be 'Pass'
                $result.Results['130002']['TestThree'].Outcome | Should -Be 'Skip'
            }

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -like '::warning::*'
            }
        }

        It 'Terminates when AlTool exits above one despite complete passing JSON' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 2 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'skipped'; output = ''; durationMs = 0 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('transport failed')
                    Output         = [string[]]@($stdout, 'transport failed')
                    ExitCode       = [int] 9
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*unexpected code 9*stderr: transport failed*'
            }
        }

        It 'Terminates when exit code one has no failed test result' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 2 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'skipped'; output = ''; durationMs = 0 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('connection failed after response')
                    Output         = [string[]]@($stdout, 'connection failed after response')
                    ExitCode       = [int] 1
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*code 1 without reporting a failed test*connection failed after response*'
            }
        }

        It 'Terminates when exit code zero includes a failed test result' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'failed'; output = 'assertion failed'; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 2 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'skipped'; output = ''; durationMs = 0 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@()
                    Output         = [string[]]@($stdout)
                    ExitCode       = [int] 0
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*code 0 after reporting a failed test*assertion failed*'
            }
        }

        It 'Terminates when AlTool returns no structured response' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@('no response diagnostic')
                    Output         = [string[]]@('no response diagnostic')
                    ExitCode       = [int] 0
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*no structured stdout*stderr: no response diagnostic*'
            }
        }

        It 'Terminates when the structured response envelope is invalid' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{ data = @{ results = @() } } | ConvertTo-Json -Depth 4
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@()
                    Output         = [string[]]@($stdout)
                    ExitCode       = [int] 0
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*does not contain a valid ToolResponse data.results collection*'
            }
        }

        It 'Returns an otherwise valid partial response without a selection warning' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('batch diagnostic')
                    Output         = [string[]]@($stdout, 'batch diagnostic')
                    ExitCode       = [int] 0
                }
            }
            Mock -ModuleName AlToolTestRunner Write-Host {}

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                $result.Results['130001'].ContainsKey('TestOne') | Should -BeTrue
                $result.Results['130001'].ContainsKey('TestTwo') | Should -BeFalse
                $result.Results.ContainsKey('130002') | Should -BeFalse
                @($result.Keys | Sort-Object) | Should -Be @('ElapsedSec', 'Results')
            }

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -like '::warning::*'
            }
            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -eq 'batch diagnostic'
            }
        }

        It 'Returns unrequested results without a selection warning' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'passed'; output = ''; durationMs = 2 },
                            @{ codeunitId = 130002; methodName = 'TestThree'; status = 'skipped'; output = ''; durationMs = 0 },
                            @{ codeunitId = 139999; methodName = 'Unexpected'; status = 'failed'; output = 'ignored'; durationMs = 3 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@()
                    Output         = [string[]]@($stdout)
                    ExitCode       = [int] 1
                }
            }
            Mock -ModuleName AlToolTestRunner Write-Host {}

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection

                $result.Results['139999']['Unexpected'].Outcome | Should -Be 'Fail'
            }

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -like '::warning::*'
            }
        }

        It 'Invalidates a duplicate result instead of keeping an arbitrary outcome' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'failed'; output = 'failed'; durationMs = 2 },
                            @{ codeunitId = 130001; methodName = 'Duplicate'; status = 'passed'; output = ''; durationMs = 3 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@()
                    Output         = [string[]]@($stdout)
                    ExitCode       = [int] 1
                }
            }
            Mock -ModuleName AlToolTestRunner Write-Host {}
            $duplicateCodeunit = [PSCustomObject]@{ Id = 130001; Name = 'Duplicate Tests'; Tests = @('Duplicate') }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunit  = $duplicateCodeunit
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits @($Codeunit) -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection

                $result.Results['130001'].ContainsKey('Duplicate') | Should -BeFalse
                @($result.Keys | Sort-Object) | Should -Be @('ElapsedSec', 'Results')
            }

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 1 -Exactly -ParameterFilter {
                "$Object" -like '::warning::*invalid result entries*duplicate results*invalidated*'
            }
        }

        It 'Terminates with stdout and stderr when the batch response is malformed' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $testGroupsIndex = [Array]::IndexOf($ArgumentList, '--testgroups')
                $script:capturedTestGroupsPath = $ArgumentList[$testGroupsIndex + 1]
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('{not-json')
                    StandardError  = [string[]]@('parse diagnostic')
                    Output         = [string[]]@('{not-json', 'parse diagnostic')
                    ExitCode       = [int] 1
                }
            }
            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*protocol failure*could not be parsed as JSON*stderr: parse diagnostic*stdout: {not-json*'
            }

            Test-Path -LiteralPath $script:capturedTestGroupsPath | Should -BeFalse
        }

        It 'Removes the testgroups file when native invocation fails' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $testGroupsIndex = [Array]::IndexOf($ArgumentList, '--testgroups')
                $script:capturedTestGroupsPath = $ArgumentList[$testGroupsIndex + 1]
                throw 'native invocation failed'
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                } | Should -Throw '*native invocation failed*'
            }

            Test-Path -LiteralPath $script:capturedTestGroupsPath | Should -BeFalse
        }
    }

    Context 'Invoke-AlToolTestRun parameter contract' {
        BeforeAll {
            $script:requiredParameterCredential = New-Object System.Management.Automation.PSCredential(
                'admin',
                (ConvertTo-SecureString 'password' -AsPlainText -Force)
            )
            $script:requiredParameterExtensionId = [Guid]::NewGuid().ToString()
        }

        It 'Declares only the explicit runner contract and marks required values mandatory' {
            $command = Get-Command Invoke-AlToolTestRun

            $command.Parameters.ContainsKey('Parameters') | Should -BeFalse
            foreach ($parameterName in @('ContainerName', 'Credential', 'ExtensionId')) {
                $parameterAttribute = $command.Parameters[$parameterName].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                    Select-Object -First 1
                $parameterAttribute.Mandatory | Should -BeTrue
            }
        }

        It 'Rejects calls that omit ContainerName' {
            {
                Invoke-AlToolTestRun -Credential $script:requiredParameterCredential `
                    -ExtensionId $script:requiredParameterExtensionId
            } | Should -Throw
        }

        It 'Rejects calls that omit Credential' {
            {
                Invoke-AlToolTestRun -ContainerName 'test' -ExtensionId $script:requiredParameterExtensionId
            } | Should -Throw
        }

        It 'Rejects calls that omit ExtensionId' {
            {
                Invoke-AlToolTestRun -ContainerName 'test' -Credential $script:requiredParameterCredential
            } | Should -Throw
        }
    }

    Context 'Invoke-AlToolTestRun batch behavior' {
        BeforeEach {
            $script:testRunCredential = New-Object System.Management.Automation.PSCredential(
                'admin',
                (ConvertTo-SecureString 'password' -AsPlainText -Force)
            )
            $script:testRunParameters = @{
                ContainerName = 'test'
                Credential    = $script:testRunCredential
                ExtensionId   = [Guid]::NewGuid().ToString()
                AppName       = 'Test App'
            }
            $script:testRunCodeunit = [PSCustomObject]@{
                Id    = 130001
                Name  = 'My Tests'
                Tests = @('TestOne')
            }
            Remove-Item -LiteralPath (Join-Path $TestDrive 'TestResults.xml') -Force -ErrorAction SilentlyContinue

            Mock -ModuleName AlToolTestRunner Install-AlTool { return '1.2.3' }
            Mock -ModuleName AlToolTestRunner Get-Command { return $null } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Get-AlToolConnection {
                return @{ Server = 'http://test'; ServerInstance = 'BC'; Port = 7049 }
            }
            Mock -ModuleName AlToolTestRunner New-AlToolProject { return $TestDrive }
            Mock -ModuleName AlToolTestRunner Get-AlToolCompany { return 'CRONUS' }
            Mock -ModuleName AlToolTestRunner Get-AlToolTestCodeunits { return @($script:testRunCodeunit) }
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{ '130001' = @{ TestOne = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' } } }
                    ElapsedSec = 0.1
                }
            }
        }

        It 'Installs AlTool when a direct call cannot find al' {
            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue

            Should -Invoke -ModuleName AlToolTestRunner Get-Command -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'al' -and $ErrorAction -eq 'SilentlyContinue'
            }
            Should -Invoke -ModuleName AlToolTestRunner Install-AlTool -Times 1 -Exactly
        }

        It 'Does not install AlTool when a direct call finds al' {
            Mock -ModuleName AlToolTestRunner Get-Command {
                return [PSCustomObject]@{ Name = 'al' }
            } -ParameterFilter { $Name -eq 'al' }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue

            Should -Invoke -ModuleName AlToolTestRunner Get-Command -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'al' -and $ErrorAction -eq 'SilentlyContinue'
            }
            Should -Invoke -ModuleName AlToolTestRunner Install-AlTool -Times 0 -Exactly
        }

        It 'Runs all codeunits for an app in exactly one batch' {
            $secondCodeunit = [PSCustomObject]@{ Id = 130002; Name = 'Other Tests'; Tests = @('TestTwo') }
            Mock -ModuleName AlToolTestRunner Get-AlToolTestCodeunits {
                return @($script:testRunCodeunit, $secondCodeunit)
            }
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{
                        '130001' = @{ TestOne = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' } }
                        '130002' = @{ TestTwo = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' } }
                    }
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue

            Should -Invoke -ModuleName AlToolTestRunner Get-AlToolTestCodeunits -Times 1 -Exactly -ParameterFilter {
                $ContainerName -eq 'test' -and
                $Credential.UserName -eq 'admin' -and
                $ExtensionId -eq $script:testRunParameters.ExtensionId -and
                $Tenant -eq 'default' -and
                $TestType -eq '' -and
                $DisabledTests.Count -eq 0
            }
            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly -ParameterFilter {
                $Codeunits.Count -eq 2 -and
                "$($Codeunits[0].Id)" -eq '130001' -and
                "$($Codeunits[1].Id)" -eq '130002'
            }
        }

        It 'Keeps pass, fail, and skip outcomes from the single batch' {
            $script:testRunCodeunit.Tests = @('Passing', 'Failing', 'Skipped')
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{ '130001' = @{
                            Passing = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' }
                            Failing = @{ Outcome = 'Fail'; Ms = 2; Message = 'primary failure'; Stacktrace = 'stack' }
                            Skipped = @{ Outcome = 'Skip'; Ms = 0; Message = ''; Stacktrace = '' }
                        } }
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeFalse

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Passing']/failure") | Should -BeNullOrEmpty
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Failing']/failure").GetAttribute('message') |
                Should -Be 'primary failure'
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Skipped']/skipped") | Should -Not -BeNullOrEmpty
        }

        It 'Turns a partial valid batch into a final missing-result JUnit failure' {
            $script:testRunCodeunit.Tests = @('Reported', 'Missing')
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{ '130001' = @{ Reported = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' } } }
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeFalse

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Reported']/failure") | Should -BeNullOrEmpty
            $missingFailure = $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Missing']/failure")
            $missingFailure.GetAttribute('message') | Should -Be 'No result produced by al runtests'
        }

        It 'Ignores unrequested batch entries when building requested JUnit outcomes' {
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{
                        '130001' = @{ TestOne = @{ Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' } }
                        '139999' = @{ Unexpected = @{ Outcome = 'Fail'; Ms = 2; Message = 'ignored'; Stacktrace = '' } }
                    }
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $junit.SelectNodes('testsuites/testsuite/testcase').Count | Should -Be 1
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='TestOne']/failure") | Should -BeNullOrEmpty
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='Unexpected']") | Should -BeNullOrEmpty
        }

        It 'Turns a duplicate-invalidated result into a final missing-result JUnit failure' {
            $script:testRunCodeunit.Tests = @('Duplicate')
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{ Results = @{ '130001' = @{} }; ElapsedSec = 0.1 }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeFalse

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $failure = $junit.SelectSingleNode('testsuites/testsuite/testcase/failure')
            $failure.GetAttribute('message') | Should -Be 'No result produced by al runtests'
        }

        It 'Skips AlTool when enumeration finds no enabled codeunits' {
            Mock -ModuleName AlToolTestRunner Get-AlToolTestCodeunits { return @() }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue
            Should -Invoke -ModuleName AlToolTestRunner Install-AlTool -Times 0 -Exactly
            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 0 -Exactly
        }

        It 'Runs one batch per app and appends JUnit suites across app invocations' {
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue
            $script:testRunParameters.AppName = 'Second Test App'
            Invoke-AlToolTestRun @script:testRunParameters | Should -BeTrue

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 2 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $junit.SelectNodes('testsuites/testsuite').Count | Should -Be 2
            $junit.SelectNodes('testsuites/testsuite/testcase').Count | Should -Be 2
        }
    }

    Context 'Add-JUnitTestSuite' {
        InModuleScope AlToolTestRunner {
        BeforeEach {
            $script:doc = New-Object System.Xml.XmlDocument
            $script:doc.AppendChild($script:doc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
            $script:suites = $script:doc.CreateElement("testsuites")
            $script:doc.AppendChild($script:suites) | Out-Null
        }

        It 'Writes a passing suite with correct counts and no failure nodes' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @{ TestA = @{ Outcome = 'Pass'; Ms = 10; Message = ''; Stacktrace = '' } }

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('TestA') -MethodResults $methodResults -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host'

            $failed | Should -Be 0
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('name') | Should -Be '130001 My Tests'
            $suite.GetAttribute('tests') | Should -Be '1'
            $suite.GetAttribute('failures') | Should -Be '0'
            $suite.GetAttribute('time') | Should -Be '0.01'
            $suite.SelectNodes('testcase/failure').Count | Should -Be 0
        }

        It 'Marks a requested method with no result as a failure' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('MissingTest') -MethodResults @{} -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host'

            $failed | Should -Be 1
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('failures') | Should -Be '1'
            $suite.SelectSingleNode('testcase/failure').GetAttribute('message') | Should -Match 'No result produced'
        }

        It 'Records a failing method with its message and stacktrace' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @{ TestA = @{ Outcome = 'Fail'; Ms = 4; Message = 'boom'; Stacktrace = 'line1;line2' } }

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('TestA') -MethodResults $methodResults -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host'

            $failed | Should -Be 1
            $failureNode = $script:suites.SelectSingleNode('testsuite/testcase/failure')
            $failureNode.GetAttribute('message') | Should -Be 'boom'
            $failureNode.InnerText | Should -Match 'line1'
            $failureNode.InnerText | Should -Match 'line2'
        }

        It 'Records skipped methods in the suite count' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @{ TestA = @{ Outcome = 'Skip'; Ms = 0; Message = ''; Stacktrace = '' } }

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('TestA') -MethodResults $methodResults -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host'

            $failed | Should -Be 0
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('tests') | Should -Be '1'
            $suite.GetAttribute('skipped') | Should -Be '1'
            $suite.SelectNodes('testcase/skipped').Count | Should -Be 1
        }

        It 'Sets suite time to the sum of available requested method durations' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @{
                TestA = @{ Outcome = 'Pass'; Ms = 1250; Message = ''; Stacktrace = '' }
                TestB = @{ Outcome = 'Skip'; Ms = 250; Message = ''; Stacktrace = '' }
            }

            Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('TestA', 'TestB', 'MissingTest') -MethodResults $methodResults `
                -ExtensionId 'ext-id' -AppName 'MyApp' -Hostname 'host' | Out-Null

            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('time') | Should -Be '1.5'
            $suite.SelectSingleNode("testcase[@name='MissingTest']").GetAttribute('time') | Should -Be '0'
        }
        }
    }
}
