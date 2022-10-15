Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0082' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $summarySb = [System.Text.StringBuilder]::new()
    $failuresSb = [System.Text.StringBuilder]::new()
    $testResults = [xml](Get-Content "$project\TestResults.xml")

    $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "appName" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
    if (-not $appNames) {
        $appNames = @($testResults.testsuites.testsuite | ForEach-Object { $_.Properties.property | Where-Object { $_.Name -eq "extensionId" } | ForEach-Object { $_.Value } } | Select-Object -Unique)
    }
    $totalTests = 0
    $totalTime = 0.0
    $totalFailed = 0
    $totalSkipped = 0
    $testResults.testsuites.testsuite | ForEach-Object {
        $totalTests += $_.Tests
        $totalTime += [decimal]::Parse($_.time, [System.Globalization.CultureInfo]::InvariantCulture)
        $totalFailed += $_.failures
        $totalSkipped += $_.skipped
    }
    Write-Host "$($appNames.Count) TestApps, $totalTests tests, $totalFailed failed, $totalSkipped skipped, $totalTime seconds"
    $summarySb.Append('|Test app|Tests|Passed|Failed|Skipped|Time|\n|:---|---:|---:|---:|---:|---:|\n') | Out-Null
    $failuresSb.Append("<details><summary><i>$totalFailed failing tests</i></summary>") | Out-Null
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
        if ($appFailed) {
            $failuresSb.Append("<details><summary><i>$appName, $appTests tests, $appPassed passed, $appFailed failed, $appSkipped skipped, $appTime seconds</i></summary>\n") | Out-Null
            $suites | ForEach-Object {
                Write-Host "  - $($_.name), $($_.tests) tests, $($_.failures) failed, $($_.skipped) skipped, $($_.time) seconds"
                if ($_.failures -gt 0) {
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
    $failuresSb.Append("</details>") | Out-Null
    if ($totalFailed -gt 0) {
        $summarySb.Append("\n\n$($failuresSb.ToString())") | Out-Null
    }
    Add-Content -Path $env:GITHUB_OUTPUT -Value "TestResultMD=$($summarySb.ToString())"
    Write-Host "TestResultMD=$($summarySb.ToString())"

    Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($summarySb.ToString().Replace("\n","`n"))`n"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Deliver action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
