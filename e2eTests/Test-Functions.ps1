function GetNumberOfRuns {
    Param(
        [string] $repository,
        [string] $workflowName
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
    $runs.Count
}

function TestNumberOfRuns {
    Param(
        [string] $repository,
        [string] $workflowName,
        [int] $expectedNumberOfRuns
    )

    $count = GetNumberOfRuns -repository $repository -workflowName $workflowName
    if ($count -ne $expectedNumberOfRuns) {
        throw "Expected number of runs was $expectedNumberOfRuns. Actual number was $($count)"
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
    foreach($type in $expectedArtifacts.Keys) {
        $expected = $expectedArtifacts."$type"
        Write-Host "Type: $type, Expected: $expected"
        if ($type -eq 'thisbuild') {
            $fileNamePattern = "thisbuild-*-Apps?*$appVersion.*.*.app"
            Write-Host "FileNamePattern: $fileNamePattern"
            $actual = @(Get-ChildItem -Path $path -File -Recurse | Where-Object {
                $_.FullName.Substring($path.Length+1) -like $fileNamePattern
            }).Count
        }
        else {
            $fileNamePattern = "*-$type-$repoVersion.*.*?*$appVersion.*.*.app"
            Write-Host "FileNamePattern: $fileNamePattern"
            $actual = @(Get-ChildItem -Path $path -File -Recurse | Where-Object {
                $_.FullName.SubString($path.Length+1) -like $fileNamePattern
            }).Count
        }
        if ($actual -ne $expected) {
            Write-Host "::Error::Expected number of $type was $expected. Actual number of $type is $actual"
            $err = $true
        }
        else {
            Write-Host "Number of $type was $actual as expected"
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'json', Justification = 'False positive.')]
    $json = Get-Content $jsonFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    foreach($key in $properties.Keys) {
        $expected = $properties."$key"
        # Key can be 'idRanges[0].from' or other expressions
        $actual = Invoke-Expression "`$json.$key"
        if ($actual -ne $expected) {
            Write-Host "::Error::Property $key is $actual. Expected $expected"
            $err = $true
        }
    }
    if ($err) {
        throw "Testing properties in $jsonFile failed"
    }
}
