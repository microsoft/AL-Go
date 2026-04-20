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

Describe "CoverageReportGenerator - New-CoverageBar" {

    Context "Bar rendering" {
        It "Should return all dashes for 0% coverage" {
            $bar = New-CoverageBar -Coverage 0 -Width 10
            $bar | Should -Match '\[-{10}\]'
        }

        It "Should return all hashes for 100% coverage" {
            $bar = New-CoverageBar -Coverage 100 -Width 10
            $bar | Should -Match '\[#{10}\]'
        }

        It "Should return half and half for 50% coverage" {
            $bar = New-CoverageBar -Coverage 50 -Width 10
            $bar | Should -Match '\[#{5}-{5}\]'
        }

        It "Should respect custom width" {
            $bar = New-CoverageBar -Coverage 50 -Width 20
            $bar | Should -Match '\[#{10}-{10}\]'
        }

        It "Should use default width of 10" {
            $bar = New-CoverageBar -Coverage 100
            $bar | Should -Match '\[#{10}\]'
        }
    }
}

Describe "CoverageReportGenerator - Get-ModuleFromFilename" {

    Context "With matching AppRoots" {
        It "Should return Area as matching root and Module as root/first-subdir" {
            $result = Get-ModuleFromFilename -Filename "src/System Application/App/Email/src/Email.Codeunit.al" -AppRoots @("src/System Application/App")

            $result.Area | Should -Be "src/System Application/App"
            $result.Module | Should -Be "src/System Application/App/Email"
        }

        It "Should match longest AppRoot when multiple roots could match" {
            $appRoots = @("src", "src/System Application", "src/System Application/App")
            $result = Get-ModuleFromFilename -Filename "src/System Application/App/Email/src/Email.Codeunit.al" -AppRoots $appRoots

            $result.Area | Should -Be "src/System Application/App"
            $result.Module | Should -Be "src/System Application/App/Email"
        }

        It "Should normalize backslashes in filename" {
            $result = Get-ModuleFromFilename -Filename "src\System Application\App\Email\src\Email.Codeunit.al" -AppRoots @("src/System Application/App")

            $result.Area | Should -Be "src/System Application/App"
            $result.Module | Should -Be "src/System Application/App/Email"
        }

        It "Should set Module equal to Area when no subdirectory exists under root" {
            $result = Get-ModuleFromFilename -Filename "src/System Application/App/File.al" -AppRoots @("src/System Application/App")

            $result.Area | Should -Be "src/System Application/App"
            $result.Module | Should -Be "src/System Application/App/File.al"
        }
    }

    Context "Without AppRoots (depth heuristic)" {
        It "Should use 3-level area and 4-level module for deep paths" {
            $result = Get-ModuleFromFilename -Filename "src/System Application/App/Email/src/Email.Codeunit.al"

            $result.Area | Should -Be "src/System Application/App"
            $result.Module | Should -Be "src/System Application/App/Email"
        }

        It "Should set area and module to full path for shallow paths (fewer than 3 segments)" {
            $result = Get-ModuleFromFilename -Filename "src/File.al"

            $result.Area | Should -Be "src/File.al"
            $result.Module | Should -Be "src/File.al"
        }

        It "Should set module equal to area when path has exactly 3 segments" {
            $result = Get-ModuleFromFilename -Filename "src/App/File.al"

            $result.Area | Should -Be "src/App/File.al"
            $result.Module | Should -Be "src/App/File.al"
        }

        It "Should handle single segment path" {
            $result = Get-ModuleFromFilename -Filename "File.al"

            $result.Area | Should -Be "File.al"
            $result.Module | Should -Be "File.al"
        }
    }

    Context "No matching AppRoot falls back to heuristic" {
        It "Should use depth heuristic when no AppRoot matches" {
            $result = Get-ModuleFromFilename -Filename "other/path/deep/module/src/File.al" -AppRoots @("src/System Application/App")

            $result.Area | Should -Be "other/path/deep"
            $result.Module | Should -Be "other/path/deep/module"
        }
    }
}

Describe "CoverageReportGenerator - Get-ModuleCoverageData" {

    Context "Single area with single module" {
        It "Should return one area with correct aggregated data" {
            $coverage = @{
                Packages = @(
                    @{
                        Classes = @(
                            @{ Filename = "src/App/Module1/File1.al"; LinesTotal = 10; LinesCovered = 5 },
                            @{ Filename = "src/App/Module1/File2.al"; LinesTotal = 20; LinesCovered = 15 }
                        )
                    }
                )
            }

            $result = Get-ModuleCoverageData -Coverage $coverage

            $result.Keys.Count | Should -Be 1
            $area = $result["src/App/Module1"]
            $area | Should -Not -BeNullOrEmpty
            $area.TotalLines | Should -Be 30
            $area.CoveredLines | Should -Be 20
            $area.Objects | Should -Be 2
            $area.AllZero | Should -Be $false
        }
    }

    Context "Multiple areas" {
        It "Should separate classes into distinct areas" {
            $coverage = @{
                Packages = @(
                    @{
                        Classes = @(
                            @{ Filename = "src/AppA/Mod/sub/File.al"; LinesTotal = 10; LinesCovered = 8 },
                            @{ Filename = "src/AppB/Mod/sub/File.al"; LinesTotal = 20; LinesCovered = 5 }
                        )
                    }
                )
            }

            $result = Get-ModuleCoverageData -Coverage $coverage

            $result.Keys.Count | Should -Be 2
            $result.ContainsKey("src/AppA/Mod") | Should -Be $true
            $result.ContainsKey("src/AppB/Mod") | Should -Be $true
        }
    }

    Context "Area with zero coverage" {
        It "Should set AllZero to true when no lines are covered" {
            $coverage = @{
                Packages = @(
                    @{
                        Classes = @(
                            @{ Filename = "src/App/Module1/File1.al"; LinesTotal = 10; LinesCovered = 0 },
                            @{ Filename = "src/App/Module1/File2.al"; LinesTotal = 20; LinesCovered = 0 }
                        )
                    }
                )
            }

            $result = Get-ModuleCoverageData -Coverage $coverage

            $area = $result["src/App/Module1"]
            $area.AllZero | Should -Be $true
            $area.CoveredLines | Should -Be 0
        }
    }

    Context "Mixed coverage" {
        It "Should correctly mark areas with and without coverage" {
            $coverage = @{
                Packages = @(
                    @{
                        Classes = @(
                            @{ Filename = "src/Covered/Mod/sub/File.al"; LinesTotal = 10; LinesCovered = 5 },
                            @{ Filename = "src/Uncovered/Mod/sub/File.al"; LinesTotal = 20; LinesCovered = 0 }
                        )
                    }
                )
            }

            $result = Get-ModuleCoverageData -Coverage $coverage

            $covered = $result["src/Covered/Mod"]
            $covered.AllZero | Should -Be $false

            $uncovered = $result["src/Uncovered/Mod"]
            $uncovered.AllZero | Should -Be $true
        }
    }

    Context "With AppRoots" {
        It "Should use AppRoots to determine area and module" {
            $coverage = @{
                Packages = @(
                    @{
                        Classes = @(
                            @{ Filename = "src/System Application/App/Email/src/Email.Codeunit.al"; LinesTotal = 10; LinesCovered = 8 }
                        )
                    }
                )
            }

            $result = Get-ModuleCoverageData -Coverage $coverage -AppRoots @("src/System Application/App")

            $result.ContainsKey("src/System Application/App") | Should -Be $true
            $area = $result["src/System Application/App"]
            $area.TotalLines | Should -Be 10
            $area.CoveredLines | Should -Be 8
            $area.Modules.ContainsKey("src/System Application/App/Email") | Should -Be $true
        }
    }
}

Describe "CoverageReportGenerator - Read-CoberturaFile fallback path" {

    Context "Missing lines-covered and lines-valid attributes" {
        It "Should compute LinesCovered and LinesValid from class data" {
            $xmlContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<coverage line-rate="0.75" branch-rate="0.0" version="1.0" timestamp="1710166800">
  <packages>
    <package name="TestPkg" line-rate="0.75" branch-rate="0.0">
      <classes>
        <class name="Codeunit.50100" filename="src/File1.al" line-rate="0.75">
          <methods/>
          <lines>
            <line number="1" hits="1" branch="false"/>
            <line number="2" hits="1" branch="false"/>
            <line number="3" hits="1" branch="false"/>
            <line number="4" hits="0" branch="false"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
'@
            $tempFile = Join-Path $TestDrive "no-attrs.xml"
            Set-Content -Path $tempFile -Value $xmlContent -Encoding UTF8

            $data = Read-CoberturaFile -CoverageFile $tempFile

            $data.LinesCovered | Should -Be 3
            $data.LinesValid | Should -Be 4
        }

        It "Should compute totals across multiple packages" {
            $xmlContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<coverage line-rate="0.5" branch-rate="0.0" version="1.0" timestamp="1710166800">
  <packages>
    <package name="Pkg1" line-rate="1.0">
      <classes>
        <class name="C1" filename="src/F1.al" line-rate="1.0">
          <methods/>
          <lines>
            <line number="1" hits="1"/>
            <line number="2" hits="1"/>
          </lines>
        </class>
      </classes>
    </package>
    <package name="Pkg2" line-rate="0.0">
      <classes>
        <class name="C2" filename="src/F2.al" line-rate="0.0">
          <methods/>
          <lines>
            <line number="1" hits="0"/>
            <line number="2" hits="0"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
'@
            $tempFile = Join-Path $TestDrive "no-attrs-multi.xml"
            Set-Content -Path $tempFile -Value $xmlContent -Encoding UTF8

            $data = Read-CoberturaFile -CoverageFile $tempFile

            $data.LinesCovered | Should -Be 2
            $data.LinesValid | Should -Be 4
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
