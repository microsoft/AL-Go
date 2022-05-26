function Test-NumberOfRuns {
    Param(
        [string] $workflowName,
        [int] $expectedNumberOfRuns
    )

    if ($workflowName) {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs ($workflowName):"
        $runs = @(gh run list --limit 1000 --workflow $workflowName --repo $repository)
    }
    else {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs:"
        $runs = @(gh run list --limit 1000 --repo $repository)
    }
    $runs | Out-Host
    if ($runs.Count -ne $expectedNumberOfRuns) {
        throw "Expected number of runs was $expectedNumberOfRuns. Actual number was $($runs.Count)"
    }
}

function Test-ArtifactsFromRun {
    Param(
        [string] $runid,
        [string] $folder,
        [string] $expectedNumberOfApps,
        [string] $expectedNumberOfTestApps,
        [string] $expectedNumberOfTests = 0,
        [string] $repoVersion = "",
        [string] $appVersion = ""
    )

    Write-Host -ForegroundColor Yellow "`nTest Artifacts from run $runid"
    Write-Host "Download build artifacts to $folder"
    gh run download $runid --dir $folder

    $actualNumberOfApps = @(Get-ChildItem -Path "$folder\*-Apps-$repoVersion*\*$appVersion*.app").Count
    if ($actualNumberOfApps -ne $expectedNumberOfApps) {
        throw "Expected number of apps was $expectedNumberOfApps. Actual number of apps is $actualNumberOfApps"
    }
    $actualNumberOfTestApps = @(Get-ChildItem -Path "$folder\*-TestApps-$repoVersion*\*$appVersion*.app").Count
    if ($actualNumberOfTestApps -ne $expectedNumberOfTestApps) {
        throw "Expected number of test apps was $expectedNumberOfTestApps. Actual number of test apps is $actualNumberOfTestApps"
    }
    if ($expectedNumberOfTests) {
        $actualNumberOfTests = 0
        $actualNumberOfErrors = 0
        $actualNumberOfFailures = 0
        Get-Item "$folder\*-TestResults*\TestResults.xml" | ForEach-Object {
            [xml]$testResults = Get-Content $_.FullName -encoding UTF8
            @($testresults.testsuites.testsuite) | ForEach-Object {
                $actualNumberOfTests += $_.tests
                $actualNumberOfErrors += $_.Errors
                $actualNumberOfFailures += $_.Failures
            }
        }

        if ($actualNumberOfTests -ne $expectedNumberOfTests) {
            throw "Expected number of tests was $expectedNumberOfTests. Actual number of tests is $actualNumberOfTests"
        }

        if ($actualNumberOfErrors -ne 0 -or $actualNumberOfFailures -ne 0) {
            throw "Test results indicate unexpected errors"
        }
    }
}

function Test-PropertiesInJsonFile {
    Param(
        [string] $jsonFile,
        [Hashtable] $properties
    )

    $json = Get-Content $jsonFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    $properties.Keys | ForEach-Object {
        $expected = $properties."$_"
        $actual = Invoke-Expression "`$json.$_"
        if ($actual -ne $expected) {
            Write-Host "$_ is $actual. Expected $expected"
        }
    }

}
