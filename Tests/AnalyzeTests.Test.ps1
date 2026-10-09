Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "AnalyzeTests Action Tests" {
    BeforeAll {
        function GetBcptTestResultFile {
            Param(
                [int] $noOfSuites = 1,
                [int] $noOfCodeunits = 1,
                [int] $noOfOperations = 1,
                [int] $noOfMeasurements = 1,
                [int] $durationOffset = 0,
                [int] $numberOfSQLStmtsOffset = 0
            )

            $bcpt = @()
            for($suiteNo = 1; $suiteNo -le $noOfSuites; $suiteNo++) {
                $suiteName = "SUITE$suiteNo"
                for($codeUnitID = 1; $codeunitID -le $noOfCodeunits; $codeunitID++) {
                    $codeunitName = "Codeunit$codeunitID"
                    for($operationNo = 1; $operationNo -le $noOfOperations; $operationNo++) {
                        $operationName = "Operation$operationNo"
                        for($no = 1; $no -le $noOfMeasurements; $no++) {
                            $bcpt += @(@{
                                "id" = [GUID]::NewGuid().ToString()
                                "bcptCode" = $suiteName
                                "codeunitID" = $codeunitID
                                "codeunitName" = $codeunitName
                                "operation" = $operationName
                                "durationMin" = $operationNo*10+$no+$durationOffset
                                "numberOfSQLStmts" = $operationNo+$numberOfSQLStmtsOffset
                            })
                        }
                    }
                }
            }
            $filename = Join-Path ([System.IO.Path]::GetTempPath()) "$([GUID]::NewGuid().ToString()).json"
            $bcpt | ConvertTo-Json -Depth 100 | Set-Content -Path $filename -Encoding UTF8
            return $filename
        }

        $actionName = "AnalyzeTests"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'bcptFilename', Justification = 'False positive.')]
        $bcptFilename = GetBcptTestResultFile -noOfSuites 1 -noOfCodeunits 2 -noOfOperations 5 -noOfMeasurements 4
        # BaseLine1 has overall highter duration and more SQL statements than bcptFilename (+ one more opearion)
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'bcptBaseLine1', Justification = 'False positive.')]
        $bcptBaseLine1 = GetBcptTestResultFile -noOfSuites 1 -noOfCodeunits 4 -noOfOperations 6 -noOfMeasurements 4 -durationOffset 5 -numberOfSQLStmtsOffset 1
        # BaseLine2 has overall lower duration and less SQL statements than bcptFilename (+ one less opearion)
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'bcptBaseLine2', Justification = 'False positive.')]
        $bcptBaseLine2 = GetBcptTestResultFile -noOfSuites 1 -noOfCodeunits 2 -noOfOperations 4 -noOfMeasurements 4 -durationOffset -2 -numberOfSQLStmtsOffset 0
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'thresholdsFile', Justification = 'False positive.')]
        $thresholdsFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([GUID]::NewGuid().ToString()).json"
        @{ "NumberOfSqlStmtsThresholdWarning" = 1; "NumberOfSqlStmtsThresholdError" = 2 } | ConvertTo-Json | Set-Content -Path $thresholdsFile -Encoding UTF8
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Test ReadBcptFile' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $bcpt = ReadBcptFile -bcptTestResultsFile $bcptFilename
        $bcpt.Count | should -Be 1
        $bcpt."SUITE1".Count | should -Be 2
        $bcpt."SUITE1"."1".operations.Count | should -Be 5
        $bcpt."SUITE1"."1".operations."operation2".measurements.Count | should -Be 4
    }

    It 'Test ReadBcptFile returns null when file does not exist' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $bcpt = ReadBcptFile -bcptTestResultsFile 'non-existent-file.json'
        $bcpt | Should -Be $null
    }

    It 'Test GetBcptSummaryMD returns empty string when file does not exist' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $md = GetBcptSummaryMD -bcptTestResultsFile 'non-existent-file.json'
        $md | Should -Be ''
    }

    It 'Test GetBcptSummaryMD returns warning message when file exists but contains no entries' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $emptyResultsFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([GUID]::NewGuid().ToString()).json"
        $script:warningCount = 0
        Mock OutputWarning { Param([string] $message) Write-Host "WARNING: $message"; $script:warningCount++ }
        try {
            Set-Content -Path $emptyResultsFile -Value '[]' -Encoding UTF8
            $md = GetBcptSummaryMD -bcptTestResultsFile $emptyResultsFile
            $md | Should -Not -BeNullOrEmpty
            $md | Should -Match 'No BCPT results were recorded'
            $script:warningCount | Should -Be 1
        }
        finally {
            Remove-Item -Path $emptyResultsFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Test GetBcptSummaryMD (no baseline)' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $md = GetBcptSummaryMD -bcptTestResultsFile $bcptFilename
        Write-Host $md.Replace('\n',"`n")
        $md | should -Match 'No baseline provided'
        $columns = 6
        $rows = 12
        [regex]::Matches($md, '\|SUITE1\|').Count | should -Be 1
        [regex]::Matches($md, '\|Codeunit.\|').Count | should -Be 2
        [regex]::Matches($md, '\|Operation.\|').Count | should -Be 10
        [regex]::Matches($md, '\|').Count | should -Be (($columns+1)*$rows)
    }

    It 'Test GetBcptSummaryMD (with worse baseline)' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $md = GetBcptSummaryMD -bcptTestResultsFile $bcptFilename -baselinePath $bcptBaseLine1 -bcptThresholds @{"durationWarning"=10;"durationError"=25;"numberOfSqlStmtsWarning"=5;"numberOfSqlStmtsError"=10}
        Write-Host $md.Replace('\n',"`n")
        $md | should -Not -Match 'No baseline provided'
        $columns = 13
        $rows = 12
        [regex]::Matches($md, '\|SUITE1\|').Count | should -Be 1
        [regex]::Matches($md, '\|Codeunit.\|').Count | should -Be 2
        [regex]::Matches($md, '\|Operation.\|').Count | should -Be 10
        [regex]::Matches($md, "\|$statusOK\|").Count | should -Be 10
        [regex]::Matches($md, "\|$statusWarning\|").Count | should -Be 0
        [regex]::Matches($md, "\|$statusError\|").Count | should -Be 0
        [regex]::Matches($md, '\|').Count | should -Be (($columns+1)*$rows)
    }

    It 'Test GetBcptSummaryMD (with better baseline)' {
        . (Join-Path $scriptRoot '../AL-Go-Helper.ps1')
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')

        $script:errorCount = 0
        Mock OutputError { Param([string] $message) Write-Host "ERROR: $message"; $script:errorCount++ }
        $script:warningCount = 0
        Mock OutputWarning { Param([string] $message) Write-Host "WARNING: $message"; $script:warningCount++ }

        $md = GetBcptSummaryMD -bcptTestResultsFile $bcptFilename -baselinePath $bcptBaseLine2 -thresholdsPath $thresholdsFile -bcptThresholds @{"durationWarning"=5;"durationError"=10;"numberOfSqlStmtsWarning"=5;"numberOfSqlStmtsError"=10}
        Write-Host $md.Replace('\n',"`n")
        $md | should -Not -Match 'No baseline provided'
        $columns = 13
        $rows = 12
        [regex]::Matches($md, '\|SUITE1\|').Count | should -Be 1
        [regex]::Matches($md, '\|Codeunit.\|').Count | should -Be 2
        [regex]::Matches($md, '\|Operation.\|').Count | should -Be 10
        [regex]::Matches($md, '\|N\/A\|').Count | should -Be 4
        [regex]::Matches($md, "\|$statusOK\|").Count | should -Be 0
        [regex]::Matches($md, "\|$statusWarning\|").Count | should -Be 4
        [regex]::Matches($md, "\|$statusError\|").Count | should -Be 4
        [regex]::Matches($md, '\|').Count | should -Be (($columns+1)*$rows)
        $script:errorCount | Should -be 2
        $script:warningCount | Should -be 0
    }

    It 'Test GetPageScriptingTestResultSummaryMD returns a hashtable' {
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $output = GetPageScriptingTestResultSummaryMD -testResultsFile (Join-Path $PSScriptRoot 'TestArtifacts/PageScriptingTestResults.xml') -project 'TestProject'
        $output | Should -BeOfType 'hashtable'
    }

    It 'Test page scripting summary under strict mode with <passed> passed, <failed> failed and <skipped> skipped tests' -TestCases @(
        @{ passed = 9; failed = 2; skipped = 0 }
        @{ passed = 1; failed = 1; skipped = 1 }
        @{ passed = 2; failed = 0; skipped = 0 }
        @{ passed = 0; failed = 2; skipped = 0 }
    ) {
        Param($passed, $failed, $skipped)

        Set-StrictMode -Version 2.0
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        Mock Trace-Information {}
        $testcases = @(
            for ($i = 1; $i -le $passed; $i++) {
                "<testcase name='Passed$i.yml' time='1' />"
            }
            for ($i = 1; $i -le $failed; $i++) {
                "<testcase name='Failed$i.yml' time='1'><failure message='Replay error $i'><![CDATA[Stack trace $i]]></failure></testcase>"
            }
            for ($i = 1; $i -le $skipped; $i++) {
                "<testcase name='Skipped$i.yml' time='1'><skipped /></testcase>"
            }
        ) -join "`n"
        $totalTests = $passed + $failed + $skipped
        $testResultsFile = Join-Path $TestDrive 'PageScriptingTestResults.xml'
        @"
<testsuites tests="$totalTests" failures="$failed" skipped="$skipped" time="$totalTests">
  <testsuite name="TestProject" tests="$totalTests" failures="$failed" skipped="$skipped" time="$totalTests">
    $testcases
  </testsuite>
</testsuites>
"@ | Set-Content -Path $testResultsFile -Encoding UTF8

        $output = GetPageScriptingTestResultSummaryMD -testResultsFile $testResultsFile -project 'TestProject'
        $output.SummaryMD | Should -Match "\|TestProject\|$totalTests\|"
        if ($passed -gt 0) { $output.SummaryMD | Should -Match "\|$passed :heavy_check_mark:\|" }
        if ($failed -gt 0) { $output.SummaryMD | Should -Match "\|$failed :x:\|" }
        if ($skipped -gt 0) { $output.SummaryMD | Should -Match "\|$skipped :question:\|" }
        $output.FailuresMD | Should -Not -Match 'Passed\d+\.yml|Skipped\d+\.yml'
        for ($i = 1; $i -le $failed; $i++) {
            $output.FailuresMD | Should -Match "Failed$i\.yml, Failure"
            $output.FailuresMD | Should -Match "Replay error $i"
            $output.FailuresMD | Should -Match "Stack trace $i"
        }
        if ($failed -eq 0) {
            $output.FailuresMD | Should -Be '<i>No test failures</i>'
        }
        else {
            $output.FailuresSummaryMD | Should -Be "<i>$failed failing tests, download test results to see details</i>"
        }
    }

    AfterAll {
        Remove-Item -Path $bcptFilename -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $bcptBaseLine1 -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $bcptBaseLine2 -Force -ErrorAction SilentlyContinue
    }
}
