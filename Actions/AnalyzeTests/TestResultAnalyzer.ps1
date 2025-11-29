$statusOK = " :heavy_check_mark:"
$statusWarning = " :warning:"
$statusError = " :x:"
$statusSkipped = " :question:"

# Build MarkDown of TestResults file
# This function will not fail if the file does not exist or if any test errors are found
# TestResults is in JUnit format
# Returns both a summary part and a failures part
$mdHelperPath = Join-Path -Path $PSScriptRoot -ChildPath "..\MarkDownHelper.psm1"
Import-Module $mdHelperPath
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)

#Helper function to build a markdown table.
#Headers are an array of strings with format "label;alignment" where alignment is 'left', 'right' or 'center'
#Rows is a 2D array of data.
#ResultIcons is a hashtable with column index as key and emoji/icon as value. This is needed because we display an emojis/icons with any result > 0, and an empty cell if the result is 0
function BuildTestMarkdownTable {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Headers,
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList] $Rows,
        [hashtable] $resultIcons
    )

    $mdTableRows = [System.Collections.ArrayList]@()
    $mdTableSB = [System.Text.StringBuilder]::new()

    foreach($row in $Rows) {
        $row -join ',' | Out-Host
        $formattedRow = @()
        for($i=0; $i -lt $row.Length; $i++) {
            #If resultIcons has a key for this column, we want to display an emoji for values > 0 and an empty cell for 0
            if ($resultIcons.ContainsKey($i)) {
                if ($row[$i] -gt 0) {
                    $formattedRow += "$($row[$i])$($resultIcons[$i])"
                }
                else {
                    $formattedRow += ""
                }
            } else {
                $formattedRow += "$($row[$i])"
            }
        }
        $mdTableRows.Add($formattedRow) | Out-Null
        "|$($formattedRow -join '|')|" | Out-Host
    }

    $mdTable = ''
    try {
        $mdTable = Build-MarkdownTable -Headers $Headers -Rows $mdTableRows
    } catch {
        $mdTable = "<i>Failed to generate result table</i>"
    }
    $mdTableSB.Append($mdTable) | Out-Null

    return $mdTableSB
}

class FailureNode {
    [string]$errorMessage
    [string]$errorStackTrace
    [bool]$isLeaf
    [System.Collections.ArrayList]$childSummaries
    [string]$summaryDetails

    FailureNode([bool]$isLeaf = $false) {
        $this.errorMessage = ''
        $this.errorStackTrace = ''
        $this.isLeaf = $isLeaf
        $this.childSummaries = @()
        $this.summaryDetails = ''
    }
}

#Helper function to build a html structure. Example output below where whitespace is kept for readability.
# <details><summary><i>SomeText</i></summary>
#     <... more nested <details> ...>
#         <i>Error: some error</i><br/> 6x&nbsp; not included for readability
#         <i>Stack trace:</i><br/>
#         <i>some stack trace</i><br/>
# </details>
function BuildHTMLFailureSummary {
    Param(
        [FailureNode]$rootFailureNode
    )

    $htmlFailureSb = [System.Text.StringBuilder]::new()
    $stack = [System.Collections.Stack]::new()
    $stack.push(@{ Node = $rootFailureNode; level = 0 })
    $currentLevel = 0

    while($stack.Count -gt 0) {
        $currentObject = $stack.pop()
        $node = $currentObject.Node
        $level = $currentObject.level

        while($currentLevel -gt $level) {
            $htmlFailureSb.Append("</details>") | Out-Null
            $currentLevel--
        }
        $currentLevel = $level

        #If we are at a leaf, insert the error message and stack trace
        if ($node.isLeaf) {
            $htmlFailureSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Error: $($node.errorMessage)</i><br/>") | Out-Null
            $htmlFailureSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Stack trace:</i><br/>") | Out-Null
            $htmlFailureSb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$($node.errorStackTrace)</i><br/>") | Out-Null
        }
        #If we are not at a leaf, insert the summary details and push the children to the stack
        else {
            $htmlFailureSb.Append("<details><summary><i>$($node.summaryDetails)</i></summary>") | Out-Null

            for($i=$node.childSummaries.Count-1; $i -ge 0; $i--) {
                $stack.push(@{ Node = $node.childSummaries[$i]; Level = $level+1 })
            }
        }
    }

    while ($currentLevel -gt 0) {
        $htmlFailureSb.Append("</details>") | Out-Null
        $currentLevel--
    }

    return $htmlFailureSb
}

function GetTestResultSummaryMD {
    Param(
        [string] $testResultsFile
    )

    $summarySb = [System.Text.StringBuilder]::new()
    $failuresSb = [System.Text.StringBuilder]::new()
    $totalTests = 0
    $totalTime = 0.0
    $totalFailed = 0
    $totalSkipped = 0
    $totalPassed = 0

    if (Test-Path -Path $testResultsFile -PathType Leaf) {
        $testResults = [xml](Get-Content -path $testResultsFile -Encoding UTF8)

        if ($testResults.testsuites) {
            $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "appName" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
            if (-not $appNames) {
                $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "extensionId" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
            }
            foreach($testsuite in $testResults.testsuites.testsuite) {
                $totalTests += $testsuite.Tests
                $totalTime += [decimal]::Parse($testsuite.time, [System.Globalization.CultureInfo]::InvariantCulture)
                $totalFailed += $testsuite.failures
                $totalSkipped += $testsuite.skipped
            }
            Write-Host "$($appNames.Count) TestApps, $totalTests tests, $totalFailed failed, $totalSkipped skipped, $totalTime seconds"
            $mdTableHeaders = @("Test app;left", "Tests;right", "Passed;right", "Failed;right", "Skipped;right", "Time;right")
            $mdTableEmojis = @{
                2 = $statusOK
                3 = $statusError
                4 = $statusSkipped
            }
            $mdTableRows = [System.Collections.ArrayList]@()
            foreach($appName in $appNames) {
                $appTests = 0
                $appTime = 0.0
                $appFailed = 0
                $appSkipped = 0
                $suites = $testResults.testsuites.testsuite | where-Object { $_.Properties.property | Where-Object { ($_.Name -eq 'appName' -or $_.Name -eq 'extensionId') -and $_.Value -eq $appName } }
                foreach($suite in $suites) {
                    $appTests += [int]$suite.tests
                    $appFailed += [int]$suite.failures
                    $appSkipped += [int]$suite.skipped
                    $appTime += [decimal]::Parse($suite.time, [System.Globalization.CultureInfo]::InvariantCulture)
                }
                $appPassed = $appTests-$appFailed-$appSkipped
                Write-Host "- $appName, $appTests tests, $appPassed passed, $appFailed failed, $appSkipped skipped, $appTime seconds"
                $mdTableRow = @( $appName, $appTests, $appPassed, $appFailed, $appSkipped, $appTime )
                $mdTableRows.Add($mdTableRow) | Out-Null
                if ($appFailed -gt 0) {
                    $rootFailureNode = [FailureNode]::new($false)
                    $rootFailureNode.summaryDetails = "$appName, $appTests tests, $appPassed passed, $appFailed failed, $appSkipped skipped, $appTime seconds"
                    foreach($suite in $suites) {
                        Write-Host "  - $($suite.name), $($suite.tests) tests, $($suite.failures) failed, $($suite.skipped) skipped, $($suite.time) seconds"
                        if ($suite.failures -gt 0 -and $failuresSb.Length -lt 32000) {
                            $suiteFailureNode = [FailureNode]::new($false)
                            $suiteFailureNode.summaryDetails = "$($suite.name), $($suite.tests) tests, $($suite.failures) failed, $($suite.skipped) skipped, $($suite.time) seconds"
                            foreach($testcase in $suite.testcase) {
                                if ($testcase.ChildNodes.Count -gt 0) {
                                    Write-Host "    - $($testcase.name), Failure, $($testcase.time) seconds"
                                    $testCaseFailureNode = [FailureNode]::new($false)
                                    $testCaseFailureNode.summaryDetails = "$($testcase.name), Failure"
                                    foreach($failure in $testcase.ChildNodes) {
                                        Write-Host "      - Error: $($failure.message)"
                                        Write-Host "        Stacktrace:"
                                        Write-Host "        $($failure."#text".Trim().Replace("`n","`n        "))"
                                        $testFailureNode = [FailureNode]::new($true)
                                        $testFailureNode.errorMessage = $failure.message
                                        $testFailureNode.errorStackTrace = $($failure."#text".Trim().Replace("`n","<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"))
                                        $testCaseFailureNode.childSummaries.Add($testFailureNode) | Out-Null
                                    }
                                    $suiteFailureNode.childSummaries.Add($testCaseFailureNode) | Out-Null
                                }
                            }
                            $rootFailureNode.childSummaries.Add($suiteFailureNode) | Out-Null
                        }
                    }
                    $failuresSB = BuildHTMLFailureSummary -rootFailureNode $rootFailureNode
                }
            }
            $summarySb = BuildTestMarkdownTable -Headers $mdTableHeaders -Rows $mdTableRows -resultIcons $mdTableEmojis
        }
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
        $failuresSummaryMD = ''
    }

    # Log test metrics to telemetry
    $totalPassed = $totalTests - $totalFailed - $totalSkipped
    if ($totalTests -gt 0) {
        $telemetryData = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalTests' -Value $totalTests.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalFailed' -Value $totalFailed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalSkipped' -Value $totalSkipped.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalPassed' -Value $totalPassed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalTime' -Value $totalTime.ToString()
        Trace-Information -Message "Test results" -AdditionalData $telemetryData
    }

    $summarySb.ToString()
    $failuresSb.ToString()
    $failuresSummaryMD
}

function ReadBcptFile {
    Param(
        [string] $bcptTestResultsFile
    )

    if ((-not $bcptTestResultsFile) -or (-not (Test-Path -Path $bcptTestResultsFile -PathType Leaf))) {
        return $null
    }

    # Read BCPT file
    $bcptResult = Get-Content -Path $bcptTestResultsFile -Encoding UTF8 | ConvertFrom-Json
    $suites = [ordered]@{}
    # Sort by bcptCode, codeunitID, operation
    foreach($measure in $bcptResult) {
        $bcptCode = $measure.bcptCode
        $codeunitID = $measure.codeunitID
        $codeunitName = $measure.codeunitName
        $operation = $measure.operation

        # Create Suite if it doesn't exist
        if(-not $suites.Contains($bcptCode)) {
            $suites."$bcptCode" = [ordered]@{}
        }
        # Create Codeunit under Suite if it doesn't exist
        if (-not $suites."$bcptCode".Contains("$codeunitID")) {
            $suites."$bcptCode"."$codeunitID" = @{
                "codeunitName" = $codeunitName
                "operations" = [ordered]@{}
            }
        }
        # Create Operation under Codeunit if it doesn't exist
        if (-not $suites."$bcptCode"."$codeunitID"."operations".Contains($operation)) {
            $suites."$bcptCode"."$codeunitID"."operations"."$operation" = @{
                "measurements" = @()
            }
        }
        # Add measurement to measurements under operation
        $suites."$bcptCode"."$codeunitID"."operations"."$operation".measurements += @(@{
            "durationMin" = $measure.durationMin
            "numberOfSQLStmts" = $measure.numberOfSQLStmts
        })
    }
    $suites
}

function GetBcptSummaryMD {
    Param(
        [string] $bcptTestResultsFile,
        [string] $baseLinePath = '',
        [string] $thresholdsPath = '',
        [int] $skipMeasurements = 0,
        [hashtable] $bcptThresholds = $null
    )

    $bcpt = ReadBcptFile -bcptTestResultsFile $bcptTestResultsFile
    if (-not $bcpt) {
        return ''
    }
    $baseLine = ReadBcptFile -bcptTestResultsFile $baseLinePath
    if ($baseLine) {
        if ($null -eq $bcptThresholds) {
            throw "Thresholds must be provided when comparing to a baseline"
        }
        # Override thresholds if thresholds file exists
        if ($thresholdsPath -and (Test-Path -path $thresholdsPath)) {
            Write-Host "Reading thresholds from $thresholdsPath"
            $thresholds = Get-Content -Path $thresholdsPath -Encoding UTF8 | ConvertFrom-Json
            foreach($threshold in 'durationWarning', 'durationError', 'numberOfSqlStmtsWarning', 'numberOfSqlStmtsError') {
                if ($thresholds.PSObject.Properties.Name -eq $threshold) {
                    $bcptThresholds."$threshold" = $thresholds."$threshold"
                }
            }
        }
        Write-Host "Using thresholds:"
        Write-Host "- DurationWarning: $($bcptThresholds.durationWarning)"
        Write-Host "- DurationError: $($bcptThresholds.durationError)"
        Write-Host "- NumberOfSqlStmtsWarning: $($bcptThresholds.numberOfSqlStmtsWarning)"
        Write-Host "- NumberOfSqlStmtsError: $($bcptThresholds.numberOfSqlStmtsError)"
    }

    $summarySb = [System.Text.StringBuilder]::new()
    $mdTableHeaders = @()
    $mdTableEmojis = @{}
    $mdTableRows = [System.Collections.ArrayList]@()
    if ($baseLine) {
        $mdTableHeaders = @("BCPT Suite;l", "Codeunit ID;l", "Codeunit Name;l", "Operation;l", "Status;c", "Duration (ms);r", "Duration base (ms);r", "Duration diff (ms);r", "Duration diff;r", "SQL Stmts;r", "SQL Stmts base;r", "SQL Stmts diff;r", "SQL Stmts diff;r")
    }
    else {
        $mdTableHeaders = @("BCPT Suite;l", "Codeunit ID;l", "Codeunit Name;l", "Operation;l", "Duration (ms);r", "SQL Stmts;r")
    }

    $lastSuiteName = ''
    $lastCodeunitID = ''
    $lastCodeunitName = ''
    $lastOperationName = ''

    $totalTests = 0
    $totalPassed = 0
    $totalFailed = 0
    $totalSkipped = 0

    # calculate statistics on measurements, skipping the $skipMeasurements longest measurements
    foreach($suiteName in $bcpt.Keys) {
        $suite = $bcpt."$suiteName"
        foreach($codeUnitID in $suite.Keys) {
            $codeunit = $suite."$codeunitID"
            $codeUnitName = $codeunit.codeunitName
            foreach($operationName in $codeunit."operations".Keys) {
                $operation = $codeunit."operations"."$operationName"
                # Get measurements to use for statistics
                $measurements = @($operation."measurements" | Sort-Object -Descending { $_.durationMin } | Select-Object -Skip $skipMeasurements)
                # Calculate statistics and store them in the operation
                $durationMin = ($measurements | ForEach-Object { $_.durationMin } | Measure-Object -Minimum).Minimum
                $numberOfSQLStmts = ($measurements | ForEach-Object { $_.numberOfSQLStmts } | Measure-Object -Minimum).Minimum

                $baseLineFound = $true
                try {
                    $baseLineMeasurements = @($baseLine."$suiteName"."$codeUnitID"."operations"."$operationName"."measurements" | Sort-Object -Descending { $_.durationMin } | Select-Object -Skip $skipMeasurements)
                    if ($baseLineMeasurements.Count -eq 0) {
                        throw "No base line measurements"
                    }
                    $baseDurationMin = ($baseLineMeasurements | ForEach-Object { $_.durationMin } | Measure-Object -Minimum).Minimum
                    $diffDurationMin = $durationMin-$baseDurationMin
                    $baseNumberOfSQLStmts = ($baseLineMeasurements | ForEach-Object { $_.numberOfSQLStmts } | Measure-Object -Minimum).Minimum
                    $diffNumberOfSQLStmts = $numberOfSQLStmts-$baseNumberOfSQLStmts
                }
                catch {
                    $baseLineFound = $false
                    $baseDurationMin = $durationMin
                    $diffDurationMin = 0
                    $baseNumberOfSQLStmts = $numberOfSQLStmts
                    $diffNumberOfSQLStmts = 0
                }

                $pctDurationMin = ($durationMin-$baseDurationMin)*100/$baseDurationMin
                $durationMinStr = "$($durationMin.ToString("#"))"
                $baseDurationMinStr = "$($baseDurationMin.ToString("#"))"
                $diffDurationMinStr = "$($diffDurationMin.ToString("+#;-#;0"))"
                $diffDurationMinPctStr = "$($pctDurationMin.ToString('+#;-#;0'))%"

                $pctNumberOfSQLStmts = ($numberOfSQLStmts-$baseNumberOfSQLStmts)*100/$baseNumberOfSQLStmts
                $numberOfSQLStmtsStr = "$($numberOfSQLStmts.ToString("#"))"
                $baseNumberOfSQLStmtsStr = "$($baseNumberOfSQLStmts.ToString("#"))"
                $diffNumberOfSQLStmtsStr = "$($diffNumberOfSQLStmts.ToString("+#;-#;0"))"
                $diffNumberOfSQLStmtsPctStr = "$($pctNumberOfSQLStmts.ToString('+#;-#;0'))%"

                $thisOperationName = ''; if ($operationName -ne $lastOperationName) { $thisOperationName = $operationName }
                $thisCodeunitName = ''; if ($codeunitName -ne $lastCodeunitName) { $thisCodeunitName = $codeunitName; $thisOperationName = $operationName }
                $thisCodeunitID = ''; if ($codeunitID -ne $lastCodeunitID) { $thisCodeunitID = $codeunitID; $thisOperationName = $operationName }
                $thisSuiteName = ''; if ($suiteName -ne $lastSuiteName) { $thisSuiteName = $suiteName; $thisOperationName = $operationName }

                $mdTableRow = @()
                if (!$baseLine) {
                    # No baseline provided
                    $mdTableRow = @($thisSuiteName, $thisCodeunitID, $thisCodeunitName, $thisOperationName, $durationMinStr, $numberOfSQLStmtsStr)
                }
                else {
                    if (!$baseLineFound) {
                        # Baseline provided, but not found for this operation
                        $statusStr = $statusSkipped
                        $baseDurationMinStr = 'N/A'
                        $diffDurationMinStr = ''
                        $baseNumberOfSQLStmtsStr = 'N/A'
                        $diffNumberOfSQLStmtsStr = ''
                        $mdTableRow = @($thisSuiteName, $thisCodeunitID, $thisCodeunitName, $thisOperationName, $statusStr, $durationMinStr, $baseDurationMinStr, '', '', $numberOfSQLStmtsStr, $baseNumberOfSQLStmtsStr, '', '')
                    }
                    else {
                        $statusStr = $statusOK
                        if ($pctDurationMin -ge $bcptThresholds.durationError) {
                            $statusStr = $statusError
                            if ($thisCodeunitName) {
                                # Only give errors and warnings on top level operation
                                OutputError -message "$operationName in $($suiteName):$codeUnitID degrades $($pctDurationMin.ToString('N0'))%, which exceeds the error threshold of $($bcptThresholds.durationError)% for duration"
                            }
                        }
                        if ($pctNumberOfSQLStmts -ge $bcptThresholds.numberOfSqlStmtsError) {
                            $statusStr = $statusError
                            if ($thisCodeunitName) {
                                # Only give errors and warnings on top level operation
                                OutputError -message "$operationName in $($suiteName):$codeUnitID degrades $($pctNumberOfSQLStmts.ToString('N0'))%, which exceeds the error threshold of $($bcptThresholds.numberOfSqlStmtsError)% for number of SQL statements"
                            }
                        }
                        if ($statusStr -eq $statusOK) {
                            if ($pctDurationMin -ge $bcptThresholds.durationWarning) {
                                $statusStr = $statusWarning
                                if ($thisCodeunitName) {
                                    # Only give errors and warnings on top level operation
                                    OutputWarning -message "$operationName in $($suiteName):$codeUnitID degrades $($pctDurationMin.ToString('N0'))%, which exceeds the warning threshold of $($bcptThresholds.durationWarning)% for duration"
                                }
                            }
                            if ($pctNumberOfSQLStmts -ge $bcptThresholds.numberOfSqlStmtsWarning) {
                                $statusStr = $statusWarning
                                if ($thisCodeunitName) {
                                    # Only give errors and warnings on top level operation
                                    OutputWarning -message "$operationName in $($suiteName):$codeUnitID degrades $($pctNumberOfSQLStmts.ToString('N0'))%, which exceeds the warning threshold of $($bcptThresholds.numberOfSqlStmtsWarning)% for number of SQL statements"
                                }
                            }
                        }
                        $mdTableRow = @($thisSuiteName, $thisCodeunitID, $thisCodeunitName, $thisOperationName, $statusStr, $durationMinStr, $baseDurationMinStr, $diffDurationMinStr, $diffDurationMinPctStr, $numberOfSQLStmtsStr, $baseNumberOfSQLStmtsStr, $diffNumberOfSQLStmtsStr, $diffNumberOfSQLStmtsPctStr)
                    }
                }
                $mdTableRows.Add($mdTableRow) | Out-Null

                # Update test counts
                switch ($statusStr) {
                    $statusOK { $totalPassed++ }
                    $statusWarning { $totalFailed++ }
                    $statusError { $totalFailed++ }
                    $statusSkipped { $totalSkipped++ }
                }

                $lastSuiteName = $suiteName
                $lastCodeunitID = $codeUnitID
                $lastCodeunitName = $codeUnitName
                $lastOperationName = $operationName
            }
        }
    }

    $summarySb = BuildTestMarkdownTable -Headers $mdTableHeaders -Rows $mdTableRows -resultIcons $mdTableEmojis
    if ($baseLine) {
        $summarySb.AppendLine("\n<i>Used baseline provided in $([System.IO.Path]::GetFileName($baseLinePath)).</i>") | Out-Null
    }
    else {
        $summarySb.AppendLine("\n<i>No baseline provided. Copy a set of BCPT results to $([System.IO.Path]::GetFileName($baseLinePath)) in the project folder in order to establish a baseline.</i>") | Out-Null
    }

    # Log BCPT metrics to telemetry
    $totalTests = $totalPassed + $totalFailed + $totalSkipped
    if ($totalTests -gt 0) {
        $telemetryData = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalTests' -Value $totalTests.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalPassed' -Value $totalPassed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalFailed' -Value $totalFailed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalSkipped' -Value $totalSkipped.ToString()
        Trace-Information -Message "BCPT test results" -AdditionalData $telemetryData
    }

    $summarySb.ToString()
}

function GetPageScriptingTestResultSummaryMD {
    Param(
        [string] $testResultsFile,
        [string] $project = ''
    )

    $summarySb = [System.Text.StringBuilder]::new()
    $failuresSb = [System.Text.StringBuilder]::new()
    $totalTests = 0
    $totalTime = 0.0
    $totalFailed = 0
    $totalSkipped = 0
    $totalPassed = 0

    if (Test-Path -Path $testResultsFile -PathType Leaf) {
        $testResults = [xml](Get-Content -path $testResultsFile -Encoding UTF8)

        $rootFailureNode = [FailureNode]::new($false)
        if ($testResults.testsuites) {
            $totalTests = $testResults.testsuites.tests
            $totalTime = $testResults.testsuites.time
            $totalFailed = $testResults.testsuites.failures
            $totalSkipped = $testResults.testsuites.skipped
            $totalPassed = $totalTests - $totalFailed - $totalSkipped

            #Write total summary for all test suites
            Write-Host "$totalTests tests, $totalPassed passed, $totalFailed failed, $totalSkipped skipped, $totalTime seconds"
            $mdTableHeaders = @("Suite;left", "Tests;right", "Passed;right", "Failed;right", "Skipped;right", "Time;right")
            $mdTableEmojis = @{
                2 = $statusOK
                3 = $statusError
                4 = $statusSkipped
            }
            $mdTableRows = [System.Collections.ArrayList]@()

            foreach($testsuite in $testResults.testsuites.testsuite) {
                $suitePrettyName = if ($project) { $testsuite.name -replace ".*?(?=$project)",  "" } else { "" }
                $suiteTests = $testsuite.tests
                $suiteTime = $testsuite.time
                $suiteFailed = $testsuite.failures
                $suiteSkipped = $testsuite.skipped
                $suitePassed = $suiteTests - $suiteFailed - $suiteSkipped
                $mdTableRow = @($suitePrettyName, $suiteTests, $suitePassed, $suiteFailed, $suiteSkipped, $suiteTime)
                $mdTableRows.Add($mdTableRow) | Out-Null

                if ($suiteFailed -gt 0 ) {
                    $suiteFailureNode = [FailureNode]::new($false)
                    $suiteFailureNode.summaryDetails = "$suitePrettyName, $suiteTests tests, $suitePassed passed, $suiteFailed failed, $suiteSkipped skipped, $suiteTime seconds"
                    foreach($testcase in $testsuite.testcase) {
                        $testName = Split-Path ($testcase.name -replace '\(', '' -replace '\)', '') -Leaf
                        if ($testcase.failure) {
                            Write-Host "      - Error: $($testcase.failure.message)"
                            Write-Host "        Stacktrace:"
                            Write-Host "        $($testcase.failure."#cdata-section".Trim().Replace("`n","`n        "))"
                            $testCaseSummaryNode = [FailureNode]::new($false)
                            $testCaseSummaryNode.summaryDetails = "$($testName), Failure"
                            $testCaseFailureNode = [FailureNode]::new($true)
                            $testCaseFailureNode.errorMessage = $testcase.failure.message
                            $testCaseFailureNode.errorStackTrace = $testcase.failure."#cdata-section"
                            $testCaseSummaryNode.childSummaries.Add($testCaseFailureNode) | Out-Null
                            $suiteFailureNode.childSummaries.Add($testCaseSummaryNode) | Out-Null
                        }
                    }
                    $rootFailureNode.childSummaries.Add($suiteFailureNode) | Out-Null
                }
            }
            $summarySb = BuildTestMarkdownTable -Headers $mdTableHeaders -Rows $mdTableRows -resultIcons $mdTableEmojis
        }
        if ($totalFailed -gt 0) {
            $failuresSb = BuildHTMLFailureSummary -rootFailureNode $rootFailureNode
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
        Write-Host "Did not find test results file"
        $failuresSummaryMD = ''
    }

    # Log test metrics to telemetry
    if ($totalTests -gt 0) {
        $telemetryData = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalTests' -Value $totalTests.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalPassed' -Value $totalPassed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalFailed' -Value $totalFailed.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalSkipped' -Value $totalSkipped.ToString()
        Add-TelemetryProperty -Hashtable $telemetryData -Key 'TotalTime' -Value $totalTime.ToString()
        Trace-Information -Message "Page scripting test results" -AdditionalData $telemetryData
    }

    return @{
        SummaryMD = $summarySb.ToString()
        FailuresMD = $failuresSb.ToString()
        FailuresSummaryMD = $failuresSummaryMD
    }
}
