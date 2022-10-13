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

    $sb = [System.Text.StringBuilder]::new()
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
    if ($totalFailed) {
        $pre = "<i><b>"
        $post = "</b></i>"
    }
    else {
        $pre = "<i>"
        $post = "</i>"
    }
    $sb.Append("<details><summary>$pre$($appNames.Count) TestApps, $totalTests tests, $totalFailed failed, $totalSkipped skipped, $totalTime seconds$post</summary>") | Out-Null
    $appNames | ForEach-Object {
        $appName = $_
        $appTests = 0
        $appTime = 0.0
        $appFailed = 0
        $appSkipped = 0
        $suites = $testResults.testsuites.testsuite | where-Object { $_.Properties.property | Where-Object { $_.Value -eq $appName } }
        $suites | ForEach-Object {
            $appTests += $_.tests
            $appFailed += $_.failures
            $appSkipped += $_.skipped
            $appTime += [decimal]::Parse($_.time, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        Write-Host "- $appName, $appTests tests, $appFailed failed, $appSkipped skipped, $appTime seconds"
        if ($appFailed) {
            $pre = "<i><b>"
            $post = "</b></i>"
        }
        else {
            $pre = "<i>"
            $post = "</i>"
        }
        $sb.Append("<details><summary>$pre$appName, $appTests tests, $appFailed failed, $appSkipped skipped, $appTime seconds$post</summary>") | Out-Null
        $suites | ForEach-Object {
            Write-Host "  - $($_.name), $($_.tests) tests, $($_.failures) failed, $($_.skipped) skipped, $($_.time) seconds"
            if ($_.failures -gt 0) {
                $pre = "<i><b>"
                $post = "</b></i>"
            }
            else {
                $pre = "<i>"
                $post = "</i>"
            }
            $sb.Append("<details><summary>$pre$($_.name), $($_.tests) tests, $($_.failures) failed, $($_.skipped) skipped, $($_.time) seconds$post</summary>") | Out-Null
            $_.testcase | ForEach-Object {
                if ($_.ChildNodes.Count -gt 0) {
                    Write-Host "    - $($_.name), Failure, $($_.time) seconds"
                    $sb.Append("<details><summary><i><b>$($_.name), Failure</b></i></summary>") | Out-Null
                    $_.ChildNodes | ForEach-Object {
                        Write-Host "      - Error: $($_.message)"
                        Write-Host "        Stacktrace:"
                        Write-Host "        $($_."#text".Trim().Replace("`n","`n        "))"
                        $sb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Error: $($_.message)</b></i><br/>") | Out-Null
                        $sb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Stack trace</i><br/>") | Out-Null
                        $sb.Append("<i>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$($_."#text".Trim().Replace("`n","<br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"))</i><br/>") | Out-Null
                    }
                    $sb.Append("</details>") | Out-Null
                }
                else {
                    Write-Host "    - $($_.name), Success, $($_.time) seconds"
                    $sb.Append("&nbsp;&nbsp;&nbsp;&nbsp;<i>$($_.name), Success</i><br/>") | Out-Null
                }
            }
            $sb.Append("</details>") | Out-Null
        }
        $sb.Append("</details>") | Out-Null
    }
    $sb.Append("</details>") | Out-Null
    Add-Content -Path $env:GITHUB_OUTPUT -Value "TestResultMD=$($sb.ToString())"
    Write-Host "TestResultMD=$($sb.ToString())"

    if ($project -eq ".") {
        Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($sb.ToString())`n"
    }
    else {
        Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$project - ($sb.ToString())`n"
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Deliver action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
