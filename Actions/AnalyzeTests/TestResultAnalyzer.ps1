function GetTestResultSummary {
    Param(
        [xml] $testResults,
        [int] $includeFailures
    )

    $totalTests = 0
    $totalTime = 0.0
    $totalFailed = 0
    $totalSkipped = 0
    $failuresIncluded = 0
    $summarySb = [System.Text.StringBuilder]::new()
    $failuresSb = [System.Text.StringBuilder]::new()
    if ($testResults.testsuites) {
        $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "appName" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
        if (-not $appNames) {
            $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "extensionId" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
        }
        $testResults.testsuites.testsuite | ForEach-Object {
            $totalTests += $_.Tests
            $totalTime += [decimal]::Parse($_.time, [System.Globalization.CultureInfo]::InvariantCulture)
            $totalFailed += $_.failures
            $totalSkipped += $_.skipped
        }
        Write-Host "$($appNames.Count) TestApps, $totalTests tests, $totalFailed failed, $totalSkipped skipped, $totalTime seconds"
        $summarySb.Append('|Test app|Tests|Passed|Failed|Skipped|Time|\n|:---|---:|---:|---:|---:|---:|\n') | Out-Null
        $appNames | ForEach-Object {
            $appName = $_
            $appTests = 0
            $appTime = 0.0
            $appFailed = 0
            $appSkipped = 0
            $suites = $testResults.testsuites.testsuite | where-Object { $_.Properties.property | Where-Object { $_.Value -eq $appName } }
            $suites | ForEach-Object {
                $appTests += [int]$_.tests
                $appFailed += [int]$_.failures
                $appSkipped += [int]$_.skipped
                $appTime += [decimal]::Parse($_.time, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            $appPassed = $appTests-$appFailed-$appSkipped
            Write-Host "- $appName, $appTests tests, $appPassed passed, $appFailed failed, $appSkipped skipped, $appTime seconds"
            $summarySb.Append("|$appName|$appTests|") | Out-Null
            if ($appPassed -gt 0) {
                $summarySb.Append("$($appPassed):white_check_mark:") | Out-Null
            }
            $summarySb.Append("|") | Out-Null
            if ($appFailed -gt 0) {
                $summarySb.Append("$($appFailed):x:") | Out-Null
            }
            $summarySb.Append("|") | Out-Null
            if ($appSkipped -gt 0) {
                $summarySb.Append("$($appSkipped):white_circle:") | Out-Null
            }
            $summarySb.Append("|$($appTime)s|\n") | Out-Null
            if ($appFailed -gt 0) {
                $failuresSb.Append("<details><summary><i>$appName, $appTests tests, $appPassed passed, $appFailed failed, $appSkipped skipped, $appTime seconds</i></summary>\n") | Out-Null
                $suites | ForEach-Object {
                    Write-Host "  - $($_.name), $($_.tests) tests, $($_.failures) failed, $($_.skipped) skipped, $($_.time) seconds"
                    if ($_.failures -gt 0 -and $failuresSb.Length -lt 32000) {
                        $failuresSb.Append("<details><summary><i>$($_.name), $($_.tests) tests, $($_.failures) failed, $($_.skipped) skipped, $($_.time) seconds</i></summary>") | Out-Null
                        $_.testcase | ForEach-Object {
                            if ($_.ChildNodes.Count -gt 0) {
                                Write-Host "    - $($_.name), Failure, $($_.time) seconds"
                                $failuresSb.Append("<details><summary><i>$($_.name), Failure</i></summary>") | Out-Null
                                $_.ChildNodes | ForEach-Object {
                                    Write-Host "      - Error: $($_.message)"
                                    Write-Host "        Stacktrace:"
                                    Write-Host "        $($_."#text".Trim().Replace("`n","`n        "))"
                                    $failuresSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Error: $($_.message)</i><br/>") | Out-Null
                                    $failuresSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Stack trace</i><br/>") | Out-Null
                                    $failuresSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$($_."#text".Trim().Replace("`n","<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"))</i><br/>") | Out-Null
                                }
                                $failuresSb.Append("</details>") | Out-Null
                            }
                        }
                        $failuresSb.Append("</details>") | Out-Null
                        $failuresIncluded++
                    }
                }
                $failuresSb.Append("</details>") | Out-Null
            }
        }
    }
    if ($totalFailed -gt 0) {
        if ($totalFailed -gt $failuresIncluded) {
            $failuresSb.Insert(0,"<details><summary><i>$totalFailed failing tests (showing the first $failuresIncluded here, download test results to see all)</i></summary>") | Out-Null
        }
        else {
            $failuresSb.Insert(0,"<details><summary><i>$totalFailed failing tests</i></summary>") | Out-Null
        }
        $failuresSb.Append("</details>") | Out-Null
        if (($summarySb.Length + $failuresSb.Length) -lt 65000) {
            $summarySb.Append("\n\n$($failuresSb.ToString())") | Out-Null
        }
        else {
            $summarySb.Append("\n\n<i>$totalFailed failing tests. Download test results to see all</i>") | Out-Null
        }
    }
    else {
        $summarySb.Append("\n\n<i>No test failures</i>") | Out-Null
    }
    if ($summarySb.Length -lt 65500) {
        $summarySb.ToString()
    }
    else {
        "<i>$totalFailed failing tests. Download test results to see all</i>"
    }
}
