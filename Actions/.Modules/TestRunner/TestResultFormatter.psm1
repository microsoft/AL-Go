<#
.SYNOPSIS
    Test result formatting utilities for converting test results to various output formats.
.DESCRIPTION
    This module provides functions to convert AL test run results into different XML formats
    such as XUnit and JUnit. It can be extended to support additional formats as needed.
#>

<#
.SYNOPSIS
    Saves test results to a file in the specified format.
.PARAMETER TestRunResultObject
    The test run result object containing test execution data.
.PARAMETER ResultsFilePath
    The path where the results file should be saved.
.PARAMETER Format
    The output format. Supported values: 'XUnit', 'JUnit'. Default is 'JUnit'.
.PARAMETER ExtensionId
    Optional extension ID to include in JUnit output for proper test grouping.
.PARAMETER AppName
    Optional app name to include in JUnit output for proper test grouping.
#>
function Save-TestResults {
    param(
        [Parameter(Mandatory = $true)]
        $TestRunResultObject,
        [Parameter(Mandatory = $true)]
        [string] $ResultsFilePath,
        [ValidateSet('XUnit', 'JUnit')]
        [string] $Format = 'JUnit',
        [string] $ExtensionId = '',
        [string] $AppName = ''
    )

    switch ($Format) {
        'XUnit' {
            Save-ResultsAsXUnit -TestRunResultObject $TestRunResultObject -ResultsFilePath $ResultsFilePath
        }
        'JUnit' {
            Save-ResultsAsJUnit -TestRunResultObject $TestRunResultObject -ResultsFilePath $ResultsFilePath -ExtensionId $ExtensionId -AppName $AppName
        }
    }
}

<#
.SYNOPSIS
    Converts test results to XUnit format and saves to file.
#>
function Save-ResultsAsXUnit {
    param(
        [Parameter(Mandatory = $true)]
        $TestRunResultObject,
        [Parameter(Mandatory = $true)]
        [string] $ResultsFilePath
    )

    [xml]$XUnitDoc = New-Object System.Xml.XmlDocument
    $XUnitDoc.AppendChild($XUnitDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
    $XUnitAssemblies = $XUnitDoc.CreateElement("assemblies")
    $XUnitDoc.AppendChild($XUnitAssemblies) | Out-Null

    foreach ($testResult in $TestRunResultObject) {
        $name = $testResult.name
        $startTime = [datetime]($testResult.startTime)
        $finishTime = [datetime]($testResult.finishTime)
        $duration = $finishTime.Subtract($startTime)
        $durationSeconds = [Math]::Round($duration.TotalSeconds, 3)

        $XUnitAssembly = $XUnitDoc.CreateElement("assembly")
        $XUnitAssemblies.AppendChild($XUnitAssembly) | Out-Null
        $XUnitAssembly.SetAttribute("name", $name)
        $XUnitAssembly.SetAttribute("x-code-unit", $testResult.codeUnit)
        $XUnitAssembly.SetAttribute("test-framework", "PS Test Runner")
        $XUnitAssembly.SetAttribute("run-date", $startTime.ToString("yyyy-MM-dd"))
        $XUnitAssembly.SetAttribute("run-time", $startTime.ToString("HH:mm:ss"))
        $XUnitAssembly.SetAttribute("total", 0)
        $XUnitAssembly.SetAttribute("passed", 0)
        $XUnitAssembly.SetAttribute("failed", 0)
        $XUnitAssembly.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))
        
        $XUnitCollection = $XUnitDoc.CreateElement("collection")
        $XUnitAssembly.AppendChild($XUnitCollection) | Out-Null
        $XUnitCollection.SetAttribute("name", $name)
        $XUnitCollection.SetAttribute("total", 0)
        $XUnitCollection.SetAttribute("passed", 0)
        $XUnitCollection.SetAttribute("failed", 0)
        $XUnitCollection.SetAttribute("skipped", 0)
        $XUnitCollection.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

        foreach ($testMethod in $testResult.testResults) {
            $testMethodName = $testMethod.method
            $XUnitAssembly.SetAttribute("total", ([int]$XUnitAssembly.GetAttribute("total") + 1))
            $XUnitCollection.SetAttribute("total", ([int]$XUnitCollection.GetAttribute("total") + 1))
            
            $XUnitTest = $XUnitDoc.CreateElement("test")
            $XUnitCollection.AppendChild($XUnitTest) | Out-Null
            $XUnitTest.SetAttribute("name", $XUnitAssembly.GetAttribute("name") + ':' + $testMethodName)
            $XUnitTest.SetAttribute("method", $testMethodName)
            
            $methodStartTime = [datetime]($testMethod.startTime)
            $methodFinishTime = [datetime]($testMethod.finishTime)
            $methodDuration = $methodFinishTime.Subtract($methodStartTime)
            $methodDurationSeconds = [Math]::Round($methodDuration.TotalSeconds, 3)
            $XUnitTest.SetAttribute("time", $methodDurationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

            switch ($testMethod.result) {
                2 { # Success
                    $XUnitAssembly.SetAttribute("passed", ([int]$XUnitAssembly.GetAttribute("passed") + 1))
                    $XUnitCollection.SetAttribute("passed", ([int]$XUnitCollection.GetAttribute("passed") + 1))
                    $XUnitTest.SetAttribute("result", "Pass")
                }
                1 { # Failure
                    $XUnitAssembly.SetAttribute("failed", ([int]$XUnitAssembly.GetAttribute("failed") + 1))
                    $XUnitCollection.SetAttribute("failed", ([int]$XUnitCollection.GetAttribute("failed") + 1))
                    $XUnitTest.SetAttribute("result", "Fail")
                    
                    $XUnitFailure = $XUnitDoc.CreateElement("failure")
                    $XUnitMessage = $XUnitDoc.CreateElement("message")
                    $XUnitMessage.InnerText = $testMethod.message
                    $XUnitFailure.AppendChild($XUnitMessage) | Out-Null
                    $XUnitStacktrace = $XUnitDoc.CreateElement("stack-trace")
                    $XUnitStacktrace.InnerText = $($testMethod.stackTrace).Replace(";", "`n")
                    $XUnitFailure.AppendChild($XUnitStacktrace) | Out-Null
                    $XUnitTest.AppendChild($XUnitFailure) | Out-Null
                }
                3 { # Skipped
                    $XUnitCollection.SetAttribute("skipped", ([int]$XUnitCollection.GetAttribute("skipped") + 1))
                    $XUnitTest.SetAttribute("result", "Skip")
                }
            }
        }
    }

    $XUnitDoc.Save($ResultsFilePath)
}

<#
.SYNOPSIS
    Converts test results to JUnit format and saves to file.
.DESCRIPTION
    Generates JUnit XML format compatible with AL-Go's AnalyzeTests action.
    The format follows the standard JUnit schema with testsuites/testsuite/testcase structure.
#>
function Save-ResultsAsJUnit {
    param(
        [Parameter(Mandatory = $true)]
        $TestRunResultObject,
        [Parameter(Mandatory = $true)]
        [string] $ResultsFilePath,
        [string] $ExtensionId = '',
        [string] $AppName = ''
    )

    [xml]$JUnitDoc = New-Object System.Xml.XmlDocument
    $JUnitDoc.AppendChild($JUnitDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
    $JUnitTestSuites = $JUnitDoc.CreateElement("testsuites")
    $JUnitDoc.AppendChild($JUnitTestSuites) | Out-Null

    $hostname = $env:COMPUTERNAME
    if (-not $hostname) { $hostname = "localhost" }

    foreach ($testResult in $TestRunResultObject) {
        $codeunitId = $testResult.codeUnit
        $name = $testResult.name
        $startTime = [datetime]($testResult.startTime)
        $finishTime = [datetime]($testResult.finishTime)
        $duration = $finishTime.Subtract($startTime)
        $durationSeconds = [Math]::Round($duration.TotalSeconds, 3)

        $JUnitTestSuite = $JUnitDoc.CreateElement("testsuite")
        $JUnitTestSuites.AppendChild($JUnitTestSuite) | Out-Null
        $JUnitTestSuite.SetAttribute("name", "$codeunitId $name")
        $JUnitTestSuite.SetAttribute("timestamp", $startTime.ToString("s"))
        $JUnitTestSuite.SetAttribute("hostname", $hostname)
        $JUnitTestSuite.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))
        $JUnitTestSuite.SetAttribute("tests", 0)
        $JUnitTestSuite.SetAttribute("failures", 0)
        $JUnitTestSuite.SetAttribute("errors", 0)
        $JUnitTestSuite.SetAttribute("skipped", 0)

        # Add properties element for extensionId and appName (required by AnalyzeTests)
        $JUnitProperties = $JUnitDoc.CreateElement("properties")
        $JUnitTestSuite.AppendChild($JUnitProperties) | Out-Null

        if ($ExtensionId) {
            $property = $JUnitDoc.CreateElement("property")
            $property.SetAttribute("name", "extensionId")
            $property.SetAttribute("value", $ExtensionId)
            $JUnitProperties.AppendChild($property) | Out-Null
        }

        if ($AppName) {
            $property = $JUnitDoc.CreateElement("property")
            $property.SetAttribute("name", "appName")
            $property.SetAttribute("value", $AppName)
            $JUnitProperties.AppendChild($property) | Out-Null
        }

        $totalTests = 0
        $failedTests = 0
        $skippedTests = 0

        foreach ($testMethod in $testResult.testResults) {
            $testMethodName = $testMethod.method
            $totalTests++

            $methodStartTime = [datetime]($testMethod.startTime)
            $methodFinishTime = [datetime]($testMethod.finishTime)
            $methodDuration = $methodFinishTime.Subtract($methodStartTime)
            $methodDurationSeconds = [Math]::Round($methodDuration.TotalSeconds, 3)

            $JUnitTestCase = $JUnitDoc.CreateElement("testcase")
            $JUnitTestSuite.AppendChild($JUnitTestCase) | Out-Null
            $JUnitTestCase.SetAttribute("classname", "$codeunitId $name")
            $JUnitTestCase.SetAttribute("name", $testMethodName)
            $JUnitTestCase.SetAttribute("time", $methodDurationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

            switch ($testMethod.result) {
                2 { # Success
                    # No child element needed for success
                }
                1 { # Failure
                    $failedTests++
                    $JUnitFailure = $JUnitDoc.CreateElement("failure")
                    $JUnitFailure.SetAttribute("message", $testMethod.message)
                    $stackTrace = $($testMethod.stackTrace).Replace(";", "`n")
                    $JUnitFailure.InnerText = $stackTrace
                    $JUnitTestCase.AppendChild($JUnitFailure) | Out-Null
                }
                3 { # Skipped
                    $skippedTests++
                    $JUnitSkipped = $JUnitDoc.CreateElement("skipped")
                    $JUnitTestCase.AppendChild($JUnitSkipped) | Out-Null
                }
            }
        }

        $JUnitTestSuite.SetAttribute("tests", $totalTests)
        $JUnitTestSuite.SetAttribute("failures", $failedTests)
        $JUnitTestSuite.SetAttribute("skipped", $skippedTests)
    }

    $JUnitDoc.Save($ResultsFilePath)
}

Export-ModuleMember -Function Save-TestResults, Save-ResultsAsXUnit, Save-ResultsAsJUnit
