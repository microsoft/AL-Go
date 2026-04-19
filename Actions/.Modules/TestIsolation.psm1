<#
.SYNOPSIS
Test Isolation module for AL-Go for GitHub.

.DESCRIPTION
Builds a scriptblock compatible with Run-AlPipeline's -RunTestsInBcContainer
override. The scriptblock invokes Run-TestsInBcContainer once per declared
partition (each with its own test runner and codeunit-range filter), plus one
trailing call under the default runner whose filter excludes every codeunit
matched by the explicit partitions.
#>

function New-PartitionedTestRunnerScriptBlock {
    <#
        .SYNOPSIS
            Build a scriptblock for Run-AlPipeline's -RunTestsInBcContainer hook.
        .DESCRIPTION
            Run-AlPipeline invokes the override once per test app with a hashtable
            of parameters (extensionId, containerName, disabledTests, JUnit/XUnit
            file, AppendTo*ResultFile, auth context, etc.). The returned
            scriptblock loops over the configured partitions and, for each one,
            invokes Run-TestsInBcContainer with the partition's runner id and
            codeunit-range filter. After all partitions, it issues one trailing
            call under defaultRunnerCodeunitId whose -testCodeunitRange is the
            negation of the union of every explicit partition's filter — so every
            test codeunit not matched by an explicit partition runs under the
            default runner exactly once.

            Result-file appending is preserved because we forward the JUnit/XUnit
            file params Run-AlPipeline already configured (AppendTo*ResultFile = $true).
        .PARAMETER Settings
            The testIsolation settings object with `defaultRunnerCodeunitId` and
            `partitions` (array of @{ runnerCodeunitId; codeunits }). Closed over
            by the returned scriptblock.
        .OUTPUTS
            [scriptblock] returning $true if every invocation reported success.
    #>
    Param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $capturedPartitions = @($Settings.partitions)
    $capturedDefaultRunner = [int] $Settings.defaultRunnerCodeunitId

    # Build the negative filter for the trailing default-runner call by
    # collecting every '|'-separated piece from every partition's codeunits
    # filter, prefixing each with '<>' and joining with '&'. Result is a
    # BC integer-field filter expression that matches every codeunit ID NOT
    # covered by an explicit partition.
    $defaultRangeFilter = ''
    if ($capturedPartitions.Count -gt 0) {
        $negatedPieces = @()
        foreach ($p in $capturedPartitions) {
            foreach ($piece in ([string] $p.codeunits).Split('|')) {
                $trimmed = $piece.Trim()
                if ($trimmed) { $negatedPieces += "<>$trimmed" }
            }
        }
        $defaultRangeFilter = $negatedPieces -join '&'
    }

    return {
        Param([Hashtable] $parameters)

        $appId = "$($parameters.extensionId)"
        $allPassed = $true
        $invocations = 0

        foreach ($p in $capturedPartitions) {
            $call = @{}
            foreach ($k in $parameters.Keys) { $call[$k] = $parameters[$k] }
            $call['testCodeunitRange'] = "$($p.codeunits)"
            $call['testRunnerCodeunitId'] = "$([int] $p.runnerCodeunitId)"

            Write-Host "Running partition runner=$($p.runnerCodeunitId) range='$($p.codeunits)' app=$appId"
            $invocations++

            $passed = Run-TestsInBcContainer @call
            if (-not $passed) { $allPassed = $false }
        }

        $defaultCall = @{}
        foreach ($k in $parameters.Keys) { $defaultCall[$k] = $parameters[$k] }
        if ($defaultRangeFilter) { $defaultCall['testCodeunitRange'] = $defaultRangeFilter }
        if ($capturedDefaultRunner -gt 0) { $defaultCall['testRunnerCodeunitId'] = "$capturedDefaultRunner" }

        Write-Host "Running default partition runner=$capturedDefaultRunner range='$defaultRangeFilter' app=$appId"
        $invocations++

        $passed = Run-TestsInBcContainer @defaultCall
        if (-not $passed) { $allPassed = $false }

        Write-Host "Partitioned test run for app $appId complete. Invocations: $invocations. All passed: $allPassed"
        return $allPassed
    }.GetNewClosure()
}

Export-ModuleMember -Function New-PartitionedTestRunnerScriptBlock
