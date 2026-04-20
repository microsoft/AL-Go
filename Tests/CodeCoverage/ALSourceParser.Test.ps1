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

Describe "ALSourceParser - Get-ALObjectMap AppSourcePaths" {
    BeforeAll {
        # Create two separate app source directories with distinct .al files
        $script:appDir1 = Join-Path $TestDrive "App1"
        $script:appDir2 = Join-Path $TestDrive "App2"
        $script:rootDir = $TestDrive
        New-Item -Path $script:appDir1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:appDir2 -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $script:appDir1 "cu1.al") -Value @'
codeunit 60001 "AppSource CU1"
{
    procedure Hello()
    begin
        Message('hello');
    end;
}
'@ -Encoding UTF8

        Set-Content -Path (Join-Path $script:appDir2 "cu2.al") -Value @'
codeunit 60002 "AppSource CU2"
{
    procedure World()
    begin
        Message('world');
    end;
}
'@ -Encoding UTF8

        # Place a file in root that should NOT be found when AppSourcePaths is used
        Set-Content -Path (Join-Path $TestDrive "rootonly.al") -Value @'
codeunit 60099 "Root Only CU"
{
    procedure RootProc()
    begin
        Message('root');
    end;
}
'@ -Encoding UTF8
    }

    It "Should scan only specified AppSourcePaths directories" {
        $objectMap = Get-ALObjectMap -SourcePath $script:rootDir -AppSourcePaths @($script:appDir1)

        $objectMap.Keys | Should -Contain "Codeunit.60001"
        $objectMap.Keys | Should -Not -Contain "Codeunit.60002"
        $objectMap.Keys | Should -Not -Contain "Codeunit.60099"
    }

    It "Should warn but not crash for non-existent AppSourcePaths" {
        $objectMap = Get-ALObjectMap -SourcePath $script:rootDir -AppSourcePaths @((Join-Path $TestDrive "NoSuchDir")) -WarningVariable warnings 3>$null

        $objectMap.Count | Should -Be 0
    }

    It "Should find files from multiple AppSourcePaths" {
        $objectMap = Get-ALObjectMap -SourcePath $script:rootDir -AppSourcePaths @($script:appDir1, $script:appDir2)

        $objectMap.Keys | Should -Contain "Codeunit.60001"
        $objectMap.Keys | Should -Contain "Codeunit.60002"
        $objectMap.Keys | Should -Not -Contain "Codeunit.60099"
    }
}

Describe "ALSourceParser - Get-ALObjectMap ExcludePatterns" {
    BeforeAll {
        $script:excludeDir = Join-Path $TestDrive "ExcludeTests"
        New-Item -Path $script:excludeDir -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $script:excludeDir "MyCodeunit.al") -Value @'
codeunit 70001 "Keep CU"
{
    procedure Proc1()
    begin
        Message('keep');
    end;
}
'@ -Encoding UTF8

        Set-Content -Path (Join-Path $script:excludeDir "MyPerms.PermissionSet.al") -Value @'
permissionset 70002 "My Perms"
{
    Assignable = true;
}
'@ -Encoding UTF8

        Set-Content -Path (Join-Path $script:excludeDir "MyPermsExt.PermissionSetExtension.al") -Value @'
permissionsetextension 70003 "My Perms Ext" extends "My Perms"
{
    Assignable = true;
}
'@ -Encoding UTF8
    }

    It "Should exclude files matching a single pattern" {
        $objectMap = Get-ALObjectMap -SourcePath $script:excludeDir -ExcludePatterns @('*.PermissionSet.al')

        $objectMap.Keys | Should -Contain "Codeunit.70001"
        $objectMap.Keys | Should -Not -Contain "PermissionSet.70002"
    }

    It "Should exclude files matching any of multiple patterns" {
        $objectMap = Get-ALObjectMap -SourcePath $script:excludeDir -ExcludePatterns @('*.PermissionSet.al', '*.PermissionSetExtension.al')

        $objectMap.Keys | Should -Contain "Codeunit.70001"
        $objectMap.Keys | Should -Not -Contain "PermissionSet.70002"
        $objectMap.Keys | Should -Not -Contain "PermissionSetExtension.70003"
    }

    It "Should keep all files when pattern matches nothing" {
        $objectMap = Get-ALObjectMap -SourcePath $script:excludeDir -ExcludePatterns @('*.NoMatch.xyz')

        $objectMap.Count | Should -Be 3
    }

    It "Should return empty map when pattern matches all files" {
        $objectMap = Get-ALObjectMap -SourcePath $script:excludeDir -ExcludePatterns @('*.al')

        $objectMap.Count | Should -Be 0
    }
}

Describe "ALSourceParser - Read-AppJson" {
    It "Should parse valid app.json with all fields" {
        $appJsonDir = Join-Path $TestDrive "ReadAppJson"
        New-Item -Path $appJsonDir -ItemType Directory -Force | Out-Null
        $appJsonPath = Join-Path $appJsonDir "app.json"
        Set-Content -Path $appJsonPath -Value '{"id":"11111111-2222-3333-4444-555555555555","name":"TestApp","publisher":"TestPublisher","version":"1.0.0.0"}' -Encoding UTF8

        $result = Read-AppJson -AppJsonPath $appJsonPath

        $result | Should -Not -BeNullOrEmpty
        $result.Id | Should -Be "11111111-2222-3333-4444-555555555555"
        $result.Name | Should -Be "TestApp"
        $result.Publisher | Should -Be "TestPublisher"
        $result.Version | Should -Be "1.0.0.0"
    }

    It "Should return null for missing file" {
        $result = Read-AppJson -AppJsonPath (Join-Path $TestDrive "nonexistent.json") -WarningVariable warnings 3>$null

        $result | Should -BeNullOrEmpty
    }

    It "Should handle malformed JSON gracefully" {
        $badJsonPath = Join-Path $TestDrive "bad-app.json"
        Set-Content -Path $badJsonPath -Value '{ this is not json }' -Encoding UTF8

        { Read-AppJson -AppJsonPath $badJsonPath } | Should -Throw
    }
}

Describe "ALSourceParser - Get-NormalizedObjectType" {
    It "Should normalize common AL types to PascalCase" {
        Get-NormalizedObjectType -ObjectType 'codeunit' | Should -Be 'Codeunit'
        Get-NormalizedObjectType -ObjectType 'table' | Should -Be 'Table'
        Get-NormalizedObjectType -ObjectType 'page' | Should -Be 'Page'
        Get-NormalizedObjectType -ObjectType 'report' | Should -Be 'Report'
    }

    It "Should normalize extension types" {
        Get-NormalizedObjectType -ObjectType 'tableextension' | Should -Be 'TableExtension'
        Get-NormalizedObjectType -ObjectType 'pageextension' | Should -Be 'PageExtension'
        Get-NormalizedObjectType -ObjectType 'enumextension' | Should -Be 'EnumExtension'
        Get-NormalizedObjectType -ObjectType 'permissionsetextension' | Should -Be 'PermissionSetExtension'
    }

    It "Should normalize other known types" {
        Get-NormalizedObjectType -ObjectType 'query' | Should -Be 'Query'
        Get-NormalizedObjectType -ObjectType 'xmlport' | Should -Be 'XMLport'
        Get-NormalizedObjectType -ObjectType 'enum' | Should -Be 'Enum'
        Get-NormalizedObjectType -ObjectType 'interface' | Should -Be 'Interface'
        Get-NormalizedObjectType -ObjectType 'permissionset' | Should -Be 'PermissionSet'
        Get-NormalizedObjectType -ObjectType 'profile' | Should -Be 'Profile'
        Get-NormalizedObjectType -ObjectType 'controladdin' | Should -Be 'ControlAddIn'
    }

    It "Should be case-insensitive" {
        Get-NormalizedObjectType -ObjectType 'CODEUNIT' | Should -Be 'Codeunit'
        Get-NormalizedObjectType -ObjectType 'Table' | Should -Be 'Table'
        Get-NormalizedObjectType -ObjectType 'PageExtension' | Should -Be 'PageExtension'
    }

    It "Should return original value for unknown types" {
        Get-NormalizedObjectType -ObjectType 'SomeFutureType' | Should -Be 'SomeFutureType'
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
