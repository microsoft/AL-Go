$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

BeforeAll {
    . (Join-Path $PSScriptRoot "../../Actions/.Modules/TestRunner/Internal/Constants.ps1")
    Import-Module (Join-Path $PSScriptRoot "../../Actions/.Modules/TestRunner/TestResultFormatter.psm1" -Resolve) -Force -DisableNameChecking

    # The formatter expects a nested structure: each item has codeUnit, name, startTime, finishTime
    # and a testResults array of individual test methods.
    function script:New-TestSuite([string]$codeunitId, [string]$name, [array]$methods) {
        return [PSCustomObject]@{
            codeUnit    = $codeunitId
            name        = $name
            startTime   = [DateTime]::new(2026, 1, 1, 10, 0, 0)
            finishTime  = [DateTime]::new(2026, 1, 1, 10, 0, 5)
            testResults = $methods
        }
    }

    function script:New-TestMethod([string]$method, [int]$result, [string]$message = "", [string]$testStackTrace = "") {
        return [PSCustomObject]@{
            method     = $method
            result     = $result
            message    = $message
            stackTrace = $testStackTrace
            startTime  = [DateTime]::new(2026, 1, 1, 10, 0, 0)
            finishTime = [DateTime]::new(2026, 1, 1, 10, 0, 1)
        }
    }
}

Describe "TestResultFormatter - Save-ResultsAsJUnit" {
    BeforeEach {
        $script:outDir = (Get-Item TestDrive:\).FullName
    }

    It "Should create valid JUnit XML with passing tests" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestAdd" -result $script:SuccessTestResultType),
                (New-TestMethod -method "TestSubtract" -result $script:SuccessTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "junit_pass.xml"
        Save-ResultsAsJUnit -TestRunResultObject $results -ResultsFilePath $outFile

        Test-Path $outFile | Should -BeTrue
        [xml]$xml = Get-Content $outFile -Encoding UTF8
        $xml.testsuites | Should -Not -BeNullOrEmpty
        $xml.testsuites.testsuite | Should -Not -BeNullOrEmpty
        [int]$xml.testsuites.testsuite.tests | Should -Be 2
        [int]$xml.testsuites.testsuite.failures | Should -Be 0
    }

    It "Should record failures with message and stack trace" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestFail" -result $script:FailureTestResultType -message "Assert failed" -stackTrace "at line 10;at line 20")
            ))
        )
        $outFile = Join-Path $script:outDir "junit_fail.xml"
        Save-ResultsAsJUnit -TestRunResultObject $results -ResultsFilePath $outFile

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        [int]$xml.testsuites.testsuite.failures | Should -Be 1
        $testcase = $xml.testsuites.testsuite.testcase
        $testcase.failure | Should -Not -BeNullOrEmpty
        $testcase.failure.message | Should -Be "Assert failed"
    }

    It "Should record skipped tests" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestSkip" -result $script:SkippedTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "junit_skip.xml"
        Save-ResultsAsJUnit -TestRunResultObject $results -ResultsFilePath $outFile

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        [int]$xml.testsuites.testsuite.skipped | Should -Be 1
    }

    It "Should include extensionId and appName as properties" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "Test1" -result $script:SuccessTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "junit_props.xml"
        Save-ResultsAsJUnit -TestRunResultObject $results -ResultsFilePath $outFile -ExtensionId "ext-123" -AppName "MyApp"

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        $props = $xml.testsuites.testsuite.properties.property
        ($props | Where-Object { $_.name -eq "extensionId" }).value | Should -Be "ext-123"
        ($props | Where-Object { $_.name -eq "appName" }).value | Should -Be "MyApp"
    }

    It "Should handle empty test results array" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @())
        )
        $outFile = Join-Path $script:outDir "junit_empty.xml"
        Save-ResultsAsJUnit -TestRunResultObject $results -ResultsFilePath $outFile

        Test-Path $outFile | Should -BeTrue
        [xml]$xml = Get-Content $outFile -Encoding UTF8
        [int]$xml.testsuites.testsuite.tests | Should -Be 0
    }
}

Describe "TestResultFormatter - Save-ResultsAsXUnit" {
    BeforeEach {
        $script:outDir = (Get-Item TestDrive:\).FullName
    }

    It "Should create valid XUnit XML with passing tests" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestAdd" -result $script:SuccessTestResultType),
                (New-TestMethod -method "TestSubtract" -result $script:SuccessTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "xunit_pass.xml"
        Save-ResultsAsXUnit -TestRunResultObject $results -ResultsFilePath $outFile

        Test-Path $outFile | Should -BeTrue
        [xml]$xml = Get-Content $outFile -Encoding UTF8
        $xml.assemblies | Should -Not -BeNullOrEmpty
        $xml.assemblies.assembly | Should -Not -BeNullOrEmpty
        [int]$xml.assemblies.assembly.total | Should -Be 2
        [int]$xml.assemblies.assembly.passed | Should -Be 2
        [int]$xml.assemblies.assembly.failed | Should -Be 0
    }

    It "Should record failures in XUnit format" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestFail" -result $script:FailureTestResultType -message "Assert failed" -stackTrace "at line 10")
            ))
        )
        $outFile = Join-Path $script:outDir "xunit_fail.xml"
        Save-ResultsAsXUnit -TestRunResultObject $results -ResultsFilePath $outFile

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        [int]$xml.assemblies.assembly.failed | Should -Be 1
    }

    It "Should handle mixed results" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "TestPass" -result $script:SuccessTestResultType),
                (New-TestMethod -method "TestFail" -result $script:FailureTestResultType -message "error"),
                (New-TestMethod -method "TestSkip" -result $script:SkippedTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "xunit_mixed.xml"
        Save-ResultsAsXUnit -TestRunResultObject $results -ResultsFilePath $outFile

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        [int]$xml.assemblies.assembly.total | Should -Be 3
        [int]$xml.assemblies.assembly.passed | Should -Be 1
        [int]$xml.assemblies.assembly.failed | Should -Be 1
        # XUnit tracks skipped at the collection level
        [int]$xml.assemblies.assembly.collection.skipped | Should -Be 1
    }
}

Describe "TestResultFormatter - Save-TestResults" {
    BeforeEach {
        $script:outDir = (Get-Item TestDrive:\).FullName
    }

    It "Should route to JUnit format" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "Test1" -result $script:SuccessTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "routed_junit.xml"
        Save-TestResults -TestRunResultObject $results -ResultsFilePath $outFile -Format 'JUnit'

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        $xml.testsuites | Should -Not -BeNullOrEmpty
    }

    It "Should route to XUnit format when specified" {
        $results = @(
            (New-TestSuite -codeunitId "50100" -name "MyTests" -methods @(
                (New-TestMethod -method "Test1" -result $script:SuccessTestResultType)
            ))
        )
        $outFile = Join-Path $script:outDir "routed_xunit.xml"
        Save-TestResults -TestRunResultObject $results -ResultsFilePath $outFile -Format 'XUnit'

        [xml]$xml = Get-Content $outFile -Encoding UTF8
        $xml.assemblies | Should -Not -BeNullOrEmpty
    }
}
