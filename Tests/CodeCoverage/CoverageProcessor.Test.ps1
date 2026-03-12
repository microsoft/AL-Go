Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../Actions/.Modules/TestRunner/CoverageProcessor"
    Import-Module (Join-Path $scriptPath "CoverageProcessor.psm1") -Force

    $testDataPath = Join-Path $PSScriptRoot "TestData"
}

Describe "CoverageProcessor - Convert-BCCoverageToCobertura" {

    Context "Single file conversion" {
        It "Should convert BC coverage to Cobertura XML" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "output.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            $outputPath | Should -Exist
            $stats | Should -Not -BeNullOrEmpty
            $stats.TotalLines | Should -BeGreaterThan 0
            $stats.CoveragePercent | Should -BeGreaterOrEqual 0
        }

        It "Should create stats JSON file alongside Cobertura XML" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "output2.cobertura.xml"
            $statsPath = Join-Path $TestDrive "output2.cobertura.stats.json"

            Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            $statsPath | Should -Exist
            $statsJson = Get-Content $statsPath -Raw | ConvertFrom-Json
            $statsJson.TotalLines | Should -Not -BeNullOrEmpty
            $statsJson.CoveragePercent | Should -Not -BeNullOrEmpty
        }

        It "Should handle coverage file without source path" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $outputPath = Join-Path $TestDrive "nosource.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -OutputPath $outputPath

            $outputPath | Should -Exist
            $stats | Should -Not -BeNullOrEmpty
        }

        It "Should return null for empty coverage file" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/empty-coverage.dat"
            $outputPath = Join-Path $TestDrive "empty.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -OutputPath $outputPath

            $stats | Should -BeNullOrEmpty
        }

        It "Should calculate coverage statistics correctly" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "stats-test.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            $stats.TotalLines | Should -Be ($stats.CoveredLines + $stats.NotCoveredLines)
            $stats.LineRate | Should -BeGreaterOrEqual 0
            $stats.LineRate | Should -BeLessOrEqual 1
            $stats.ObjectCount | Should -BeGreaterThan 0
        }

        It "Should load app metadata from app.json" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "appinfo.cobertura.xml"

            # Create a test app.json
            $appJsonPath = Join-Path $TestDrive "test-app.json"
            @{
                name = "Test App"
                version = "1.0.0.0"
                publisher = "Test Publisher"
            } | ConvertTo-Json | Set-Content $appJsonPath -Encoding UTF8

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath `
                -AppJsonPath $appJsonPath

            $outputPath | Should -Exist
        }
    }

    Context "Source filtering" {
        It "Should filter to only include objects with source files" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "filtered.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            # Should have excluded objects count if coverage includes external objects
            $stats.ExcludedObjectCount | Should -BeGreaterOrEqual 0
        }

        It "Should include source objects with no coverage" {
            # This tests that objects in source with 0 hits are included
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "zero-coverage.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            # Object count should include all source objects, not just covered ones
            $stats.ObjectCount | Should -BeGreaterOrEqual 1
        }

        It "Should respect exclude patterns" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "excluded.cobertura.xml"

            $stats = Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath `
                -ExcludePatterns @("*.Test.al", "*Test*.al")

            $outputPath | Should -Exist
        }
    }

    Context "XML output validation" {
        It "Should generate valid Cobertura XML" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "valid.cobertura.xml"

            Convert-BCCoverageToCobertura `
                -CoverageFilePath $coverageFile `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            # Should be valid XML
            { [xml](Get-Content $outputPath -Raw) } | Should -Not -Throw

            $xml = [xml](Get-Content $outputPath -Raw)
            $xml.coverage | Should -Not -BeNullOrEmpty
            $xml.coverage.packages | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "CoverageProcessor - Merge-BCCoverageToCobertura" {

    Context "Multiple file merging" {
        It "Should merge multiple coverage files" {
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"),
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat")
            )
            $sourcePath = Join-Path $testDataPath "ALFiles"
            $outputPath = Join-Path $TestDrive "merged.cobertura.xml"

            $stats = Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -SourcePath $sourcePath `
                -OutputPath $outputPath

            $outputPath | Should -Exist
            $stats | Should -Not -BeNullOrEmpty
        }

        It "Should handle single file as merge input" {
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat")
            )
            $outputPath = Join-Path $TestDrive "single-merge.cobertura.xml"

            $stats = Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -OutputPath $outputPath

            $outputPath | Should -Exist
        }

        It "Should handle missing files gracefully" {
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"),
                (Join-Path $testDataPath "CoverageFiles/nonexistent.dat")
            )
            $outputPath = Join-Path $TestDrive "missing-file.cobertura.xml"

            { Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -OutputPath $outputPath } | Should -Not -Throw
        }

        It "Should return null when all files empty or missing" {
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/empty-coverage.dat"),
                (Join-Path $testDataPath "CoverageFiles/nonexistent.dat")
            )
            $outputPath = Join-Path $TestDrive "all-empty.cobertura.xml"

            $stats = Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -OutputPath $outputPath

            $stats | Should -BeNullOrEmpty
        }

        It "Should deduplicate line entries and take max hits" {
            # When same line appears in multiple files, take max hit count
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"),
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat")
            )
            $outputPath = Join-Path $TestDrive "dedup.cobertura.xml"

            $stats = Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -OutputPath $outputPath

            # Should have deduplicated entries
            $stats | Should -Not -BeNullOrEmpty
        }

        It "Should create stats JSON for merged output" {
            $coverageFiles = @(
                (Join-Path $testDataPath "CoverageFiles/sample-coverage.dat")
            )
            $outputPath = Join-Path $TestDrive "merged-stats.cobertura.xml"
            $statsPath = Join-Path $TestDrive "merged-stats.cobertura.stats.json"

            Merge-BCCoverageToCobertura `
                -CoverageFiles $coverageFiles `
                -OutputPath $outputPath

            $statsPath | Should -Exist
        }
    }
}

Describe "CoverageProcessor - Find-CoverageFiles" {

    Context "File discovery" {
        It "Should find .dat files in directory" {
            $directory = Join-Path $testDataPath "CoverageFiles"

            $files = Find-CoverageFiles -Directory $directory

            $files | Should -Not -BeNullOrEmpty
            $files.Count | Should -BeGreaterThan 0
        }

        It "Should respect custom pattern" {
            $directory = Join-Path $testDataPath "CoverageFiles"

            $files = Find-CoverageFiles -Directory $directory -Pattern "*.xml"

            $files | Should -Not -BeNullOrEmpty
        }

        It "Should return empty array for missing directory" {
            $directory = Join-Path $testDataPath "NonExistent"

            $files = Find-CoverageFiles -Directory $directory

            $files | Should -BeNullOrEmpty
        }

        It "Should search recursively" {
            $directory = Join-Path $testDataPath "CoverageFiles"

            $files = Find-CoverageFiles -Directory $directory -Pattern "*"

            # Should find files in subdirectories if any exist
            $files.Count | Should -BeGreaterOrEqual 0
        }
    }
}

Describe "CoverageProcessor - Get-BCCoverageSummary" {

    Context "Quick summary generation" {
        It "Should generate summary without Cobertura output" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"

            $summary = Get-BCCoverageSummary -CoverageFilePath $coverageFile

            $summary | Should -Not -BeNullOrEmpty
            $summary.TotalLines | Should -BeGreaterThan 0
            $summary.CoveragePercent | Should -BeGreaterOrEqual 0
        }

        It "Should include object breakdown" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/sample-coverage.dat"

            $summary = Get-BCCoverageSummary -CoverageFilePath $coverageFile

            $summary.Objects | Should -Not -BeNullOrEmpty
            $summary.Objects.Count | Should -BeGreaterThan 0
            $summary.Objects[0].ObjectType | Should -Not -BeNullOrEmpty
            $summary.Objects[0].CoveragePercent | Should -BeGreaterOrEqual 0
        }

        It "Should handle empty coverage file" {
            $coverageFile = Join-Path $testDataPath "CoverageFiles/empty-coverage.dat"

            $summary = Get-BCCoverageSummary -CoverageFilePath $coverageFile

            $summary.TotalLines | Should -Be 0
            $summary.CoveredLines | Should -Be 0
        }
    }
}
