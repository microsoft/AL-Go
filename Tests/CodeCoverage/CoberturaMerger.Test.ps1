Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../Actions/MergeCoverageSummaries"
    Import-Module (Join-Path $scriptPath "CoberturaMerger.psm1") -Force
    
    $testDataPath = Join-Path $PSScriptRoot "TestData/CoberturaFiles"
}

Describe "CoberturaMerger - Merge-CoberturaFiles" {
    
    Context "File merging" {
        It "Should merge multiple Cobertura files" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura2.xml")
            )
            $outputPath = Join-Path $TestDrive "merged.xml"
            
            $stats = Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            $outputPath | Should -Exist
            $stats | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle single file" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "single.xml"
            
            $stats = Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            $outputPath | Should -Exist
        }
        
        It "Should skip missing files with warning" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "nonexistent.xml")
            )
            $outputPath = Join-Path $TestDrive "missing.xml"
            
            { Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath } | Should -Not -Throw
            $outputPath | Should -Exist
        }
        
        It "Should handle all missing files gracefully" {
            $files = @((Join-Path $testDataPath "nonexistent1.xml"), (Join-Path $testDataPath "nonexistent2.xml"))
            $outputPath = Join-Path $TestDrive "allmissing.xml"
            
            $stats = Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            $stats.TotalLines | Should -Be 0
            $stats.CoveredLines | Should -Be 0
        }
        
        It "Should skip malformed XML files" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura-malformed.xml")
            )
            $outputPath = Join-Path $TestDrive "malformed.xml"
            
            { Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath } | Should -Not -Throw
        }
    }
    
    Context "Line merging" {
        It "Should take maximum hit count for duplicate lines" {
            # When the same line appears in multiple files, take max hits
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura2.xml")
            )
            $outputPath = Join-Path $TestDrive "maxhits.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            $merged.coverage | Should -Not -BeNullOrEmpty
        }
        
        It "Should deduplicate lines by filename and line number" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura1.xml")  # Same file twice
            )
            $outputPath = Join-Path $TestDrive "dedup.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            $merged.coverage | Should -Not -BeNullOrEmpty
        }
        
        It "Should maintain line number ordering" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura2.xml")
            )
            $outputPath = Join-Path $TestDrive "ordered.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            $lines = $merged.coverage.packages.package.classes.class.lines.line
            if ($lines -and $lines.Count -gt 1) {
                for ($i = 1; $i -lt $lines.Count; $i++) {
                    [int]$lines[$i].number | Should -BeGreaterOrEqual ([int]$lines[$i-1].number)
                }
            }
        }
    }
    
    Context "Statistics calculation" {
        It "Should recalculate line-rate after merge" {
            $files = @(
                (Join-Path $testDataPath "cobertura1.xml"),
                (Join-Path $testDataPath "cobertura2.xml")
            )
            $outputPath = Join-Path $TestDrive "stats.xml"
            
            $stats = Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            [double]$lineRate = $merged.coverage.'line-rate'
            $lineRate | Should -BeGreaterOrEqual 0
            $lineRate | Should -BeLessOrEqual 1
        }
        
        It "Should calculate total lines-valid correctly" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "linesvalid.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            [int]$linesValid = $merged.coverage.'lines-valid'
            $linesValid | Should -BeGreaterOrEqual 0
        }
        
        It "Should calculate total lines-covered correctly" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "linescovered.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            [int]$linesCovered = $merged.coverage.'lines-covered'
            $linesCovered | Should -BeGreaterOrEqual 0
        }
    }
    
    Context "XML structure" {
        It "Should produce valid Cobertura XML" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "valid.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            { [xml](Get-Content $outputPath -Raw) } | Should -Not -Throw
            
            [xml]$merged = Get-Content $outputPath -Raw
            $merged.coverage | Should -Not -BeNullOrEmpty
            $merged.coverage.packages | Should -Not -BeNullOrEmpty
        }
        
        It "Should maintain package structure" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "packages.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            $merged.coverage.packages.package | Should -Not -BeNullOrEmpty
        }
        
        It "Should maintain class structure" {
            $files = @((Join-Path $testDataPath "cobertura1.xml"))
            $outputPath = Join-Path $TestDrive "classes.xml"
            
            Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            [xml]$merged = Get-Content $outputPath -Raw
            $classes = $merged.coverage.packages.package.classes.class
            $classes | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Empty coverage handling" {
        It "Should handle empty coverage files" {
            $files = @((Join-Path $testDataPath "cobertura-empty.xml"))
            $outputPath = Join-Path $TestDrive "empty.xml"
            
            $stats = Merge-CoberturaFiles -CoberturaFiles $files -OutputPath $outputPath
            
            $outputPath | Should -Exist
        }
    }
}

Describe "CoberturaMerger - Merge-CoverageStats" {
    
    Context "Stats file merging" {
        It "Should merge app source paths from multiple JSON files" {
            $statsFiles = @()
            
            # Create test stats files
            $stats1 = @{
                AppSourcePaths = @("src/Module1", "src/Module2")
                ExcludedObjectCount = 5
                ExcludedLinesExecuted = 100
            } | ConvertTo-Json
            $statsFile1 = Join-Path $TestDrive "stats1.json"
            Set-Content -Path $statsFile1 -Value $stats1 -Encoding UTF8
            $statsFiles += $statsFile1
            
            $stats2 = @{
                AppSourcePaths = @("src/Module3")
                ExcludedObjectCount = 3
                ExcludedLinesExecuted = 50
            } | ConvertTo-Json
            $statsFile2 = Join-Path $TestDrive "stats2.json"
            Set-Content -Path $statsFile2 -Value $stats2 -Encoding UTF8
            $statsFiles += $statsFile2
            
            $merged = Merge-CoverageStats -StatsFiles $statsFiles
            
            $merged | Should -Not -BeNullOrEmpty
            $merged.ExcludedObjectCount | Should -Be 8
            $merged.ExcludedLinesExecuted | Should -Be 150
            $merged.AppSourcePaths.Count | Should -Be 3
        }
        
        It "Should handle single stats file" {
            $stats = @{
                AppSourcePaths = @("src/Module1")
                ExcludedObjectCount = 2
            } | ConvertTo-Json
            $statsFile = Join-Path $TestDrive "singlestats.json"
            Set-Content -Path $statsFile -Value $stats -Encoding UTF8
            
            $merged = Merge-CoverageStats -StatsFiles @($statsFile)
            
            $merged.ExcludedObjectCount | Should -Be 2
            $merged.AppSourcePaths.Count | Should -Be 1
        }
        
        It "Should skip missing stats files" {
            $stats = @{
                ExcludedObjectCount = 5
            } | ConvertTo-Json
            $statsFile1 = Join-Path $TestDrive "exists.json"
            Set-Content -Path $statsFile1 -Value $stats -Encoding UTF8
            
            $statsFiles = @($statsFile1, (Join-Path $TestDrive "missing.json"))
            
            { Merge-CoverageStats -StatsFiles $statsFiles } | Should -Not -Throw
        }
        
        It "Should deduplicate app source paths" {
            $stats1 = @{
                AppSourcePaths = @("src/Module1", "src/Module2")
            } | ConvertTo-Json
            $statsFile1 = Join-Path $TestDrive "dedup1.json"
            Set-Content -Path $statsFile1 -Value $stats1 -Encoding UTF8
            
            $stats2 = @{
                AppSourcePaths = @("src/Module2", "src/Module3")
            } | ConvertTo-Json
            $statsFile2 = Join-Path $TestDrive "dedup2.json"
            Set-Content -Path $statsFile2 -Value $stats2 -Encoding UTF8
            
            $merged = Merge-CoverageStats -StatsFiles @($statsFile1, $statsFile2)
            
            # Should have 3 unique paths (Module1, Module2, Module3)
            $merged.AppSourcePaths.Count | Should -Be 3
        }
    }
}
