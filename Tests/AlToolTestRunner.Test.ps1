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
            ($payload.Output -join "`n") | Should -Match 'native-stdout'
            ($payload.Output -join "`n") | Should -Match 'native-stderr'
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
        It 'Falls back to update after install failure only when al is still unavailable' {
            $script:availabilityChecks = 0
            Mock -ModuleName AlToolTestRunner Get-Command {
                $script:availabilityChecks++
                if ($script:availabilityChecks -eq 1) { return $null }
                return [PSCustomObject]@{ Source = 'al' }
            } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    return [PSCustomObject]@{ Output = [string[]]@('install failed'); ExitCode = [int] 1 }
                }
                return [PSCustomObject]@{ Output = [string[]]@('1.2.3'); ExitCode = [int] 0 }
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
                    return [PSCustomObject]@{ Output = [string[]]@('install failed'); ExitCode = [int] 1 }
                }
                return [PSCustomObject]@{ Output = [string[]]@('update stderr'); ExitCode = [int] 17 }
            }

            { Install-AlTool } | Should -Throw '*fallback dotnet tool update exited with code 17*update stderr*'
        }

        It 'Warns on forced update failure and uses the existing version' {
            Mock -ModuleName AlToolTestRunner Get-Command { return [PSCustomObject]@{ Source = 'al' } } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Write-Host {}
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    return [PSCustomObject]@{ Output = [string[]]@('update stderr'); ExitCode = [int] 9 }
                }
                return [PSCustomObject]@{ Output = [string[]]@('1.2.3'); ExitCode = [int] 0 }
            }

            Install-AlTool -Force | Should -Be '1.2.3'

            Should -Invoke -ModuleName AlToolTestRunner Write-Host -Times 1 -Exactly -ParameterFilter {
                "$Object" -like "WARNING: 'al' update check exited with code 9*"
            }
        }

        It 'Reports al version failure explicitly' {
            Mock -ModuleName AlToolTestRunner Get-Command { return [PSCustomObject]@{ Source = 'al' } } -ParameterFilter { $Name -eq 'al' }
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                return [PSCustomObject]@{ Output = [string[]]@('version stderr'); ExitCode = [int] 11 }
            }

            { Install-AlTool } | Should -Throw "*'al --version'*exited with code 11*version stderr*"
        }
    }

    Context 'ConvertFrom-AlRunTestsOutput' {
        It 'Parses pass and fail results, dropping phantom OnRun and aggregate entries' {
            $lines = @(
                'Test run completed: 3 tests, 1 failed',
                'Results:',
                'PASS OnRun (5ms)',
                'PASS MyPassingTest (12ms)',
                'FAIL MyFailingTest (8ms)',
                '  Assert.AreEqual failed. Expected 1, got 2.',
                'AL Callstack:',
                '  "My Codeunit"(CodeUnit 130001).MyFailingTest line 3',
                'PASS  (25ms)'
            )

            $results = ConvertFrom-AlRunTestsOutput -OutputLines $lines

            $results.Keys.Count | Should -Be 2
            $results.ContainsKey('OnRun') | Should -BeFalse
            $results['MyPassingTest'].Outcome | Should -Be 'Pass'
            $results['MyPassingTest'].Ms | Should -Be 12
            $results['MyFailingTest'].Outcome | Should -Be 'Fail'
            $results['MyFailingTest'].Message | Should -Match 'Assert.AreEqual failed'
            $results['MyFailingTest'].Stacktrace | Should -Match 'MyFailingTest line 3'
        }

        It 'Returns an empty map when there is no Results block' {
            $results = ConvertFrom-AlRunTestsOutput -OutputLines @('Some unrelated output', 'No results here')
            $results.Keys.Count | Should -Be 0
        }

        It 'Parses skipped results' {
            $lines = @('Results:', 'SKIP MySkippedTest (0ms)')
            $results = ConvertFrom-AlRunTestsOutput -OutputLines $lines
            $results['MySkippedTest'].Outcome | Should -Be 'Skip'
        }
    }

    Context 'Get-DisabledTestKeySet' {
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

    Context 'Get-AlToolTestCodeunits' {
        It 'Enumerates codeunits and filters disabled methods and whole codeunits' {
            Mock -ModuleName AlToolTestRunner Get-TestsFromBcContainer {
                @(
                    [PSCustomObject]@{ Id = 130001; Name = 'My Tests'; Tests = @('TestOne', 'TestTwo') },
                    [PSCustomObject]@{ Id = 130002; Name = 'Whole CU'; Tests = @('X', 'Y') }
                )
            }
            $params = @{
                containerName = 'test'
                credential    = (New-Object System.Management.Automation.PSCredential('admin', (ConvertTo-SecureString 'password' -AsPlainText -Force)))
                extensionId   = [Guid]::NewGuid().ToString()
                disabledTests = @(
                    [PSCustomObject]@{ codeunitName = 'My Tests'; method = 'TestTwo' },
                    [PSCustomObject]@{ codeunitName = 'Whole CU'; method = '*' }
                )
            }

            $codeunits = @(Get-AlToolTestCodeunits -Parameters $params)

            $codeunits.Count | Should -Be 1
            $codeunits[0].Name | Should -Be 'My Tests'
            @($codeunits[0].Tests).Count | Should -Be 1
            $codeunits[0].Tests[0] | Should -Be 'TestOne'
        }

        It 'Returns every codeunit when there are no disabled tests' {
            Mock -ModuleName AlToolTestRunner Get-TestsFromBcContainer {
                @([PSCustomObject]@{ Id = 130001; Name = 'My Tests'; Tests = @('TestOne') })
            }
            $params = @{
                containerName = 'test'
                credential    = (New-Object System.Management.Automation.PSCredential('admin', (ConvertTo-SecureString 'password' -AsPlainText -Force)))
                extensionId   = [Guid]::NewGuid().ToString()
            }

            $codeunits = @(Get-AlToolTestCodeunits -Parameters $params)
            $codeunits.Count | Should -Be 1
        }
    }

    Context 'Get-AlToolConnection' {
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

    Context 'Get-AlToolCompany' {
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

    Context 'Invoke-AlRunTestsForCodeunit' {
        It 'Returns nonzero exit code and raw stderr without throwing' {
            Mock -ModuleName AlToolTestRunner Invoke-AlNativeCommand {
                return [PSCustomObject]@{ Output = [string[]]@('raw native stderr'); ExitCode = [int] 19 }
            }

            $result = Invoke-AlRunTestsForCodeunit -CodeunitId '130001' -Methods @('TestOne') `
                -ProjectPath $TestDrive -Company 'CRONUS' -Tenant 'default' `
                -Connection @{ Server = 'http://test'; ServerInstance = 'BC'; Port = 7049 }

            $result.ExitCode | Should -Be 19
            $result.Raw | Should -Match 'raw native stderr'
            $result.Connected | Should -BeFalse
            $result.Results.Count | Should -Be 0
        }
    }

    Context 'Add-JUnitTestSuite' {
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
                -Hostname 'host' -ElapsedSec 1.5

            $failed | Should -Be 0
            $suite = $script:suites.SelectSingleNode('testsuite')
            $suite.GetAttribute('name') | Should -Be '130001 My Tests'
            $suite.GetAttribute('tests') | Should -Be '1'
            $suite.GetAttribute('failures') | Should -Be '0'
            $suite.SelectNodes('testcase/failure').Count | Should -Be 0
        }

        It 'Marks a requested method with no result as a failure' {
            $codeunit = [PSCustomObject]@{ Id = 130001; Name = 'My Tests' }

            $failed = Add-JUnitTestSuite -Doc $script:doc -TestSuitesNode $script:suites -Codeunit $codeunit `
                -RequestedMethods @('MissingTest') -MethodResults @{} -ExtensionId 'ext-id' -AppName 'MyApp' `
                -Hostname 'host' -ElapsedSec 0.0

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
                -Hostname 'host' -ElapsedSec 0.5

            $failed | Should -Be 1
            $failureNode = $script:suites.SelectSingleNode('testsuite/testcase/failure')
            $failureNode.GetAttribute('message') | Should -Be 'boom'
            $failureNode.InnerText | Should -Match 'line1'
            $failureNode.InnerText | Should -Match 'line2'
        }
    }
}
