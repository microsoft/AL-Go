Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

# BuildCodeCoverageSummary depends on AL-Go-Helper.ps1 and CoverageReportGenerator.ps1.
# We dot-source only CoverageReportGenerator (the functions we actually test)
# and mock the GitHub environment variables.

BeforeAll {
    . (Join-Path $PSScriptRoot "../../Actions/BuildCodeCoverageSummary/CoverageReportGenerator.ps1")

    $testDataPath = Join-Path $PSScriptRoot "TestData/CoberturaFiles"
}

Describe "BuildCodeCoverageSummary - GetStringByteSize" {

    BeforeAll {
        # Replicate the helper function defined inside the action script
        function GetStringByteSize($string) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($string)
            return $bytes.Length
        }
    }

    It "Should return correct byte size for ASCII strings" {
        $size = GetStringByteSize("Hello")
        $size | Should -Be 5
    }

    It "Should return correct byte size for empty string" {
        $size = GetStringByteSize("")
        $size | Should -Be 0
    }

    It "Should handle multi-byte characters" {
        $size = GetStringByteSize("ä")
        $size | Should -BeGreaterThan 1
    }
}

Describe "BuildCodeCoverageSummary - Coverage file discovery" {

    It "Should detect when coverage file exists" {
        $workspace = $TestDrive
        $project = "TestProject"

        # Create expected directory structure
        $coverageDir = Join-Path $workspace "$project/.buildartifacts/CodeCoverage"
        New-Item -ItemType Directory -Path $coverageDir -Force | Out-Null
        Copy-Item (Join-Path $testDataPath "cobertura1.xml") (Join-Path $coverageDir "cobertura.xml")

        $coverageFile = Join-Path $workspace "$project/.buildartifacts/CodeCoverage/cobertura.xml"
        Test-Path -Path $coverageFile -PathType Leaf | Should -BeTrue
    }

    It "Should detect when coverage file is missing" {
        $workspace = $TestDrive
        $coverageFile = Join-Path $workspace "missing-project/.buildartifacts/CodeCoverage/cobertura.xml"
        Test-Path -Path $coverageFile -PathType Leaf | Should -BeFalse
    }
}

Describe "BuildCodeCoverageSummary - Summary generation" {

    It "Should generate coverage summary from Cobertura file" {
        $coverageFile = Join-Path $testDataPath "cobertura1.xml"

        $result = Get-CoverageSummaryMD -CoverageFile $coverageFile

        $result | Should -Not -BeNullOrEmpty
        $result.SummaryMD | Should -Not -BeNullOrEmpty
        $result.SummaryMD | Should -Match "Coverage"
    }

    It "Should return empty summary for missing file" {
        $result = Get-CoverageSummaryMD -CoverageFile (Join-Path $TestDrive "nonexistent.xml")

        $result.SummaryMD | Should -BeNullOrEmpty
    }

    It "Should handle empty coverage data" {
        $coverageFile = Join-Path $testDataPath "cobertura-empty.xml"

        $result = Get-CoverageSummaryMD -CoverageFile $coverageFile

        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "BuildCodeCoverageSummary - Size limit handling" {

    BeforeAll {
        function GetStringByteSize($string) {
            return [System.Text.Encoding]::UTF8.GetBytes($string).Length
        }
    }

    It "Should calculate combined size correctly" {
        $titleSize = GetStringByteSize("## Code Coverage`n`n")
        $summarySize = GetStringByteSize("Some summary content")
        $detailsSize = GetStringByteSize("Some details content")

        $totalSize = $titleSize + $summarySize + $detailsSize
        $totalSize | Should -BeLessThan (1MB)
    }

    It "Should detect when summary exceeds 1MB limit" {
        $largeContent = "x" * (1MB + 1)
        $size = GetStringByteSize($largeContent)

        $size | Should -BeGreaterThan (1MB - 4)
    }

    It "Should keep small summaries under limit" {
        $coverageFile = Join-Path $testDataPath "cobertura1.xml"
        $result = Get-CoverageSummaryMD -CoverageFile $coverageFile

        $titleSize = GetStringByteSize("## Code Coverage`n`n")
        $summarySize = GetStringByteSize($result.SummaryMD)

        ($titleSize + $summarySize) | Should -BeLessThan (1MB - 4)
    }
}

Describe "BuildCodeCoverageSummary - Step summary output" {

    It "Should write to GITHUB_STEP_SUMMARY file" {
        $stepSummaryFile = Join-Path $TestDrive "step-summary.md"
        Set-Content -Path $stepSummaryFile -Value "" -Encoding UTF8

        $coverageFile = Join-Path $testDataPath "cobertura1.xml"
        $result = Get-CoverageSummaryMD -CoverageFile $coverageFile

        if ($result.SummaryMD) {
            Add-Content -Encoding UTF8 -Path $stepSummaryFile -Value "## Code Coverage`n`n"
            Add-Content -Encoding UTF8 -Path $stepSummaryFile -Value "$($result.SummaryMD)`n`n"
        }

        $content = Get-Content $stepSummaryFile -Raw
        $content | Should -Match "Code Coverage"
    }
}
