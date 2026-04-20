BeforeAll {
    . (Join-Path $PSScriptRoot "..\..\Actions\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path $PSScriptRoot "..\..\Actions\.Modules\TestRunner\CoverageProcessor\BCCoverageParser.psm1" -Resolve) -Force

    $script:testDataPath = Join-Path $PSScriptRoot "TestData\CoverageFiles"
}

Describe "BCCoverageParser - CSV Format" {
    Context "Valid CSV coverage file" {
        It "Should parse CSV coverage file successfully" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $csvFile

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should parse all coverage lines from CSV" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $csvFile

            # Should have 11 lines (based on sample data)
            $result.Count | Should -Be 11
        }

        It "Should correctly parse coverage status" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $csvFile

            $coveredLines = $result | Where-Object { $_.CoverageStatusName -eq 'Covered' }
            $notCoveredLines = $result | Where-Object { $_.CoverageStatusName -eq 'NotCovered' }

            # Count actual covered vs not covered from test data
            $coveredLines.Count | Should -Be 9
            $notCoveredLines.Count | Should -Be 2
        }

        It "Should correctly parse hit counts" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $csvFile

            $firstLine = $result[0]
            $firstLine.Hits | Should -Be 5

            $highHitLine = $result | Where-Object { $_.ObjectId -eq '50000' } | Select-Object -First 1
            $highHitLine.Hits | Should -Be 100
        }

        It "Should correctly parse object types" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $csvFile

            $codeunits = $result | Where-Object { $_.ObjectType -eq 'Codeunit' }
            $tables = $result | Where-Object { $_.ObjectType -eq 'Table' }
            $pages = $result | Where-Object { $_.ObjectType -eq 'Page' }

            $codeunits.Count | Should -Be 8
            $tables.Count | Should -Be 2
            $pages.Count | Should -Be 1
        }
    }

    Context "Empty and malformed files" {
        It "Should handle empty CSV file gracefully" {
            $emptyFile = Join-Path $script:testDataPath "empty-coverage.dat"
            $result = Read-BCCoverageCsvFile -Path $emptyFile

            # Empty file returns empty array, not null
            $result.Count | Should -Be 0
        }
    }
}

Describe "BCCoverageParser - XML Format" {
    Context "Valid XML coverage file" {
        It "Should parse XML coverage file successfully" {
            $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
            $result = Read-BCCoverageXmlFile -Path $xmlFile

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should parse all objects from XML" {
            $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
            $result = Read-BCCoverageXmlFile -Path $xmlFile

            # Should have 8 lines total from 2 codeunits
            $result.Count | Should -Be 8
        }

        It "Should correctly map object types from XML" {
            $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
            $result = Read-BCCoverageXmlFile -Path $xmlFile

            $allCodeunits = $result | Where-Object { $_.ObjectType -eq 'Codeunit' }
            $allCodeunits.Count | Should -Be 8
        }

        It "Should correctly parse hit counts from XML" {
            $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
            $result = Read-BCCoverageXmlFile -Path $xmlFile

            $hitCounts = $result | Select-Object -ExpandProperty Hits
            $hitCounts | Should -Contain 5
            $hitCounts | Should -Contain 10
            $hitCounts | Should -Contain 0
        }

        It "Should correctly identify covered vs not covered lines" {
            $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
            $result = Read-BCCoverageXmlFile -Path $xmlFile

            $covered = $result | Where-Object { $_.CoverageStatusName -eq 'Covered' }
            $notCovered = $result | Where-Object { $_.CoverageStatusName -eq 'NotCovered' }

            $covered.Count | Should -Be 6
            $notCovered.Count | Should -Be 2
        }
    }
}

Describe "BCCoverageParser - Auto Detection" {
    It "Should auto-detect CSV format" {
        $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
        $result = Read-BCCoverageFile -Path $csvFile

        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 11
    }

    It "Should auto-detect XML format" {
        $xmlFile = Join-Path $script:testDataPath "sample-coverage.xml"
        $result = Read-BCCoverageFile -Path $xmlFile

        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 8
    }
}

Describe "BCCoverageParser - Grouping and Statistics" {
    Context "Group-CoverageByObject" {
        It "Should group coverage by object" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $grouped = Group-CoverageByObject -CoverageEntries $rawData

            $grouped.Keys.Count | Should -BeGreaterThan 0
        }

        It "Should create correct object keys" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $grouped = Group-CoverageByObject -CoverageEntries $rawData

            $grouped.Keys | Should -Contain 'Codeunit.50100'
            $grouped.Keys | Should -Contain 'Codeunit.50101'
            $grouped.Keys | Should -Contain 'Table.50000'
        }

        It "Should group all lines for each object" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $grouped = Group-CoverageByObject -CoverageEntries $rawData

            $codeunit1 = $grouped['Codeunit.50100']
            $codeunit1.Lines.Count | Should -Be 5

            $codeunit2 = $grouped['Codeunit.50101']
            $codeunit2.Lines.Count | Should -Be 3
        }
    }

    Context "Get-CoverageStatistics" {
        It "Should calculate coverage percentage" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $stats = Get-CoverageStatistics -CoverageEntries $rawData

            $stats.CoveragePercent | Should -BeGreaterThan 0
            $stats.CoveragePercent | Should -BeLessOrEqual 100
        }

        It "Should count total and covered lines" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $stats = Get-CoverageStatistics -CoverageEntries $rawData

            $stats.TotalLines | Should -Be 11
            # 8 with status 0 (Covered) + 0 with status 2 (PartiallyCovered) = 8 covered
            # But let's check the actual data
            $covered = ($rawData | Where-Object { $_.IsCovered }).Count
            $stats.CoveredLines | Should -Be $covered
        }

        It "Should calculate line rate" {
            $csvFile = Join-Path $script:testDataPath "sample-coverage.dat"
            $rawData = Read-BCCoverageCsvFile -Path $csvFile
            $stats = Get-CoverageStatistics -CoverageEntries $rawData

            # Line rate should be between 0 and 1
            $stats.LineRate | Should -BeGreaterThan 0
            $stats.LineRate | Should -BeLessOrEqual 1
        }
    }
}

Describe "BCCoverageParser - PartiallyCovered status" {
    It "Should treat PartiallyCovered (status 2) as covered" {
        $tempFile = Join-Path $TestDrive "partial-coverage.dat"
        # Status 2 = PartiallyCovered, should be treated as IsCovered = $true
        @(
            "5,50100,10,0,5"     # Covered
            "5,50100,11,2,3"     # PartiallyCovered
            "5,50100,12,1,0"     # NotCovered
        ) | Set-Content -Path $tempFile -Encoding UTF8

        $result = Read-BCCoverageCsvFile -Path $tempFile

        $result.Count | Should -Be 3
        $covered = @($result | Where-Object { $_.IsCovered })
        $covered.Count | Should -Be 2
        ($result | Where-Object { $_.LineNo -eq 11 }).IsCovered | Should -BeTrue
    }
}

Describe "BCCoverageParser - Malformed input" {
    It "Should handle malformed CSV file gracefully" {
        $malformedFile = Join-Path $script:testDataPath "malformed-coverage.dat"

        $result = Read-BCCoverageCsvFile -Path $malformedFile

        # Should not throw; returns null or empty
        @($result).Count | Should -Be 0
    }

    It "Should handle empty CSV file gracefully" {
        $emptyFile = Join-Path $script:testDataPath "empty-coverage.dat"

        $result = Read-BCCoverageCsvFile -Path $emptyFile

        @($result).Count | Should -Be 0
    }
}

Describe "BCCoverageParser - Get-ObjectTypeId" {
    It "Should return correct ID for known type names" {
        Get-ObjectTypeId -ObjectTypeName "Codeunit" | Should -Be 5
        Get-ObjectTypeId -ObjectTypeName "Table" | Should -Be 3
        Get-ObjectTypeId -ObjectTypeName "Page" | Should -Be 8
        Get-ObjectTypeId -ObjectTypeName "Report" | Should -Be 14
    }

    It "Should return 0 for unknown type names" {
        Get-ObjectTypeId -ObjectTypeName "UnknownType" | Should -Be 0
    }

    It "Should be case-insensitive" {
        Get-ObjectTypeId -ObjectTypeName "CODEUNIT" | Should -Be 5
        Get-ObjectTypeId -ObjectTypeName "codeunit" | Should -Be 5
    }
}
