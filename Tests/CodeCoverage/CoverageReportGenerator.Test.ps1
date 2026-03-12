Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../Actions/BuildCodeCoverageSummary/CoverageReportGenerator.ps1"
    . $scriptPath
    
    $testDataPath = Join-Path $PSScriptRoot "TestData/CoberturaFiles"
}

Describe "CoverageReportGenerator - Get-CoverageStatusIcon" {
    
    Context "Icon selection" {
        It "Should return green circle for >= 80%" {
            $icon = Get-CoverageStatusIcon -Coverage 80
            $icon | Should -Match "green"
        }
        
        It "Should return green circle for 100%" {
            $icon = Get-CoverageStatusIcon -Coverage 100
            $icon | Should -Match "green"
        }
        
        It "Should return yellow circle for 50-79%" {
            $icon = Get-CoverageStatusIcon -Coverage 50
            $icon | Should -Match "yellow"
            
            $icon = Get-CoverageStatusIcon -Coverage 79
            $icon | Should -Match "yellow"
        }
        
        It "Should return red circle for < 50%" {
            $icon = Get-CoverageStatusIcon -Coverage 0
            $icon | Should -Match "red"
            
            $icon = Get-CoverageStatusIcon -Coverage 49
            $icon | Should -Match "red"
        }
    }
}

Describe "CoverageReportGenerator - Format-CoveragePercent" {
    
    Context "Percentage formatting" {
        It "Should format line rate as percentage with icon" {
            $result = Format-CoveragePercent -LineRate 0.85
            
            $result | Should -Match "85"
            $result | Should -Match "%"
        }
        
        It "Should include appropriate icon" {
            $result = Format-CoveragePercent -LineRate 0.85
            $result | Should -Match "circle"
        }
        
        It "Should handle 0% coverage" {
            $result = Format-CoveragePercent -LineRate 0
            $result | Should -Match "0"
            $result | Should -Match "%"
        }
        
        It "Should handle 100% coverage" {
            $result = Format-CoveragePercent -LineRate 1.0
            $result | Should -Match "100"
            $result | Should -Match "%"
        }
    }
}

Describe "CoverageReportGenerator - Read-CoberturaFile" {
    
    Context "File parsing" {
        It "Should parse valid Cobertura XML" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $data = Read-CoberturaFile -CoverageFile $coverageFile
            
            $data | Should -Not -BeNullOrEmpty
            $data.LineRate | Should -BeGreaterOrEqual 0
            $data.LineRate | Should -BeLessOrEqual 1
        }
        
        It "Should extract coverage statistics" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $data = Read-CoberturaFile -CoverageFile $coverageFile
            
            $data.LinesCovered | Should -BeGreaterOrEqual 0
            $data.LinesValid | Should -BeGreaterOrEqual 0
        }
        
        It "Should group classes by package" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $data = Read-CoberturaFile -CoverageFile $coverageFile
            
            $data.Packages | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle empty coverage file" {
            $coverageFile = Join-Path $testDataPath "cobertura-empty.xml"
            
            $data = Read-CoberturaFile -CoverageFile $coverageFile
            
            $data | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "CoverageReportGenerator - Get-CoverageSummaryMD" {
    
    Context "Markdown generation" {
        It "Should generate markdown summary" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            $result | Should -Not -BeNullOrEmpty
            $result.SummaryMD | Should -Not -BeNullOrEmpty
            $result.SummaryMD | Should -Match "Coverage"
        }
        
        It "Should include overall coverage percentage" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            $result.SummaryMD | Should -Match "%"
        }
        
        It "Should include module/package breakdown in details" {
            $coverageFile = Join-Path $testDataPath "cobertura1.xml"
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            # Should have table with coverage data in details or summary
            ($result.SummaryMD + $result.DetailsMD) | Should -Match "\|"
        }
        
        It "Should handle empty coverage" {
            $coverageFile = Join-Path $testDataPath "cobertura-empty.xml"
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should load stats from matching .stats.json file" {
            $coverageFile = Join-Path $TestDrive "test.cobertura.xml"
            $statsFile = Join-Path $TestDrive "test.cobertura.stats.json"
            
            # Copy test coverage file
            Copy-Item (Join-Path $testDataPath "cobertura1.xml") $coverageFile
            
            # Create matching stats file
            @{
                ExcludedObjectCount = 5
                ExcludedLinesExecuted = 100
            } | ConvertTo-Json | Set-Content $statsFile -Encoding UTF8
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle missing coverage file gracefully" {
            $coverageFile = Join-Path $TestDrive "nonexistent.xml"
            
            $result = Get-CoverageSummaryMD -CoverageFile $coverageFile
            
            $result.SummaryMD | Should -BeNullOrEmpty
        }
    }
}
