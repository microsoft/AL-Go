function Test-NumberOfRuns {
    Param(
        [string] $workflowName,
        [int] $expectedNumberOfRuns
    )

    if ($workflowName) {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs ($workflowName):"
        $runs = @(gh run list --limit 1000 --workflow $workflowName --repo $repository | Where-Object { $_ -notlike "*`tworkflow_run`t*" })
    }
    else {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs:"
        $runs = @(gh run list --limit 1000 --repo $repository | Where-Object { $_ -notlike "*`tworkflow_run`t*" })
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
        [hashtable] $expectedArtifacts = @{},
        [string] $expectedNumberOfTests = 0,
        [string] $repoVersion = "",
        [string] $appVersion = ""
    )

    Write-Host -ForegroundColor Yellow "`nTest Artifacts from run $runid"
    Start-Sleep -Seconds 30
    Write-Host "Download build artifacts to $folder"
    invoke-gh run download $runid --dir $folder

    $expectedArtifacts.Keys | ForEach-Object {
        $expected = $expectedArtifacts."$_"
        $actual = @(Get-ChildItem -Path "$folder\*-$($_)-$repoVersion*\*$appVersion*.app").Count
        if ($actual -ne $expected) {
            throw "Expected number of $_ was $expected. Actual number of $_ is $actual"
        }
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

function Replace-StringInFiles {
    Param(
        [string] $path,
        [string] $include = "*",
        [string] $search,
        [string] $replace
    )

    Get-ChildItem -Path $path -Recurse -Include $include -File | ForEach-Object {
        $content = Get-Content $_.FullName -Encoding utf8
        $content = $content -replace $search, $replace
        Set-Content -Path $_.FullName -Value $content -Encoding utf8
    }
}


