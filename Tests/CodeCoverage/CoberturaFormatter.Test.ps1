Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../Actions/.Modules/TestRunner/CoverageProcessor"
    Import-Module (Join-Path $scriptPath "CoberturaFormatter.psm1") -Force

    $testDataPath = Join-Path $PSScriptRoot "TestData"
}

Describe "CoberturaFormatter - New-CoberturaDocument" {

    Context "XML structure generation" {
        It "Should create valid Cobertura XML structure" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectTypeId = 5
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 5; IsCovered = $true; CoverageStatus = 0 }
                        [PSCustomObject]@{ LineNo = 15; Hits = 0; IsCovered = $false; CoverageStatus = 1 }
                    )
                    SourceInfo = @{
                        FilePath = "TestCodeunit.al"
                        RelativePath = "src/TestCodeunit.al"
                        ExecutableLines = 10
                        TotalLines = 20
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $xml | Should -Not -BeNullOrEmpty
            $xml.coverage | Should -Not -BeNullOrEmpty
            $xml.coverage.packages | Should -Not -BeNullOrEmpty
            $xml.coverage.sources | Should -Not -BeNullOrEmpty
        }

        It "Should include timestamp in coverage element" {
            $coverageData = @{}

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $xml.coverage.timestamp | Should -Not -BeNullOrEmpty
            [long]$xml.coverage.timestamp | Should -BeGreaterThan 0
        }

        It "Should calculate overall line-rate correctly" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectTypeId = 5
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 5; IsCovered = $true }
                    )
                    SourceInfo = @{ ExecutableLines = 4; FilePath = "test.al"; RelativePath = "test.al" }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $lineRateStr = $xml.coverage.'line-rate'
            $lineRateStr | Should -Not -BeNullOrEmpty
            $lineRate = [double]::Parse($lineRateStr, [System.Globalization.CultureInfo]::InvariantCulture)
            $lineRate | Should -BeGreaterOrEqual 0
            $lineRate | Should -BeLessOrEqual 1
        }

        It "Should handle empty coverage data" {
            $coverageData = @{}

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $xml.coverage | Should -Not -BeNullOrEmpty
            $xml.coverage.'lines-valid' | Should -Be "0"
            $xml.coverage.'lines-covered' | Should -Be "0"
        }

        It "Should include app metadata when provided" {
            $coverageData = @{}
            $appInfo = @{
                Name = "Test App"
                Version = "1.0.0.0"
                Publisher = "Test Publisher"
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData -AppInfo $appInfo

            $xml | Should -Not -BeNullOrEmpty
        }
    }

    Context "Package organization" {
        It "Should group objects by module/folder" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @()
                    SourceInfo = @{
                        FilePath = "C:\src\Module1\Test.al"
                        RelativePath = "Module1/Test.al"
                        ExecutableLines = 5
                    }
                }
                "Codeunit.50200" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50200
                    Lines = @()
                    SourceInfo = @{
                        FilePath = "C:\src\Module2\Other.al"
                        RelativePath = "Module2/Other.al"
                        ExecutableLines = 10
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $packages = @($xml.coverage.packages.package)
            $packages.Count | Should -BeGreaterThan 0
        }

        It "Should create classes for each AL object" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @([PSCustomObject]@{ LineNo = 10; Hits = 1; IsCovered = $true })
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 5
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $classes = $xml.coverage.packages.package.classes.class
            $classes | Should -Not -BeNullOrEmpty
            $classes.name | Should -Match "Codeunit"
        }
    }

    Context "Line coverage" {
        It "Should include line elements with hit counts" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 5; IsCovered = $true }
                        [PSCustomObject]@{ LineNo = 15; Hits = 3; IsCovered = $true }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 10
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $lines = $xml.coverage.packages.package.classes.class.lines.line
            $lines | Should -Not -BeNullOrEmpty
            $lines[0].number | Should -Be "10"
            $lines[0].hits | Should -Be "5"
        }

        It "Should include lines with zero hits when ExecutableLineNumbers provided" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 1; IsCovered = $true }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 5
                        ExecutableLineNumbers = @(10, 15, 20)
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $lines = @($xml.coverage.packages.package.classes.class.lines.line)
            $lines.Count | Should -BeGreaterThan 1
            $zeroHitLine = $lines | Where-Object { $_.number -eq "15" }
            $zeroHitLine.hits | Should -Be "0"
        }
    }

    Context "Method coverage" {
        It "Should include method elements when procedures available" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 5; IsCovered = $true }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 10
                        Procedures = @(
                            @{ Name = "TestProcedure"; StartLine = 8; EndLine = 12 }
                        )
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            $methods = $xml.coverage.packages.package.classes.class.methods.method
            $methods | Should -Not -BeNullOrEmpty
            $methods.name | Should -Contain "TestProcedure"
        }
    }
}

Describe "CoberturaFormatter - Save-CoberturaFile" {

    Context "File output" {
        It "Should save XML to specified path" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @()
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 5
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData
            $outputPath = Join-Path $TestDrive "output.cobertura.xml"

            Save-CoberturaFile -XmlDocument $xml -OutputPath $outputPath

            $outputPath | Should -Exist
        }

        It "Should create valid XML file" {
            $coverageData = @{}
            $xml = New-CoberturaDocument -CoverageData $coverageData
            $outputPath = Join-Path $TestDrive "valid.cobertura.xml"

            Save-CoberturaFile -XmlDocument $xml -OutputPath $outputPath

            { [xml](Get-Content $outputPath -Raw) } | Should -Not -Throw
        }

        It "Should use UTF-8 encoding" {
            $coverageData = @{}
            $xml = New-CoberturaDocument -CoverageData $coverageData
            $outputPath = Join-Path $TestDrive "utf8.cobertura.xml"

            Save-CoberturaFile -XmlDocument $xml -OutputPath $outputPath

            $content = Get-Content $outputPath -Raw
            $content | Should -Match '<?xml version="1.0"'
        }
    }
}

Describe "CoberturaFormatter - Statistics" {

    Context "Coverage calculations" {
        It "Should calculate lines-valid from source info when available" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 1; IsCovered = $true }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 20
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            [int]$linesValid = $xml.coverage.'lines-valid'
            $linesValid | Should -BeGreaterThan 0
        }

        It "Should calculate lines-covered from coverage data" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 5; IsCovered = $true }
                        [PSCustomObject]@{ LineNo = 15; Hits = 3; IsCovered = $true }
                        [PSCustomObject]@{ LineNo = 20; Hits = 0; IsCovered = $false }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 10
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            [int]$linesCovered = $xml.coverage.'lines-covered'
            $linesCovered | Should -Be 2
        }

        It "Should have line-rate between 0 and 1" {
            $coverageData = @{
                "Codeunit.50100" = @{
                    ObjectType = "Codeunit"
                    ObjectId = 50100
                    Lines = @(
                        [PSCustomObject]@{ LineNo = 10; Hits = 1; IsCovered = $true }
                    )
                    SourceInfo = @{
                        FilePath = "Test.al"
                        RelativePath = "Test.al"
                        ExecutableLines = 10
                    }
                }
            }

            $xml = New-CoberturaDocument -CoverageData $coverageData

            [double]$lineRate = $xml.coverage.'line-rate'
            $lineRate | Should -BeGreaterOrEqual 0
            $lineRate | Should -BeLessOrEqual 1
        }
    }
}
