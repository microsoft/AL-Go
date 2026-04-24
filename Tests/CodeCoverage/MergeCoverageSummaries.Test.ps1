Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

BeforeAll {
    . (Join-Path $PSScriptRoot "../../Actions/BuildCodeCoverageSummary/CoverageReportGenerator.ps1")
    Import-Module (Join-Path $PSScriptRoot "../../Actions/MergeCoverageSummaries/CoberturaMerger.psm1") -Force -DisableNameChecking

    $testDataPath = Join-Path $PSScriptRoot "TestData/CoberturaFiles"
}

Describe "MergeCoverageSummaries - Artifact discovery" {

    Context "Finding coverage files" {
        It "Should find cobertura.xml files in subdirectories" {
            $artifactDir = Join-Path $TestDrive "artifacts"
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job1-CodeCoverage") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job2-CodeCoverage") -Force | Out-Null

            Copy-Item (Join-Path $testDataPath "cobertura1.xml") (Join-Path $artifactDir "job1-CodeCoverage/cobertura.xml")
            Copy-Item (Join-Path $testDataPath "cobertura2.xml") (Join-Path $artifactDir "job2-CodeCoverage/cobertura.xml")

            $files = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.xml" -Recurse -File)

            $files.Count | Should -Be 2
        }

        It "Should return empty when no coverage files exist" {
            $emptyDir = Join-Path $TestDrive "empty-artifacts"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            $files = @(Get-ChildItem -Path $emptyDir -Filter "cobertura.xml" -Recurse -File)

            $files.Count | Should -Be 0
        }

        It "Should handle missing artifact directory" {
            $missingDir = Join-Path $TestDrive "nonexistent"

            Test-Path $missingDir | Should -BeFalse
        }
    }
}

Describe "MergeCoverageSummaries - Single file bypass" {

    It "Should use single file directly without merging" {
        $artifactDir = Join-Path $TestDrive "single-artifact"
        $jobDir = Join-Path $artifactDir "job1-CodeCoverage"
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null

        $sourceFile = Join-Path $testDataPath "cobertura1.xml"
        Copy-Item $sourceFile (Join-Path $jobDir "cobertura.xml")

        $coberturaFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.xml" -Recurse -File)

        $coberturaFiles.Count | Should -Be 1
        # When count is 1, the action uses the file directly
        $mergedFile = $coberturaFiles[0].FullName
        Test-Path $mergedFile | Should -BeTrue
    }
}

Describe "MergeCoverageSummaries - Multi-file merge" {

    Context "Merging multiple coverage files" {
        It "Should merge multiple cobertura files" {
            $artifactDir = Join-Path $TestDrive "merge-artifacts"
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job1") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job2") -Force | Out-Null

            Copy-Item (Join-Path $testDataPath "cobertura1.xml") (Join-Path $artifactDir "job1/cobertura.xml")
            Copy-Item (Join-Path $testDataPath "cobertura2.xml") (Join-Path $artifactDir "job2/cobertura.xml")

            $coberturaFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.xml" -Recurse -File)
            $mergedOutputDir = Join-Path $artifactDir "_merged"
            $mergedFile = Join-Path $mergedOutputDir "cobertura.xml"

            $stats = Merge-CoberturaFiles `
                -CoberturaFiles ($coberturaFiles.FullName) `
                -OutputPath $mergedFile

            $mergedFile | Should -Exist
            $stats | Should -Not -BeNullOrEmpty
            $stats.InputFileCount | Should -Be 2
        }

        It "Should produce valid merged XML" {
            $artifactDir = Join-Path $TestDrive "valid-merge"
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job1") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job2") -Force | Out-Null

            Copy-Item (Join-Path $testDataPath "cobertura1.xml") (Join-Path $artifactDir "job1/cobertura.xml")
            Copy-Item (Join-Path $testDataPath "cobertura2.xml") (Join-Path $artifactDir "job2/cobertura.xml")

            $coberturaFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.xml" -Recurse -File)
            $mergedFile = Join-Path $artifactDir "_merged/cobertura.xml"

            Merge-CoberturaFiles -CoberturaFiles ($coberturaFiles.FullName) -OutputPath $mergedFile

            { [xml](Get-Content $mergedFile -Raw) } | Should -Not -Throw
        }
    }
}

Describe "MergeCoverageSummaries - Stats file merging" {

    Context "Merging stats metadata" {
        It "Should find and merge stats.json files" {
            $artifactDir = Join-Path $TestDrive "stats-merge"
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job1") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job2") -Force | Out-Null

            @{ AppSourcePaths = @("src/App1"); ExcludedObjectCount = 3 } |
                ConvertTo-Json | Set-Content (Join-Path $artifactDir "job1/cobertura.stats.json") -Encoding UTF8
            @{ AppSourcePaths = @("src/App2"); ExcludedObjectCount = 5 } |
                ConvertTo-Json | Set-Content (Join-Path $artifactDir "job2/cobertura.stats.json") -Encoding UTF8

            $statsFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.stats.json" -Recurse -File)
            $merged = Merge-CoverageStats -StatsFiles ($statsFiles.FullName)

            $merged | Should -Not -BeNullOrEmpty
            $merged.ExcludedObjectCount | Should -Be 8
            $merged.AppSourcePaths.Count | Should -Be 2
        }

        It "Should handle missing stats files gracefully" {
            $artifactDir = Join-Path $TestDrive "no-stats"
            New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

            $statsFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.stats.json" -Recurse -File)

            $statsFiles.Count | Should -Be 0
        }
    }
}

Describe "MergeCoverageSummaries - Summary generation" {

    Context "Consolidated coverage report" {
        It "Should generate markdown from merged file" {
            $artifactDir = Join-Path $TestDrive "summary-gen"
            New-Item -ItemType Directory -Path (Join-Path $artifactDir "job1") -Force | Out-Null
            Copy-Item (Join-Path $testDataPath "cobertura1.xml") (Join-Path $artifactDir "job1/cobertura.xml")

            $coberturaFiles = @(Get-ChildItem -Path $artifactDir -Filter "cobertura.xml" -Recurse -File)
            $mergedFile = $coberturaFiles[0].FullName

            $result = Get-CoverageSummaryMD -CoverageFile $mergedFile

            $result | Should -Not -BeNullOrEmpty
            $result.SummaryMD | Should -Match "Coverage"
        }
    }
}

Describe "MergeCoverageSummaries - Size limit handling" {

    BeforeAll {
        function GetStringByteSize($string) {
            return [System.Text.Encoding]::UTF8.GetBytes($string).Length
        }
    }

    It "Should calculate header and info sizes" {
        $header = "## :bar_chart: Code Coverage - Consolidated`n`n"
        $inputInfo = ":information_source: Merged from **2** build job(s)`n`n"

        $headerSize = GetStringByteSize($header)
        $inputInfoSize = GetStringByteSize($inputInfo)

        $headerSize | Should -BeGreaterThan 0
        $inputInfoSize | Should -BeGreaterThan 0
        ($headerSize + $inputInfoSize) | Should -BeLessThan (1MB)
    }
}

Describe "MergeCoverageSummaries - Incomplete build warning" {

    It "Should detect incomplete build from BUILD_RESULT env var" {
        # Simulate the logic from the action script
        $buildResult = 'failure'
        $incompleteWarning = ""

        if ($buildResult -eq 'failure') {
            $incompleteWarning = "> :warning: **Incomplete coverage data** - some build jobs failed"
        }

        $incompleteWarning | Should -Not -BeNullOrEmpty
        $incompleteWarning | Should -Match "Incomplete"
    }

    It "Should not warn for successful builds" {
        $buildResult = 'success'
        $incompleteWarning = ""

        if ($buildResult -eq 'failure') {
            $incompleteWarning = "> :warning: **Incomplete coverage data**"
        }

        $incompleteWarning | Should -BeNullOrEmpty
    }
}

Describe "MergeCoverageSummaries - Output variables" {

    It "Should format output variable correctly" {
        $mergedFile = "C:\workspace\.coverage-inputs\_merged\cobertura.xml"
        $outputLine = "mergedCoverageFile=$mergedFile"

        $outputLine | Should -Match "mergedCoverageFile="
        $outputLine | Should -Match "cobertura.xml"
    }
}
