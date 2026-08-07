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

    Context 'ConvertFrom-AlBatchOutput' {
        It 'Splits batched output into per-codeunit result maps' {
            $lines = @(
                '===== Codeunit 130001 =====',
                'Results:',
                'PASS TestA (3ms)',
                '===== Codeunit 130002 =====',
                'Results:',
                'FAIL TestB (7ms)',
                '  boom',
                'AL Callstack:',
                '  stack'
            )

            $byCodeunit = ConvertFrom-AlBatchOutput -OutputLines $lines

            $byCodeunit.Keys.Count | Should -Be 2
            $byCodeunit['130001']['TestA'].Outcome | Should -Be 'Pass'
            $byCodeunit['130002']['TestB'].Outcome | Should -Be 'Fail'
        }
    }

    Context 'ConvertTo-AlTestPlanJson' {
        It 'Emits arrays at both levels for a single codeunit with a single method' {
            $json = ConvertTo-AlTestPlanJson -Groups @(@{ Id = '130001'; Methods = @('OnlyTest') })

            $json | Should -Match '^\[\{'
            $json | Should -Match '\}\]$'
            $parsed = $json | ConvertFrom-Json
            @($parsed).Count | Should -Be 1
            $parsed[0].codeunitId | Should -Be 130001
            @($parsed[0].testMethods).Count | Should -Be 1
            $parsed[0].testMethods[0] | Should -Be 'OnlyTest'
        }

        It 'Serializes multiple codeunits and methods' {
            $groups = @(
                @{ Id = '1'; Methods = @('A', 'B') },
                @{ Id = '2'; Methods = @('C') }
            )
            $parsed = (ConvertTo-AlTestPlanJson -Groups $groups) | ConvertFrom-Json
            @($parsed).Count | Should -Be 2
            @($parsed[0].testMethods).Count | Should -Be 2
            $parsed[1].codeunitId | Should -Be 2
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
