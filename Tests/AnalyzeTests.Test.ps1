Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

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
    1..$noOfSuites | ForEach-Object {
        $suiteName = "SUITE$_"
        1..$noOfCodeunits | ForEach-Object {
            $codeunitID = $_
            $codeunitName = "Codeunit$_"
            1..$noOfOperations | ForEach-Object {
                $operationNo = $_
                $operationName = "Operation$operationNo"
                1..$noOfMeasurements | ForEach-Object {
                    $no = $_
                    $bcpt += @(@{
                        "id" = [GUID]::NewGuid().ToString()
                        "bcptCode" = $suiteName
                        "codeunitID" = $codeunitID
                        "codeunitName" = $codeunitName
                        "operation" = $operationName
                        "durationMin" = $codeunitNo*100+$operationNo*10+$no+$durationOffset
                        "numberOfSQLStmts" = $operationNo+$numberOfSQLStmtsOffset
                    })
                }
            }
        }
    }
    $filename = Join-Path $ENV:TEMP "$([GUID]::NewGuid().ToString()).json"
    $bcpt | ConvertTo-Json -Depth 100 | Set-Content -Path $filename -Encoding UTF8
    return $filename
}

$bcptFilename = GetBcptTestResultFile -noOfSuites 1 -noOfCodeunits 2 -noOfOperations 3 -noOfMeasurements 4
$bcptBaseLine = GetBcptTestResultFile -noOfSuites 1 -noOfCodeunits 4 -noOfOperations 6 -noOfMeasurements 4 -durationOffset -1 -numberOfSQLStmtsOffset -1

Describe "AnalyzeTests Action Tests" {
    BeforeAll {
        $actionName = "AnalyzeTests"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    It 'Test ReadBcptFile' {
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $bcpt = ReadBcptFile -path $bcptFilename
        $bcpt.Count | should -Be 1
        $bcpt."SUITE1".Count | should -Be 2
        $bcpt."SUITE1"."1".operations.Count | should -Be 3
        $bcpt."SUITE1"."1".operations."operation2".measurements.Count | should -Be 4
    }

    It 'Test GetBcptSummaryMD (no baseline)' {
        . (Join-Path $scriptRoot 'TestResultAnalyzer.ps1')
        $md = GetBcptSummaryMD -path $bcptFilename
        $md | should -Match 'No baseline provided'
        [regex]::Matches($md, '\|SUITE1\|').Count | should -Be 1
        [regex]::Matches($md, '\|Codeunit.\|').Count | should -Be 2
        [regex]::Matches($md, '\|Operation.\|').Count | should -Be 6
        [regex]::Matches($md, '\|').Count | should -Be (7*8)
        
#         -Contain 'No baseline provided'
#        $md | should -Contain '|SUITE1|'

#        $md.Replace('\n',"`n") | Set-Content -Path "C:\temp\bcpt.md" -Encoding UTF8

    }

}
