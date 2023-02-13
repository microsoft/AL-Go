function Test-NumberOfRuns {
    Param(
        [string] $repository,
        [string] $workflowName,
        [int] $expectedNumberOfRuns
    )

    $returnFields = "conclusion,displayTitle,workflowName,headBranch,event,databaseId"
    if ($workflowName) {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs ($workflowName):"
        $runs = gh run list --limit 1000 --workflow $workflowName --repo $repository --json $returnFields | ConvertFrom-Json | Where-Object { $_.event -ne "workflow_run" }
    }
    else {
        Write-Host -ForegroundColor Yellow "`nWorkflow runs:"
        $runs = gh run list --limit 1000 --repo $repository --json $returnFields | ConvertFrom-Json | Where-Object { $_.workflowName -ne "workflow_run" }
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
        [string] $appVersion = "",
        [switch] $addDelay
    )

    Write-Host -ForegroundColor Yellow "`nTest Artifacts from run $runid"
    Start-Sleep -Seconds 30
    Write-Host "Download build artifacts to $folder"
    invoke-gh run download $runid --dir $folder
    $err = $false

    if ($expectedNumberOfTests) {
        $actualNumberOfTests = 0
        $actualNumberOfErrors = 0
        $actualNumberOfFailures = 0
        Get-Item (Join-Path $folder "*-TestResults*/TestResults.xml") | ForEach-Object {
            [xml]$testResults = Get-Content $_.FullName -encoding UTF8
            @($testresults.testsuites.testsuite) | ForEach-Object {
                $actualNumberOfTests += $_.tests
                $actualNumberOfErrors += $_.Errors
                $actualNumberOfFailures += $_.Failures
            }
        }

        if ($actualNumberOfTests -ne $expectedNumberOfTests) {
            Write-Host "::Error::Expected number of tests was $expectedNumberOfTests. Actual number of tests is $actualNumberOfTests"
            $err = $true
        }
        if ($actualNumberOfErrors -ne 0 -or $actualNumberOfFailures -ne 0) {
            Write-Host "::Error::Test results indicate unexpected errors"
            $err = $true
        }
        if (!$err) {
            Write-Host "Number of tests was $actualNumberOfTests as expected and all tests passed"
        }
    }
    $path = Join-Path (Get-Location).Path $folder -Resolve
    $expectedArtifacts.Keys | ForEach-Object {
        $type = $_
        $expected = $expectedArtifacts."$type"
        Write-Host "Type: $type, Expected: $expected"
        if ($type -eq 'thisbuild') {
            $actual = @(Get-ChildItem -Path $path -File -Recurse | Where-Object { 
                $_.FullName.Substring($path.Length+1) -like "thisbuild-*-Apps?*$appVersion.*.*.app"
            }).Count
        }
        else {
            $actual = @(Get-ChildItem -Path $path -File -Recurse | Where-Object {
                $_.FullName.SubString($path.Length+1) -like "*-$type-$repoVersion.*.*?*$appVersion.*.*.app"
            }).Count
        }
        if ($actual -ne $expected) {
            Write-Host "::Error::Expected number of $_ was $expected. Actual number of $_ is $actual"
            $err = $true
        }
        else {
            Write-Host "Number of $_ was $actual as expected"
        }
    }
    if ($err) {
        throw "Testing artifacts from run failed"
    }
}

function Test-PropertiesInJsonFile {
    Param(
        [string] $jsonFile,
        [Hashtable] $properties
    )

    $err = $false
    $json = Get-Content $jsonFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    $properties.Keys | ForEach-Object {
        $expected = $properties."$_"
        $actual = Invoke-Expression "`$json.$_"
        if ($actual -ne $expected) {
            Write-Host "::Error::Property $_ is $actual. Expected $expected"
            $err = $true
        }
    }
    if ($err) {
        throw "Testing properties in $jsonFile failed"
    }
}
