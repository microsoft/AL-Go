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

    AfterAll {
        Remove-Item -Path $bcptFilename -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $bcptBaseLine1 -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $bcptBaseLine2 -Force -ErrorAction SilentlyContinue
    }
}
