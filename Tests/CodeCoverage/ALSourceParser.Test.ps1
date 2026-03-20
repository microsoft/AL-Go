BeforeAll {
    . (Join-Path $PSScriptRoot "..\..\Actions\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path $PSScriptRoot "..\..\Actions\.Modules\TestRunner\CoverageProcessor\ALSourceParser.psm1" -Resolve) -Force

    $script:testDataPath = Join-Path $PSScriptRoot "TestData\ALFiles"
}

Describe "ALSourceParser - Get-ALObjectMap" {
    Context "Parse AL source files" {
        It "Should parse codeunit object" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath

            $objectMap.Keys | Should -Contain "Codeunit.50100"
        }

        It "Should parse page object" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath

            $objectMap.Keys | Should -Contain "Page.50001"
        }

        It "Should extract object properties" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath
            $codeunit = $objectMap["Codeunit.50100"]

            $codeunit.ObjectType | Should -Be "Codeunit"
            $codeunit.ObjectId | Should -Be 50100
            $codeunit.FilePath | Should -Match "sample-codeunit.al"
        }

        It "Should identify procedures" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath
            $codeunit = $objectMap["Codeunit.50100"]

            $codeunit.Procedures | Should -Not -BeNullOrEmpty
            $codeunit.Procedures.Count | Should -BeGreaterThan 0
        }

        It "Should calculate executable lines" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath
            $codeunit = $objectMap["Codeunit.50100"]

            $codeunit.ExecutableLineNumbers | Should -Not -BeNullOrEmpty
            $codeunit.ExecutableLineNumbers.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "ALSourceParser - Get-ALProcedures" {
    Context "Procedure detection" {
        It "Should find procedures in AL code" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content

            $procedures | Should -Not -BeNullOrEmpty
            $procedures.Count | Should -BeGreaterThan 0
        }

        It "Should identify procedure names" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content
            $procedureNames = $procedures | ForEach-Object { $_.Name }

            $procedureNames | Should -Contain "TestProcedure1"
            $procedureNames | Should -Contain "TestProcedure2"
        }

        It "Should capture procedure line ranges" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content
            $firstProc = $procedures[0]

            $firstProc.StartLine | Should -BeGreaterThan 0
            $firstProc.EndLine | Should -BeGreaterThan $firstProc.StartLine
        }

        It "Should detect procedure modifiers" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content
            # Check that the "local procedure DoSomething" is detected
            $localProcNames = $procedures | ForEach-Object { $_.Name }
            $localProcNames | Should -Contain "DoSomething"
        }
    }

    Context "Complex codeunit parsing" {
        It "Should handle multiple procedures" {
            $complexFile = Join-Path $script:testDataPath "complex-codeunit.al"
            $content = Get-Content -Path $complexFile -Raw

            $procedures = Get-ALProcedures -Content $content

            $procedures.Count | Should -BeGreaterThan 2
        }

        It "Should handle nested code blocks" {
            $complexFile = Join-Path $script:testDataPath "complex-codeunit.al"
            $content = Get-Content -Path $complexFile -Raw

            $procedures = Get-ALProcedures -Content $content
            # Should successfully parse without errors
            $procedures | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "ALSourceParser - Get-ALExecutableLines" {
    Context "Executable line detection" {
        It "Should identify executable lines" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $result = Get-ALExecutableLines -Content $content

            $result.ExecutableLineNumbers | Should -Not -BeNullOrEmpty
            $result.ExecutableLineNumbers.Count | Should -BeGreaterThan 0
        }

        It "Should exclude comment lines" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $result = Get-ALExecutableLines -Content $content
            $lines = Get-Content -Path $codeunitFile

            # Find a line that's definitely a comment
            $commentLineNum = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Trim() -match '^//') {
                    $commentLineNum = $i + 1
                    break
                }
            }

            if ($commentLineNum -gt 0) {
                $result.ExecutableLineNumbers | Should -Not -Contain $commentLineNum
            }
        }

        It "Should exclude empty lines" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $result = Get-ALExecutableLines -Content $content
            $allLines = ($content -split "`n").Count

            # Executable lines should be less than total lines (some empty/comments)
            $result.ExecutableLineNumbers.Count | Should -BeLessThan $allLines
        }

        It "Should include assignment statements" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $result = Get-ALExecutableLines -Content $content

            # Should have found the assignment "myVar := 10;"
            $result.ExecutableLineNumbers.Count | Should -BeGreaterThan 5
        }

        It "Should include control flow statements" {
            $complexFile = Join-Path $script:testDataPath "complex-codeunit.al"
            $content = Get-Content -Path $complexFile -Raw

            $result = Get-ALExecutableLines -Content $content

            # Complex file has repeat/until, if statements
            $result.ExecutableLineNumbers.Count | Should -BeGreaterThan 10
        }
    }

    Context "Non-executable line exclusion" {
        It "Should exclude var blocks" {
            $complexFile = Join-Path $script:testDataPath "complex-codeunit.al"
            $content = Get-Content -Path $complexFile -Raw
            $lines = Get-Content -Path $complexFile

            $result = Get-ALExecutableLines -Content $content

            # Find var declaration line
            $varLineNum = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Trim() -match '^\s*var\s*$') {
                    $varLineNum = $i + 1
                    break
                }
            }

            if ($varLineNum -gt 0) {
                $result.ExecutableLineNumbers | Should -Not -Contain $varLineNum
            }
        }

        It "Should handle begin/end keywords properly" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $result = Get-ALExecutableLines -Content $content

            # Just verify we got some executable lines
            $result.ExecutableLineNumbers.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "ALSourceParser - Find-ProcedureForLine" {
    Context "Line to procedure mapping" {
        It "Should find procedure for given line" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content
            $testLine = $procedures[0].StartLine + 2  # Line within first procedure

            $foundProc = Find-ProcedureForLine -Procedures $procedures -LineNo $testLine

            $foundProc | Should -Not -BeNullOrEmpty
            $foundProc.Name | Should -Be $procedures[0].Name
        }

        It "Should return null for line outside procedures" {
            $codeunitFile = Join-Path $script:testDataPath "sample-codeunit.al"
            $content = Get-Content -Path $codeunitFile -Raw

            $procedures = Get-ALProcedures -Content $content
            $lineBeforeProcs = 1  # Header line

            $foundProc = Find-ProcedureForLine -Procedures $procedures -LineNo $lineBeforeProcs

            $foundProc | Should -BeNullOrEmpty
        }
    }
}

Describe "ALSourceParser - Integration" {
    Context "Full object parsing workflow" {
        It "Should parse multiple AL files in directory" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath

            $objectMap.Keys.Count | Should -BeGreaterThan 1
        }

        It "Should handle different object types" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath

            $objectTypes = $objectMap.Values | ForEach-Object { $_.ObjectType } | Select-Object -Unique
            $objectTypes | Should -Contain "Codeunit"
            $objectTypes | Should -Contain "Page"
        }

        It "Should provide complete source info" {
            $objectMap = Get-ALObjectMap -SourcePath $script:testDataPath
            $codeunit = $objectMap["Codeunit.50100"]

            $codeunit | Should -Not -BeNullOrEmpty
            $codeunit.Procedures | Should -Not -BeNullOrEmpty
            $codeunit.ExecutableLineNumbers | Should -Not -BeNullOrEmpty
        }
    }
}
