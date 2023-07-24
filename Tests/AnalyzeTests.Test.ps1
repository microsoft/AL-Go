Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

function GetBcptTestResultFile {
    Param(
        [int] $noOfSuites = 1,
        [int] $noOfCodeunits = 100,
        [int] $noOfOperations = 100,
        [int] $noOfMeasurements = 100
    )

    $bcpt = @()
    1..$noOfSuites | ForEach-Object {
        $suiteName = "SUITE$_"
        1..$noOfCodeunits | ForEach-Object {
            $codeunitID = $_
            $codeunitName = "Codeunit$_"
            1..$noOfOperations | ForEach-Object {
                $operationName = "Operation$_"
                1..$noOfMeasurements | ForEach-Object {
                    $no = $_
                    $bcpt += @(@{
                        "id" = [GUID]::NewGuid().ToString()
                        "bcptCode" = $suiteName
                        "codeunitID" = $codeunitID
                        "codeunitName" = $codeunitName
                        "operation" = $operationName
                        "durationMin" = 1000*$codeunitID+$no
                        "numberOfSQLStmts" = $codeunitID+$no
                    })
                }
            }
        }
    }
    $bcpt | ConvertTo-Json -Depth 100 | set-content -path c:\temp\bcpt.json -encoding UTF8
}

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
        Write-Host $test
    }
}
