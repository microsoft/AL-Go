Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/TestIsolation.psm1') -Force

Describe 'TestIsolation' {

    Context 'New-PartitionedTestRunnerScriptBlock' {

        BeforeAll {
            # Installed as a global function (not a Pester Mock) because the
            # scriptblock returned by New-PartitionedTestRunnerScriptBlock
            # resolves Run-TestsInBcContainer at invocation time through the
            # global function table — Mock's command-lookup scope does not
            # reach across the .GetNewClosure() boundary. The AfterAll block
            # removes the stub so no other *.Test.ps1 sees it.
            function global:Run-TestsInBcContainer {
                [CmdletBinding()]
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

        It 'default call uses negated union of every partition piece joined with &' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60200..60299' }
                    @{ runnerCodeunitId = 130452; codeunits = '60300|60301' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[2]
            $defaultCall.testCodeunitRange | Should -Be '<>60200..60299&<>60300&<>60301'
            $defaultCall.hasRunnerId       | Should -Be $false
        }

        It 'default call uses defaultRunnerCodeunitId together with the negated filter' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 130450
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = '60100' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testRunnerCodeunitId | Should -Be '130450'
            $defaultCall.testCodeunitRange    | Should -Be '<>60100'
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

        It 'trims whitespace in codeunits pieces when building the negative filter' {
            $sb = New-PartitionedTestRunnerScriptBlock -Settings @{
                defaultRunnerCodeunitId = 0
                partitions              = @(
                    @{ runnerCodeunitId = 130451; codeunits = ' 60100 |  60200..60299 ' }
                )
            }
            & $sb @{ extensionId = 'a'; containerName = 'c' } | Out-Null

            $defaultCall = $script:RunTestsInvocations[1]
            $defaultCall.testCodeunitRange | Should -Be '<>60100&<>60200..60299'
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
            $script:RunTestsInvocations[1].testCodeunitRange    | Should -Be '<>60100'
        }
    }
}
