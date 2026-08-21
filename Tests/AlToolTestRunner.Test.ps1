[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/DebugLogHelper.psm1' -Resolve) -DisableNameChecking -Force
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
        It 'Captures native stdout, redirected stderr and exit code in Windows PowerShell 5 for exit <ExitCode>' -TestCases @(
            @{ ExitCode = 0 }
            @{ ExitCode = 1 }
        ) {
            param($ExitCode)

            if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
                Set-ItResult -Skipped -Because 'Windows PowerShell 5 is only available on Windows'
                return
            }

            $modulePath = (Resolve-Path (Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1')).Path
            $windowsPowerShell = (Get-Command (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ErrorAction Stop).Source
            $childScript = "[Console]::Out.WriteLine('native-stdout'); [Console]::Error.WriteLine('native-stderr'); exit $ExitCode"
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
            $escapedModulePath = $modulePath.Replace("'", "''")
            $escapedWindowsPowerShell = $windowsPowerShell.Replace("'", "''")

            $parentScript = @"
`$ErrorActionPreference = 'Stop'
`$module = Import-Module '$escapedModulePath' -Force -PassThru
`$result = & `$module {
    Invoke-AlNativeCommand -FilePath '$escapedWindowsPowerShell' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', '$encodedChildScript'
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
            $payload.ExitCode | Should -Be $ExitCode
            $payload.ErrorActionPreference | Should -Be 'Stop'
            @($payload.StandardOutput) | Should -Be @('native-stdout')
            ($payload.StandardError -join "`n") | Should -Match 'native-stderr'
            ($payload.Output -join "`n") | Should -Match 'native-stdout'
            ($payload.Output -join "`n") | Should -Match 'native-stderr'
        }

        It 'Uses one stderr-file invocation and captures LASTEXITCODE immediately' {
            InModuleScope AlToolTestRunner {
                $functionText = (Get-Command Invoke-AlNativeCommand).ScriptBlock.ToString()

                $functionText | Should -Match '(?s)\$standardOutput\s*=\s*&\s*\$nativeCommand\.Source\s+@ArgumentList\s+2>\s*\$standardErrorPath\s*\r?\n\s*\[int\]\s*\$exitCode\s*=\s*\$LASTEXITCODE'
                $functionText | Should -Not -Match '2>&1|PSVersionTable'
            }
        }

        It 'Preserves stdout, captures stderr and does not throw for exit <ExitCode> in the current process' -TestCases @(
            @{ ExitCode = 0 }
            @{ ExitCode = 1 }
        ) {
            param($ExitCode)

            $powerShell = (Get-Process -Id $PID).Path
            $childScript = "[Console]::Out.WriteLine('native-stdout'); [Console]::Error.WriteLine('native-stderr'); exit $ExitCode"
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

            InModuleScope AlToolTestRunner -Parameters @{
                PowerShellPath = $powerShell
                EncodedScript  = $encodedChildScript
                ExpectedExit   = $ExitCode
            } {
                $originalErrorActionPreference = $ErrorActionPreference
                $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
                $originalNativePreference = if ($nativePreference) { $nativePreference.Value } else { $null }
                $existingTempFiles = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'altool-stderr-*.txt' |
                    ForEach-Object { $_.FullName })
                try {
                    $ErrorActionPreference = 'Stop'
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference = $true
                    }

                    $result = Invoke-AlNativeCommand -FilePath $PowerShellPath -ArgumentList @(
                        '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $EncodedScript
                    )

                    $result.ExitCode | Should -Be $ExpectedExit
                    $result.StandardOutput | Should -Be @('native-stdout')
                    ($result.StandardError -join "`n") | Should -Match 'native-stderr'
                    $result.Output[0] | Should -Be 'native-stdout'
                    ($result.Output -join "`n") | Should -Match 'native-stderr'
                    $ErrorActionPreference | Should -Be 'Stop'
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference | Should -BeTrue
                    }
                    $remainingTempFiles = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'altool-stderr-*.txt' |
                        ForEach-Object { $_.FullName })
                    @($remainingTempFiles | Where-Object { $_ -notin $existingTempFiles }).Count | Should -Be 0
                }
                finally {
                    $ErrorActionPreference = $originalErrorActionPreference
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference = $originalNativePreference
                    }
                }
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
                $originalErrorActionPreference = $ErrorActionPreference
                $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
                $originalNativePreference = if ($nativePreference) { $nativePreference.Value } else { $null }
                $existingTempFiles = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'altool-stderr-*.txt' |
                    ForEach-Object { $_.FullName })
                try {
                    $ErrorActionPreference = 'Stop'
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference = $true
                    }

                    { Invoke-AlNativeCommand -FilePath $InvalidExecutable } |
                        Should -Throw '*failed to run*'

                    $ErrorActionPreference | Should -Be 'Stop'
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference | Should -BeTrue
                    }
                    $remainingTempFiles = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'altool-stderr-*.txt' |
                        ForEach-Object { $_.FullName })
                    @($remainingTempFiles | Where-Object { $_ -notin $existingTempFiles }).Count | Should -Be 0
                }
                finally {
                    $ErrorActionPreference = $originalErrorActionPreference
                    if ($nativePreference) {
                        $PSNativeCommandUseErrorActionPreference = $originalNativePreference
                    }
                }
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
        It 'Maps pass, fail, and skip result occurrences by codeunit' {
            $response = @{
                succeeded = $false
                message   = 'One or more tests failed.'
                data      = @{
                    success = $false
                    results = @(
                        @{ codeunitId = 130001; methodName = 'SameName'; status = 'passed'; output = ''; durationMs = 11 },
                        @{ codeunitId = 130001; methodName = 'Fails'; status = 'failed'; output = "assertion failed`nAL Callstack:`nline one`nline two"; durationMs = 12 },
                        @{ codeunitId = 130002; methodName = 'SameName'; status = 'skipped'; output = ''; durationMs = 0 }
                    )
                }
                nextSteps = @()
                errorDetails = @{
                    code                 = 'TestRunFailed'
                    description          = 'One or more tests failed.'
                    possibleCauses       = @()
                    suggestedActions     = @('Review the failed test output.')
                    alternatives         = @()
                    missingPrerequisites = @()
                    diagnosticHints      = @('Inspect the AL callstack.')
                    retryable            = $false
                }
                warnings = @()
            } | ConvertTo-Json -Depth 6

            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @($response)

            $parsed.Succeeded | Should -BeFalse
            $parsed.Message | Should -Be 'One or more tests failed.'
            @($parsed.Results['130001']).Count | Should -Be 2
            ($parsed.Results['130001'] | Where-Object MethodName -eq 'SameName').Outcome | Should -Be 'Pass'
            ($parsed.Results['130002'] | Where-Object MethodName -eq 'SameName').Outcome | Should -Be 'Skip'
            $failedResult = $parsed.Results['130001'] | Where-Object MethodName -eq 'Fails'
            $failedResult.Outcome | Should -Be 'Fail'
            $failedResult.Message | Should -Be 'assertion failed'
            $failedResult.Stacktrace | Should -Be 'line one;line two'
        }

        It 'Preserves every duplicate result occurrence in response order' {
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

            @($parsed.Results['130001']).Count | Should -Be 3
            @($parsed.Results['130001'].Outcome) | Should -Be @('Pass', 'Fail', 'Pass')
            @($parsed.Results['130001'].Ms) | Should -Be @(1, 2, 3)
        }

        It 'Parses durationMs values beyond the Int32 range as Int64' {
            $response = @{
                succeeded = $true
                data      = @{
                    results = @(
                        @{
                            codeunitId = 130001
                            methodName = 'LongRunning'
                            status     = 'passed'
                            output     = ''
                            durationMs = 3000000000
                        }
                    )
                }
            } | ConvertTo-Json -Depth 6

            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @($response)

            $parsed.Results['130001'][0].Ms | Should -Be ([long] 3000000000)
            $parsed.Results['130001'][0].Ms.GetType() | Should -Be ([long])
        }

        It 'Accepts a skipped missing-codeunit sentinel with a blank method name' {
            $response = @{
                succeeded = $true
                data      = @{
                    results = @(
                        @{ codeunitId = 0; methodName = ''; status = 'skipped'; output = ''; durationMs = 0 }
                    )
                }
            } | ConvertTo-Json -Depth 6

            $parsed = ConvertFrom-AlTestGroupsOutput -OutputLines @($response)

            $parsed.Results['0'][0].MethodName | Should -Be ''
            $parsed.Results['0'][0].Outcome | Should -Be 'Skip'
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
            Mock -ModuleName AlToolTestRunner OutputDebug {}
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
                $result.ElapsedSec | Should -BeGreaterOrEqual 0
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
            Should -Invoke -ModuleName AlToolTestRunner OutputDebug -Times 0 -Exactly
        }

        It 'Writes successful native stderr only to debug output' {
            Mock -ModuleName AlToolTestRunner Write-Host {}
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
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
                    StandardError  = [string[]]@('informational diagnostic', 'server trace')
                    Output         = [string[]]@($stdout, 'informational diagnostic', 'server trace')
                    ExitCode       = [int] 0
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                $result.Succeeded | Should -BeTrue
            }

            Should -Invoke -ModuleName AlToolTestRunner OutputDebug -Times 1 -Exactly -ParameterFilter {
                $message -like 'al runtests stderr:*informational diagnostic*server trace*'
            }
            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -match '(?i)warning|error'
            }
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
                $result.Succeeded | Should -BeFalse
                ($result.Results['130001'] | Where-Object MethodName -eq 'TestOne').Outcome | Should -Be 'Fail'
                ($result.Results['130001'] | Where-Object MethodName -eq 'TestTwo').Outcome | Should -Be 'Pass'
                ($result.Results['130002'] | Where-Object MethodName -eq 'TestThree').Outcome | Should -Be 'Skip'
            }

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 0 -Exactly -ParameterFilter {
                "$Object" -like '::warning::*'
            }
            Should -Invoke -ModuleName AlToolTestRunner OutputDebug -Times 1 -Exactly -ParameterFilter {
                $message -like 'al runtests stderr:*test diagnostics*'
            }
        }

        It 'Terminates when AlTool exits above one despite complete passing JSON' {
            Mock -ModuleName AlToolTestRunner ConvertFrom-AlTestGroupsOutput {
                throw 'structured response should not be parsed'
            }
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
                } | Should -Throw '*process failure*unexpected code 9*stderr: transport failed*'
            }
            Should -Invoke -ModuleName AlToolTestRunner ConvertFrom-AlTestGroupsOutput -Times 0 -Exactly
        }

        It 'Returns results as unsuccessful when a successful envelope exits with code one' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
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
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection

                $result.Succeeded | Should -BeFalse
                $result.Results['130001'][0].Outcome | Should -Be 'Pass'
            }
        }

        It 'Returns failed-envelope results as unsuccessful when the process exits with code zero' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
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
                $result = Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                    -Company 'CRONUS' -Tenant 'default' -Connection $Connection

                $result.Succeeded | Should -BeFalse
                $result.Results['130001'][0].Outcome | Should -Be 'Fail'
            }
        }

        It 'Returns a failed occurrence from a successful envelope for normal JUnit handling' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'failed'; output = 'assertion failed'; durationMs = 1 }
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

                $result.Succeeded | Should -BeTrue
                $result.Results['130001'][0].Outcome | Should -Be 'Fail'
            }
        }

        It 'Surfaces stderr when AlTool fails before serializing a ToolResponse' {
            Mock -ModuleName AlToolTestRunner ConvertFrom-AlTestGroupsOutput {
                throw 'empty stdout should not be parsed'
            }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@('no response diagnostic')
                    Output         = [string[]]@('no response diagnostic')
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
                } | Should -Throw '*al runtests failed: no response diagnostic*exit code 1*'
            }
            Should -Invoke -ModuleName AlToolTestRunner ConvertFrom-AlTestGroupsOutput -Times 0 -Exactly
        }

        It 'Terminates when the structured response lacks a Boolean succeeded value' {
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
                } | Should -Throw '*protocol failure*does not contain a valid Boolean ToolResponse succeeded value*'
            }
        }

        It 'Requires data results for a successful envelope' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{ succeeded = $true } | ConvertTo-Json
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
                } | Should -Throw '*protocol failure*successful structured response does not contain a ToolResponse data.results array*'
            }
        }

        It 'Surfaces the failed-envelope message and stderr when results are absent' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    message   = 'The company could not be opened.'
                    nextSteps = @('Check the server address.', 'Retry after correcting the configuration.')
                    errorDetails = @{
                        code                 = 'ConnectionFailure'
                        description          = 'The company could not be opened.'
                        possibleCauses       = @('The server address is invalid.')
                        suggestedActions     = @('Check the server address.')
                        alternatives         = @()
                        missingPrerequisites = @('A reachable Business Central server')
                        diagnosticHints      = @('Verify the service endpoint.')
                        retryable            = $true
                    }
                    warnings = @('The test run did not start.', 'Check the server address.')
                } | ConvertTo-Json -Depth 5
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('The company could not be opened.', 'server refused the connection')
                    Output         = [string[]]@($stdout, 'The company could not be opened.', 'server refused the connection')
                    ExitCode       = [int] 1
                }
            }

            InModuleScope AlToolTestRunner -Parameters @{
                Codeunits  = $script:batchCodeunits
                Connection = $script:batchConnection
            } {
                try {
                    Invoke-AlRunTestsBatch -Codeunits $Codeunits -ProjectPath $TestDrive `
                        -Company 'CRONUS' -Tenant 'default' -Connection $Connection
                    throw 'Expected Invoke-AlRunTestsBatch to fail.'
                }
                catch {
                    $_.Exception.Message | Should -Match '^al runtests failed: The company could not be opened\.'
                    $_.Exception.Message | Should -Match 'stderr:'
                    $_.Exception.Message | Should -Match 'server refused the connection'
                }
            }
        }

        It 'Does not repeat stderr that exactly matches a failed-envelope message' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $false
                    message   = 'The company could not be opened.'
                } | ConvertTo-Json
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('The company could not be opened.')
                    Output         = [string[]]@($stdout, 'The company could not be opened.')
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
                } | Should -Throw 'al runtests failed: The company could not be opened.'
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
                } | Should -Throw '*protocol failure*could not be parsed as JSON*stdout: {not-json*stderr: parse diagnostic*'
            }

            Test-Path -LiteralPath $script:capturedTestGroupsPath | Should -BeFalse
        }

        It 'Terminates when a result status cannot be mapped to JUnit' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                $stdout = @{
                    succeeded = $true
                    data      = @{
                        results = @(
                            @{ codeunitId = 130001; methodName = 'TestOne'; status = 'passed'; output = ''; durationMs = 1 },
                            @{ codeunitId = 130001; methodName = 'TestTwo'; status = 'unknown'; output = ''; durationMs = 2 }
                        )
                    }
                } | ConvertTo-Json -Depth 6
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@($stdout)
                    StandardError  = [string[]]@('schema diagnostic')
                    Output         = [string[]]@($stdout, 'schema diagnostic')
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
                } | Should -Throw "*protocol failure*TestTwo has unknown status 'unknown'*stderr: schema diagnostic*"
            }
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
                    Results    = @{ '130001' = @(
                            @{ MethodName = 'TestOne'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' }
                        ) }
                    Succeeded  = $true
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
                        '130001' = @(@{ MethodName = 'TestOne'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' })
                        '130002' = @(@{ MethodName = 'TestTwo'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' })
                    }
                    Succeeded  = $true
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
                    Results    = @{ '130001' = @(
                            @{ MethodName = 'Passing'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' },
                            @{ MethodName = 'Failing'; Outcome = 'Fail'; Ms = 2; Message = 'primary failure'; Stacktrace = 'stack' },
                            @{ MethodName = 'Skipped'; Outcome = 'Skip'; Ms = 0; Message = ''; Stacktrace = '' }
                        ) }
                    Succeeded  = $false
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
                    Results    = @{ '130001' = @(
                            @{ MethodName = 'Reported'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' }
                        ) }
                    Succeeded  = $false
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

        It 'Reports a failed batch envelope after preserving complete JUnit results' {
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{ '130001' = @(
                            @{ MethodName = 'TestOne'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' }
                        ) }
                    Succeeded  = $false
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeFalse

            [xml] $junit = Get-Content -Path $junitFile -Raw
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='TestOne']") | Should -Not -BeNullOrEmpty
            $junit.SelectSingleNode("testsuites/testsuite/testcase[@name='TestOne']/failure") | Should -BeNullOrEmpty
        }

        It 'Ignores unrequested batch entries when building requested JUnit outcomes' {
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{
                        '130001' = @(@{ MethodName = 'TestOne'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' })
                        '139999' = @(@{ MethodName = 'Unexpected'; Outcome = 'Pass'; Ms = 2; Message = ''; Stacktrace = '' })
                    }
                    Succeeded  = $true
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

        It 'Emits exact duplicate results and includes a duplicate failure in allPassed' {
            $script:testRunCodeunit.Tests = @('Duplicate')
            $junitFile = Join-Path $TestDrive 'TestResults.xml'
            $script:testRunParameters.JUnitResultFileName = $junitFile
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                return @{
                    Results    = @{ '130001' = @(
                            @{ MethodName = 'Duplicate'; Outcome = 'Pass'; Ms = 1; Message = ''; Stacktrace = '' },
                            @{ MethodName = 'Duplicate'; Outcome = 'Fail'; Ms = 2; Message = 'second occurrence failed'; Stacktrace = 'stack' }
                        ) }
                    Succeeded  = $false
                    ElapsedSec = 0.1
                }
            }

            Invoke-AlToolTestRun @script:testRunParameters | Should -BeFalse

            Should -Invoke -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch -Times 1 -Exactly
            [xml] $junit = Get-Content -Path $junitFile -Raw
            $cases = @($junit.SelectNodes("testsuites/testsuite/testcase[@name='Duplicate']"))
            $cases.Count | Should -Be 2
            @($cases | Where-Object { $null -ne $_.SelectSingleNode('failure') }).Count | Should -Be 1
            $cases[1].SelectSingleNode('failure').GetAttribute('message') | Should -Be 'second occurrence failed'
            $junit.SelectNodes("testsuites/testsuite/testcase/failure[@message='No result produced by al runtests']").Count |
                Should -Be 0
        }

        It 'Clears runtime credentials when batch execution fails' {
            $previousUserName = $env:BC_SERVER_USERNAME
            $previousPassword = $env:BC_SERVER_PASSWORD
            Mock -ModuleName AlToolTestRunner Invoke-AlRunTestsBatch {
                throw 'batch failed'
            }

            try {
                { Invoke-AlToolTestRun @script:testRunParameters } | Should -Throw '*batch failed*'
                Test-Path Env:\BC_SERVER_USERNAME | Should -BeFalse
                Test-Path Env:\BC_SERVER_PASSWORD | Should -BeFalse
            }
            finally {
                if ($null -ne $previousUserName) {
                    $env:BC_SERVER_USERNAME = $previousUserName
                }
                if ($null -ne $previousPassword) {
                    $env:BC_SERVER_PASSWORD = $previousPassword
                }
            }
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
            $methodResults = @(
                @{ MethodName = 'TestA'; Outcome = 'Pass'; Ms = 10; Message = ''; Stacktrace = '' }
            )

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
                -RequestedMethods @('MissingTest') -MethodResults @() -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host'

            $failed | Should -Be 1
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('failures') | Should -Be '1'
            $suite.SelectSingleNode('testcase/failure').GetAttribute('message') | Should -Match 'No result produced'
        }

        It 'Records a failing method with its message and stacktrace' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @(
                @{ MethodName = 'TestA'; Outcome = 'Fail'; Ms = 4; Message = 'boom'; Stacktrace = 'line1;line2' }
            )

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
            $methodResults = @(
                @{ MethodName = 'TestA'; Outcome = 'Skip'; Ms = 0; Message = ''; Stacktrace = '' }
            )

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
            $methodResults = @(
                @{ MethodName = 'TestA'; Outcome = 'Pass'; Ms = 1250; Message = ''; Stacktrace = '' },
                @{ MethodName = 'TestB'; Outcome = 'Skip'; Ms = 250; Message = ''; Stacktrace = '' }
            )

            Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('TestA', 'TestB', 'MissingTest') -MethodResults $methodResults `
                -ExtensionId 'ext-id' -AppName 'MyApp' -Hostname 'host' | Out-Null

            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('time') | Should -Be '1.5'
            $suite.SelectSingleNode("testcase[@name='MissingTest']").GetAttribute('time') | Should -Be '0'
        }

        It 'Emits every decorated data-driven case and preserves nested brackets' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @(
                @{ MethodName = 'DataTest[Case A]'; Outcome = 'Pass'; Ms = 100; Message = ''; Stacktrace = '' },
                @{ MethodName = 'DataTest[Outer[Inner]]'; Outcome = 'Skip'; Ms = 250; Message = ''; Stacktrace = '' }
            )

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('DataTest') -MethodResults $methodResults -ExtensionId 'ext-id' `
                -AppName 'MyApp' -Hostname 'host'

            $failed | Should -Be 0
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('tests') | Should -Be '2'
            $suite.GetAttribute('skipped') | Should -Be '1'
            $suite.GetAttribute('time') | Should -Be '0.35'
            $suite.SelectSingleNode("testcase[@name='DataTest[Case A]']") | Should -Not -BeNullOrEmpty
            $suite.SelectSingleNode("testcase[@name='DataTest[Outer[Inner]]']") | Should -Not -BeNullOrEmpty
            $suite.SelectNodes("testcase/failure[@message='No result produced by al runtests']").Count | Should -Be 0
        }

        It 'Does not let an unrelated decorated result satisfy a requested base method' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @(
                @{ MethodName = 'OtherTest[Case A]'; Outcome = 'Pass'; Ms = 100; Message = ''; Stacktrace = '' },
                @{ MethodName = 'DataTest[]'; Outcome = 'Pass'; Ms = 100; Message = ''; Stacktrace = '' }
            )

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('DataTest') -MethodResults $methodResults -ExtensionId 'ext-id' `
                -AppName 'MyApp' -Hostname 'host'

            $failed | Should -Be 1
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('tests') | Should -Be '1'
            $suite.SelectSingleNode("testcase[@name='DataTest']/failure").GetAttribute('message') |
                Should -Be 'No result produced by al runtests'
            $suite.SelectSingleNode("testcase[@name='OtherTest[Case A]']") | Should -BeNullOrEmpty
            $suite.SelectSingleNode("testcase[@name='DataTest[]']") | Should -BeNullOrEmpty
        }

        It 'Emits every exact duplicate occurrence including mixed outcomes' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }
            $methodResults = @(
                @{ MethodName = 'Duplicate'; Outcome = 'Pass'; Ms = 100; Message = ''; Stacktrace = '' },
                @{ MethodName = 'Duplicate'; Outcome = 'Fail'; Ms = 200; Message = 'failed duplicate'; Stacktrace = 'line' }
            )

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('Duplicate') -MethodResults $methodResults -ExtensionId 'ext-id' `
                -AppName 'MyApp' -Hostname 'host'

            $failed | Should -Be 1
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('tests') | Should -Be '2'
            $suite.GetAttribute('failures') | Should -Be '1'
            $suite.GetAttribute('time') | Should -Be '0.3'
            $suite.SelectNodes("testcase[@name='Duplicate']").Count | Should -Be 2
            $suite.SelectNodes("testcase/failure[@message='No result produced by al runtests']").Count | Should -Be 0
        }
        }
    }
}
