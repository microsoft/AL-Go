$statusOK = ":heavy_check_mark:"
$statusWarning = ":warning:"
$statusError = ":x:"
$statusSkipped = ":white_circle:"

function ReadBcptFile {
    Param(
        [string] $path
    )

    if ((-not $path) -or (-not (Test-Path -Path $path -PathType Leaf))) {
        return $null
    }

    # Read BCPT file
    $bcptResult = Get-Content -Path $path -Encoding UTF8 | ConvertFrom-Json
    $suites = @{}
    # Sort by bcptCode, codeunitID, operation
    $bcptResult | ForEach-Object {
        $bcptCode = $_.bcptCode
        $codeunitID = $_.codeunitID
        $codeunitName = $_.codeunitName
        $operation = $_.operation

        # Create Suite if it doesn't exist
        if(-not $suites.containsKey($bcptCode)) {
            $suites."$bcptCode" = @{}
        }
        # Create Codeunit under Suite if it doesn't exist
        if (-not $suites."$bcptCode".ContainsKey("$codeunitID")) {
            $suites."$bcptCode"."$codeunitID" = @{
                "codeunitName" = $codeunitName
                "operations" = @{}
            }
        }
        # Create Operation under Codeunit if it doesn't exist
        if (-not $suites."$bcptCode"."$codeunitID"."operations".ContainsKey($operation)) {
            $suites."$bcptCode"."$codeunitID"."operations"."$operation" = @{
                "measurements" = @()
            }
        }
        # Add measurement to measurements under operation
        $suites."$bcptCode"."$codeunitID"."operations"."$operation".measurements += @(@{
            "durationMin" = $_.durationMin
            "numberOfSQLStmts" = $_.numberOfSQLStmts
        })
    }
    $suites
}

function GetBcptSummaryMD {
    Param(
        [string] $path,
        [string] $baseLinePath = '',
        [int] $skipMeasurements = 1,
        [int] $warningThreshold = 5,
        [int] $errorThreshold = 10
    )

    # TODO: grab skipMeasurements and thresholds from settings

    $bcpt = ReadBcptFile -path $path
    $baseLine = ReadBcptFile -path $baseLinePath

    $summarySb = [System.Text.StringBuilder]::new()
    $summarySb.Append("|BCPT Suite|Codeunit ID|Codeunit Name|Operation|$(if ($baseLine){'Status|'})Duration|$(if ($baseLine){'Duration (BaseLine)|'})SQL Stmts|$(if ($baseLine){'SQL Stmts (BaseLine)|'})\n|:---|:---|:---|:---|$(if ($baseLine){'---:|'}):--:|$(if ($baseLine){'---:|'})---:|$(if ($baseLine){'---:|'})\n") | Out-Null

    $lastSuiteName = ''
    $lastCodeunitID = ''
    $lastCodeunitName = ''
    $lastOperationName = ''

    # calculate statistics on measurements, skipping the $skipMeasurements longest measurements
    $bcpt.Keys | ForEach-Object {
        $suiteName = $_
        $suite = $bcpt."$suiteName"
        $suite.Keys | ForEach-Object {
            $codeUnitID = $_
            $codeunit = $suite."$codeunitID"
            $codeUnitName = $codeunit.codeunitName
            $codeunit."operations".Keys | ForEach-Object {
                $operationName = $_
                $operation = $codeunit."operations"."$operationName"
                # Get measurements to use for statistics
                $measurements = @($operation."measurements" | Sort-Object -Descending { $_.durationMin } | Select-Object -Skip $skipMeasurements)
                # Calculate statistics and store them in the operation
                $durationMin = ($measurements | ForEach-Object { $_.durationMin } | Measure-Object -Average).Average
                $numberOfSQLStmts = ($measurements | ForEach-Object { $_.numberOfSQLStmts } | Measure-Object -Average).Average

                $baseLineFound = $true
                try {
                    $baseLineMeasurements = @($baseLine."$suiteName"."$codeUnitID"."operations"."$operationName"."measurements" | Sort-Object -Descending { $_.durationMin } | Select-Object -Skip $skipMeasurements)
                    if ($baseLineMeasurements.Count -eq 0) {
                        throw "No base line measurements"
                    }
                    $baseLineDurationMin = ($baseLineMeasurements | ForEach-Object { $_.durationMin } | Measure-Object -Average).Average
                    $baseLineNumberOfSQLStmts = ($baseLineMeasurements | ForEach-Object { $_.numberOfSQLStmts } | Measure-Object -Average).Average
                }
                catch {
                    $baseLineFound = $false
                    $baseLineDurationMin = $durationMin
                    $baseLineNumberOfSQLStmts = $numberOfSQLStmts
                }

                $pctDurationMin = ($durationMin-$baseLineDurationMin)*100/$baseLineDurationMin
                if ($pctDurationMin -le 0) {
                    $durationMinStr = "**$($durationMin.ToString("N2"))**|"
                    $baseLineDurationMinStr = "$($baseLineDurationMin.ToString("N2"))|"
                }
                else {
                    $durationMinStr = "$($durationMin.ToString("N2"))|"
                    $baseLineDurationMinStr = "**$($baseLineDurationMin.ToString("N2"))**|"
                }

                $pctNumberOfSQLStmts = ($numberOfSQLStmts-$baseLineNumberOfSQLStmts)*100/$baseLineNumberOfSQLStmts
                if ($pctNumberOfSQLStmts -le 0) {
                    $numberOfSQLStmtsStr = "**$($numberOfSQLStmts.ToString("N0"))**|"
                    $baseLineNumberOfSQLStmtsStr = "$($baseLineNumberOfSQLStmts.ToString("N0"))|"
                }
                else {
                    $numberOfSQLStmtsStr = "$($numberOfSQLStmts.ToString("N0"))|"
                    $baseLineNumberOfSQLStmtsStr = "**$($baseLineNumberOfSQLStmts.ToString("N0"))**|"
                }

                if (!$baseLine) {
                    # No baseline provided
                    $statusStr = ''
                    $baselinedurationMinStr = ''
                    $baseLineNumberOfSQLStmtsStr = ''
                }
                else {
                    if (!$baseLineFound) {
                        # Baseline provided, but not found for this operation
                        $statusStr = ''
                        $baselinedurationMinStr = 'N/A|'
                        $baseLineNumberOfSQLStmtsStr = 'N/A|'
                    }
                    else {
                        $statusStr = $statusOK
                        if ($pctDurationMin -ge $errorThreshold) {
                            $statusStr = $statusError
                            OutputError -message "$operationName in $($suiteName):$codeUnitID degrades $($pctDurationMin.ToString('N0'))%, which exceeds the error threshold of $($errorThreshold)% for duration"
                        }
                        if ($pctNumberOfSQLStmts -ge $errorThreshold) {
                            $statusStr = $statusError
                            OutputError -message "$operationName in $($suiteName):$codeUnitID degrades $($pctNumberOfSQLStmts.ToString('N0'))%, which exceeds the error threshold of $($errorThreshold)% for number of SQL statements"
                        }
                        if ($statusStr -eq $statusOK) {
                            if ($pctDurationMin -ge $warningThreshold) {
                                $statusStr = $statusWarning
                                OutputWarning -message "$operationName in $($suiteName):$codeUnitID degrades $($pctDurationMin.ToString('N0'))%, which exceeds the warning threshold of $($warningThreshold)% for duration"
                            }
                            if ($pctNumberOfSQLStmts -ge $warningThreshold) {
                                $statusStr = $statusWarning
                                OutputWarning -message "$operationName in $($suiteName):$codeUnitID degrades $($pctNumberOfSQLStmts.ToString('N0'))%, which exceeds the warning threshold of $($warningThreshold)% for number of SQL statements"
                            }
                        }
                    }
                    $statusStr += '|'
                }

                $thisOperationName = ''; if ($operationName -ne $lastOperationName) { $thisOperationName = $operationName }
                $thisCodeunitName = ''; if ($codeunitName -ne $lastCodeunitName) { $thisCodeunitName = $codeunitName; $thisOperationName = $operationName }
                $thisCodeunitID = ''; if ($codeunitID -ne $lastCodeunitID) { $thisCodeunitID = $codeunitID; $thisOperationName = $operationName }
                $thisSuiteName = ''; if ($suiteName -ne $lastSuiteName) { $thisSuiteName = $suiteName; $thisOperationName = $operationName }

                $summarySb.Append("|$thisSuiteName|$thisCodeunitID|$thisCodeunitName|$thisOperationName|$statusStr$durationMinStr$baseLineDurationMinStr$numberOfSQLStmtsStr$baseLineNumberOfSQLStmtsStr\n") | Out-Null

                $lastSuiteName = $suiteName
                $lastCodeunitID = $codeUnitID
                $lastCodeunitName = $codeUnitName
                $lastOperationName = $operationName
            }
        }
    }

    if (-not $baseLine) {
        $summarySb.Append("\n<i>No baseline provided. Copy a set of BCPT results to $([System.IO.Path]::GetFileName($baseLinePath)) in the project folder in order to establish a baseline.</i>") | Out-Null
    }
    
    $summarySb.ToString()
}

# Build MarkDown of TestResults file
# This function will not fail if the file does not exist or if any test errors are found
# TestResults is in JUnit format
# Returns both a summary part and a failures part
function GetTestResultSummaryMD {
    Param(
        [string] $path
    )

    $summarySb = [System.Text.StringBuilder]::new()
    $failuresSb = [System.Text.StringBuilder]::new()
    if (Test-Path -Path $path -PathType Leaf) {
        $testResults = [xml](Get-Content -path "$project\TestResults.xml" -Encoding UTF8)
        $totalTests = 0
        $totalTime = 0.0
        $totalFailed = 0
        $totalSkipped = 0
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
                    $summarySb.Append("$($appPassed)$statusOK") | Out-Null
                }
                $summarySb.Append("|") | Out-Null
                if ($appFailed -gt 0) {
                    $summarySb.Append("$($appFailed)$statusError") | Out-Null
                }
                $summarySb.Append("|") | Out-Null
                if ($appSkipped -gt 0) {
                    $summarySb.Append("$($appSkipped)$statusSkipped") | Out-Null
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
                        }
                    }
                    $failuresSb.Append("</details>") | Out-Null
                }
            }
        }
        $failuresSummaryMD = ""
        if ($totalFailed -gt 0) {
            $failuresSummaryMD = "<i>$totalFailed failing tests, download test results to see details</i>"
            $failuresSb.Insert(0,"<details><summary>$failuresSummaryMD</summary>") | Out-Null
            $failuresSb.Append("</details>") | Out-Null
        }
        else {
            $failuresSummaryMD = "<i>No test failures</i>"
            $failuresSb.Append($failuresSummaryMD) | Out-Null
        }
    }
    else {
        $summarySb.Append("<i>No test results found</i>") | Out-Null
    }
    $summarySb.ToString()
    $failuresSb.ToString()
    $failuresSummaryMD
}
