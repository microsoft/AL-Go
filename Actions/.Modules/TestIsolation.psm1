<#
.SYNOPSIS
Test Isolation module for AL-Go for GitHub.

.DESCRIPTION
Builds a scriptblock compatible with Run-AlPipeline's -RunTestsInBcContainer
override. The scriptblock runs the tests once per declared partition (each with
its own test runner and codeunit-range filter), plus one trailing call under
the default runner whose filter is the complement of every explicit partition's
filter.
#>

Import-Module (Join-Path -Path $PSScriptRoot "DebugLogHelper.psm1")

# Codeunit IDs are positive 32-bit integers
$script:maxCodeunitId = [long] 2147483647

function ConvertTo-CodeunitIntervals {
    <#
        .SYNOPSIS
            Parse a partition 'codeunits' filter into a list of [lo, hi] integer intervals.
        .DESCRIPTION
            Only single IDs and closed ranges joined by '|' are supported
            (e.g. '60100|60200..60299'). This is deliberately a subset of the BC
            filter grammar: the complement AL-Go computes for the trailing
            default-runner call is only well-defined over unions of closed
            intervals. The settings schema enforces the same subset; this
            function is the defense for settings that bypassed schema validation.
    #>
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Filter
    )

    $intervals = @()
    foreach ($piece in $Filter.Split('|')) {
        $trimmed = $piece.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -match '^(\d+)$') {
            $lo = [long] $Matches[1]
            $hi = $lo
        }
        elseif ($trimmed -match '^(\d+)\s*\.\.\s*(\d+)$') {
            $lo = [long] $Matches[1]
            $hi = [long] $Matches[2]
        }
        else {
            throw "Unsupported piece '$trimmed' in testIsolation codeunits filter '$Filter'. Supported syntax is single codeunit IDs and closed ranges joined by '|' (e.g. '60100|60200..60299')."
        }
        if ($lo -lt 1 -or $hi -gt $script:maxCodeunitId) {
            throw "Codeunit IDs in testIsolation codeunits filter '$Filter' must be between 1 and $script:maxCodeunitId."
        }
        if ($lo -gt $hi) {
            throw "Invalid range '$trimmed' in testIsolation codeunits filter '$Filter': lower bound is greater than upper bound."
        }
        $intervals += , @($lo, $hi)
    }
    if ($intervals.Count -eq 0) {
        throw "testIsolation codeunits filter '$Filter' does not contain any codeunit IDs."
    }
    return , $intervals
}

function Get-MergedIntervals {
    Param(
        [Parameter(Mandatory = $true)]
        $Intervals
    )

    $sorted = @($Intervals | Sort-Object -Property @{ Expression = { $_[0] } }, @{ Expression = { $_[1] } })
    $merged = @()
    foreach ($interval in $sorted) {
        # Also merge adjacent intervals (lo = previous hi + 1) so the complement never contains empty gaps
        if ($merged.Count -gt 0 -and $interval[0] -le ($merged[-1][1] + 1)) {
            if ($interval[1] -gt $merged[-1][1]) { $merged[-1][1] = $interval[1] }
        }
        else {
            $merged += , @($interval[0], $interval[1])
        }
    }
    return , $merged
}

function Get-ComplementFilter {
    <#
        .SYNOPSIS
            Build a BC filter expression matching every codeunit ID NOT covered by the given merged intervals.
        .DESCRIPTION
            The BC filter grammar has no negation over ranges ('<>' only applies
            to single values), so the exclusion filter is expressed as the
            complement: a '|'-joined union of the gaps, e.g. excluding 60100 and
            60200..60299 yields '..60099|60101..60199|60300..'. Returns an empty
            string when the intervals cover the entire codeunit ID space.
    #>
    Param(
        [Parameter(Mandatory = $true)]
        $MergedIntervals
    )

    $pieces = @()
    $next = [long] 1
    foreach ($interval in $MergedIntervals) {
        if ($interval[0] -gt $next) {
            $gapHi = $interval[0] - 1
            if ($next -eq 1) { $pieces += "..$gapHi" }
            elseif ($next -eq $gapHi) { $pieces += "$next" }
            else { $pieces += "$next..$gapHi" }
        }
        if (($interval[1] + 1) -gt $next) { $next = $interval[1] + 1 }
    }
    if ($next -le $script:maxCodeunitId) {
        $pieces += "$next.."
    }
    return ($pieces -join '|')
}

function New-PartitionedTestRunnerScriptBlock {
    <#
        .SYNOPSIS
            Build a scriptblock for Run-AlPipeline's -RunTestsInBcContainer hook.
        .DESCRIPTION
            Run-AlPipeline invokes the override once per test app with a hashtable
            of parameters (extensionId, containerName, disabledTests, JUnit/XUnit
            file, AppendTo*ResultFile, auth context, etc.). The returned
            scriptblock loops over the configured partitions and, for each one,
            runs the tests with the partition's runner id and codeunit-range
            filter. After all partitions, it issues one trailing call under
            defaultRunnerCodeunitId whose -testCodeunitRange is the complement of
            the union of every explicit partition's filter - so every test
            codeunit not matched by an explicit partition runs under the default
            runner exactly once. If the partitions cover the entire codeunit ID
            space, the trailing call is skipped.

            Result-file appending is preserved because we forward the JUnit/XUnit
            file params Run-AlPipeline already configured (AppendTo*ResultFile = $true).
        .PARAMETER Settings
            The testIsolation settings object with `defaultRunnerCodeunitId` and
            `partitions` (array of @{ runnerCodeunitId; codeunits }). Closed over
            by the returned scriptblock.
        .PARAMETER InnerScriptBlock
            The scriptblock each partitioned call is routed through, with the
            same contract as Run-AlPipeline's -RunTestsInBcContainer override
            (receives a parameter hashtable, returns $true if all tests passed).
            Pass a project's existing RunTestsInBcContainer override here so
            partitioning wraps it instead of replacing it. Defaults to calling
            Run-TestsInBcContainer directly. The scriptblock must splat the
            hashtable on to Run-TestsInBcContainer for the partition-specific
            testCodeunitRange/testRunnerCodeunitId entries to take effect.
        .OUTPUTS
            [scriptblock] returning $true if every invocation reported success.
    #>
    Param(
        [Parameter(Mandatory = $true)]
        $Settings,
        [scriptblock] $InnerScriptBlock
    )

    $capturedPartitions = @($Settings.partitions)
    $capturedDefaultRunner = [int] $Settings.defaultRunnerCodeunitId
    $capturedInner = $InnerScriptBlock
    if (-not $capturedInner) {
        $capturedInner = { Param([Hashtable] $parameters) Run-TestsInBcContainer @parameters }
    }

    $partitionIntervalSets = @()
    foreach ($p in $capturedPartitions) {
        $partitionIntervalSets += , (ConvertTo-CodeunitIntervals -Filter ([string] $p.codeunits))
    }

    # Overlapping partitions run the shared codeunits once per matching partition,
    # duplicating them in the test results - warn, but leave the config decision to the user
    for ($i = 0; $i -lt $partitionIntervalSets.Count; $i++) {
        for ($j = $i + 1; $j -lt $partitionIntervalSets.Count; $j++) {
            $overlaps = $false
            foreach ($a in $partitionIntervalSets[$i]) {
                foreach ($b in $partitionIntervalSets[$j]) {
                    if (($a[0] -le $b[1]) -and ($b[0] -le $a[1])) { $overlaps = $true; break }
                }
                if ($overlaps) { break }
            }
            if ($overlaps) {
                OutputWarning -message "testIsolation partitions overlap: '$($capturedPartitions[$i].codeunits)' (runner $($capturedPartitions[$i].runnerCodeunitId)) and '$($capturedPartitions[$j].codeunits)' (runner $($capturedPartitions[$j].runnerCodeunitId)). Overlapping codeunits run once per matching partition and appear multiple times in the test results."
            }
        }
    }

    $defaultRangeFilter = ''
    $skipDefaultCall = $false
    if ($capturedPartitions.Count -gt 0) {
        $allIntervals = @()
        foreach ($set in $partitionIntervalSets) { $allIntervals += $set }
        $defaultRangeFilter = Get-ComplementFilter -MergedIntervals (Get-MergedIntervals -Intervals $allIntervals)
        $skipDefaultCall = (-not $defaultRangeFilter)
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

            $passed = & $capturedInner $call
            if (-not $passed) { $allPassed = $false }
        }

        if ($skipDefaultCall) {
            Write-Host "Partitions cover the entire codeunit ID space - skipping the default-runner call for app $appId"
        }
        else {
            $defaultCall = @{}
            foreach ($k in $parameters.Keys) { $defaultCall[$k] = $parameters[$k] }
            if ($defaultRangeFilter) { $defaultCall['testCodeunitRange'] = $defaultRangeFilter }
            if ($capturedDefaultRunner -gt 0) { $defaultCall['testRunnerCodeunitId'] = "$capturedDefaultRunner" }
            $defaultRunnerDisplay = if ($capturedDefaultRunner -gt 0) { "$capturedDefaultRunner" } else { "BC default" }

            Write-Host "Running default partition runner=$defaultRunnerDisplay range='$defaultRangeFilter' app=$appId"
            $invocations++

            $passed = & $capturedInner $defaultCall
            if (-not $passed) { $allPassed = $false }
        }

        Write-Host "Partitioned test run for app $appId complete. Invocations: $invocations. All passed: $allPassed"
        return $allPassed
    }.GetNewClosure()
}

Export-ModuleMember -Function New-PartitionedTestRunnerScriptBlock
