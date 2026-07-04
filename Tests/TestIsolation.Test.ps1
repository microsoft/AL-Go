Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/TestIsolation.psm1') -Force

Describe 'TestIsolation' {

    Context 'New-PartitionedTestRunnerScriptBlock' {

        BeforeAll {
            # Installed as a global function (not a Pester Mock) because the
            # scriptblock returned by New-PartitionedTestRunnerScriptBlock
            # resolves Run-TestsInBcContainer at invocation time through the
            # global function table - Mock's command-lookup scope does not
            # reach across the .GetNewClosure() boundary. The AfterAll block
            # removes the stub so no other *.Test.ps1 sees it.
            function global:Run-TestsInBcContainer {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Stub must match the BcContainerHelper function name.')]
                [CmdletBinding()]
                [OutputType([bool])]
                Param(
                    [string] $testCodeunit,
                    [string] $testCodeunitRange,
                    [string] $testRunnerCodeunitId,
                    [string] $extensionId,
                    [string] $containerName,
                    $disabledTests,
                    [string] $JUnitResultFileName,
                    [string] $XUnitResultFileName,
                    [switch] $AppendToJUnitResultFile,
                    [switch] $AppendToXUnitResultFile,
                    [switch] $returnTrueIfAllPassed,
                    [Parameter(ValueFromRemainingArguments = $true)]
                    $rest
                )
                $call = [pscustomobject]@{
                    testCodeunitRange       = $testCodeunitRange
                    testRunnerCodeunitId    = $testRunnerCodeunitId
                    extensionId             = $extensionId
                    containerName           = $containerName
                    AppendToJUnitResultFile = [bool] $AppendToJUnitResultFile
                    hasRangeFilter          = $PSBoundParameters.ContainsKey('testCodeunitRange')
                    hasRunnerId             = $PSBoundParameters.ContainsKey('testRunnerCodeunitId')
                }
                $script:RunTestsInvocations += , $call
                if ($script:RunTestsResponse -is [scriptblock]) {
                    return (& $script:RunTestsResponse $call)
                }
                return [bool] $script:RunTestsResponse
            }
        }

        AfterAll {
            Remove-Item -Path function:global:Run-TestsInBcContainer -ErrorAction SilentlyContinue
        }

        BeforeEach {
            $script:RunTestsInvocations = @()
            $script:RunTestsResponse = $true
        }

        It 'returns a scriptblock' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{ defaultRunnerCodeunitId = 0; partitions = @() }
            $sb | Should -BeOfType [scriptblock]
        }

        It 'with empty partitions and defaultRunnerCodeunitId = 0, invokes default runner once with no filter and no runner id' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @()
            }
            $result = & $sb @{ extensionId = 'a'; containerName = 'c' }

            $result | Should -Be $true
            $script:RunTestsInvocations.Count | Should -Be 1
            $script:RunTestsInvocations[0].hasRangeFilter | Should -Be $false
            $script:RunTestsInvocations[0].hasRunnerId | Should -Be $false
        }

        It 'with empty partitions and defaultRunnerCodeunitId set, default call uses that runner' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 130450
                partitions              = @()
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $script:RunTestsInvocations.Count | Should -Be 1
            $script:RunTestsInvocations[0].testRunnerCodeunitId | Should -Be '130450'
            $script:RunTestsInvocations[0].hasRangeFilter | Should -Be $false
        }

        It 'invokes one call per partition with that partition runner and exact range string' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60200..60299' }
                    @{ runnerCodeunitId = 130452; codeunits = '60300|60301' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            # 2 partition calls + 1 default call
            $script:RunTestsInvocations.Count | Should -Be 3

            $script:RunTestsInvocations[0].testRunnerCodeunitId | Should -Be '130451'
            $script:RunTestsInvocations[0].testCodeunitRange    | Should -Be '60200..60299'

            $script:RunTestsInvocations[1].testRunnerCodeunitId | Should -Be '130452'
            $script:RunTestsInvocations[1].testCodeunitRange    | Should -Be '60300|60301'
        }

        It 'default call uses the complement of every partition filter' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60200..60299' }
                    @{ runnerCodeunitId = 130452; codeunits = '60300|60301' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            # 60200..60299, 60300 and 60301 are adjacent and merge into 60200..60301
            $defaultCall = $script:RunTestsInvocations[2]
            $defaultCall.testCodeunitRange | Should -Be '..60199|60302..'
            $defaultCall.hasRunnerId       | Should -Be $false
        }

        It 'default call complement keeps gaps between non-adjacent partitions' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                    @{ runnerCodeunitId = 130452; codeunits = '60200..60299' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[2]
            $defaultCall.testCodeunitRange | Should -Be '..60099|60101..60199|60300..'
        }

        It 'default call complement collapses a single-ID gap to a single ID' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100|60102' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testCodeunitRange | Should -Be '..60099|60101|60103..'
        }

        It 'default call complement has no leading piece when a partition starts at codeunit ID 1' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '1..60000' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testCodeunitRange | Should -Be '60001..'
        }

        It 'skips the default-runner call when partitions cover the entire codeunit ID space' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '1..2147483647' }
                )
            }
            $result = & $sb @{ extensionId = 'a'; containerName = 'c' }

            $result | Should -Be $true
            $script:RunTestsInvocations.Count | Should -Be 1
            $script:RunTestsInvocations[0].testRunnerCodeunitId | Should -Be '130451'
        }

        It 'default call uses defaultRunnerCodeunitId together with the complement filter' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 130450
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testRunnerCodeunitId | Should -Be '130450'
            $defaultCall.testCodeunitRange    | Should -Be '..60099|60101..'
        }

        It 'forwards arbitrary Run-AlPipeline parameters to every invocation' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                )
            }
            & $sb @{
                extensionId             = 'app-a'
                containerName           = 'mycontainer'
                AppendToJUnitResultFile = $true
            } | Out-Null

            $script:RunTestsInvocations.Count | Should -Be 2
            $script:RunTestsInvocations | ForEach-Object {
                $_.extensionId             | Should -Be 'app-a'
                $_.containerName           | Should -Be 'mycontainer'
                $_.AppendToJUnitResultFile | Should -Be $true
            }
        }

        It 'returns $false if any invocation fails but still runs every call' {
            $script:RunTestsResponse = { param($call) $call.testRunnerCodeunitId -ne '130452' }

            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                    @{ runnerCodeunitId = 130452; codeunits = '60200' }
                )
            }
            $result = & $sb @{ extensionId = 'a'; containerName = 'c' }

            $result | Should -Be $false
            $script:RunTestsInvocations.Count | Should -Be 3
        }

        It 'trims whitespace in codeunits pieces when building the complement filter' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = ' 60100 |  60200..60299 ' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testCodeunitRange | Should -Be '..60099|60101..60199|60300..'
        }

        It 'works with PSCustomObject partitions (as JSON-deserialised settings would supply)' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings ([pscustomobject]@{
                    defaultRunnerCodeunitId = 0
                    partitions              = @(
                        [pscustomobject]@{ runnerCodeunitId = 130451; codeunits = '60100' }
                    )
                })
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $script:RunTestsInvocations.Count | Should -Be 2
            $script:RunTestsInvocations[0].testRunnerCodeunitId | Should -Be '130451'
            $script:RunTestsInvocations[0].testCodeunitRange    | Should -Be '60100'
            $script:RunTestsInvocations[1].testCodeunitRange    | Should -Be '..60099|60101..'
        }

        It 'routes every call through a provided InnerScriptBlock instead of Run-TestsInBcContainer' {
            $script:innerCalls = @()
            $inner = {
                Param([Hashtable] $parameters)
                $script:innerCalls += , $parameters
                return $true
            }
            $sb = New-PartitionedTestRunnerScriptBlock -InnerScriptBlock $inner -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                )
            }
            $result = & $sb @{ extensionId = 'a'; containerName = 'c' }

            $result | Should -Be $true
            $script:RunTestsInvocations.Count | Should -Be 0
            $script:innerCalls.Count | Should -Be 2
            $script:innerCalls[0].testRunnerCodeunitId | Should -Be '130451'
            $script:innerCalls[0].testCodeunitRange    | Should -Be '60100'
            $script:innerCalls[1].testCodeunitRange    | Should -Be '..60099|60101..'
            $script:innerCalls[1].extensionId          | Should -Be 'a'
        }

        It 'returns $false when the InnerScriptBlock reports a failed partition' {
            $inner = {
                Param([Hashtable] $parameters)
                return ($parameters.testRunnerCodeunitId -ne '130451')
            }
            $sb = New-PartitionedTestRunnerScriptBlock -InnerScriptBlock $inner -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                )
            }
            $result = & $sb @{ extensionId = 'a'; containerName = 'c' }

            $result | Should -Be $false
        }

        It 'warns when partition filters overlap' {
            Mock -CommandName OutputWarning -ModuleName TestIsolation { }
            $null = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100..60200' }
                    @{ runnerCodeunitId = 130452; codeunits = '60150' }
                )
            }
            Should -Invoke -CommandName OutputWarning -ModuleName TestIsolation -Times 1 -Exactly
        }

        It 'does not warn when partition filters do not overlap' {
            Mock -CommandName OutputWarning -ModuleName TestIsolation { }
            $null = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100..60200' }
                    @{ runnerCodeunitId = 130452; codeunits = '60201' }
                )
            }
            Should -Invoke -CommandName OutputWarning -ModuleName TestIsolation -Times 0 -Exactly
        }

        It 'throws on filter syntax outside the supported subset' {
            {
                New-PartitionedTestRunnerScriptBlock -Settings @{
                    defaultRunnerCodeunitId = 0
                    partitions              = @(
                        @{ runnerCodeunitId = 130451; codeunits = '<>60100' }
                    )
                }
            } | Should -Throw -ExpectedMessage "*Unsupported piece '<>60100'*"
        }

        It 'throws on open-ended ranges' {
            {
                New-PartitionedTestRunnerScriptBlock -Settings @{
                    defaultRunnerCodeunitId = 0
                    partitions              = @(
                        @{ runnerCodeunitId = 130451; codeunits = '60100..' }
                    )
                }
            } | Should -Throw -ExpectedMessage "*Unsupported piece '60100..'*"
        }

        It 'throws on a reversed range' {
            {
                New-PartitionedTestRunnerScriptBlock -Settings @{
                    defaultRunnerCodeunitId = 0
                    partitions              = @(
                        @{ runnerCodeunitId = 130451; codeunits = '60299..60200' }
                    )
                }
            } | Should -Throw -ExpectedMessage "*lower bound is greater than upper bound*"
        }

        It 'throws when a partition filter contains no codeunit IDs' {
            {
                New-PartitionedTestRunnerScriptBlock -Settings @{
                    defaultRunnerCodeunitId = 0
                    partitions              = @(
                        @{ runnerCodeunitId = 130451; codeunits = ' | ' }
                    )
                }
            } | Should -Throw -ExpectedMessage "*does not contain any codeunit IDs*"
        }
    }
}
