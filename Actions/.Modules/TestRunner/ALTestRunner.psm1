function Run-AlTests
(
    [string] $TestSuite = $script:DefaultTestSuite,
    [string] $TestCodeunitsRange = "",
    [string] $TestProcedureRange = "",
    [string] $ExtensionId = "",
    [ValidateSet('None','Disabled','Codeunit','Function')]
    [string] $RequiredTestIsolation = "None",
    [ValidateSet('','None','UnitTest','IntegrationTest','Uncategorized','AITest')]
    [string] $TestType = "",
    [ValidateSet("Disabled", "Codeunit")]
    [string] $TestIsolation = "Codeunit",
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AutorizationType = $script:DefaultAuthorizationType,
    [string] $TestPage = $global:DefaultTestPage,
    [switch] $DisableSSLVerification,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [array] $DisabledTests = @(),
    [bool] $Detailed = $true,
    [ValidateSet('no','error','warning')]
    [string] $AzureDevOps = 'no',
    [bool] $SaveResultFile = $true,
    [string] $ResultsFilePath = "$PSScriptRoot\TestResults.xml",
    [ValidateSet('XUnit','JUnit')]
    [string] $ResultsFormat = 'JUnit',
    [string] $AppName = '',
    [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
    [string] $CodeCoverageTrackingType = 'Disabled',
    [ValidateSet('Disabled','PerCodeunit','PerTest')]
    [string] $ProduceCodeCoverageMap = 'Disabled',
    [string] $CodeCoverageOutputPath = "$PSScriptRoot\CodeCoverage",
    [string] $CodeCoverageExporterId = $script:DefaultCodeCoverageExporter,
    [switch] $CodeCoverageTrackAllSessions,
    [string] $CodeCoverageFilePrefix = ("TestCoverageMap_" + (get-date -Format 'yyyyMMdd')),
    [bool] $StabilityRun
)
{
    $testRunArguments = @{
        TestSuite = $TestSuite
        TestCodeunitsRange = $TestCodeunitsRange
        TestProcedureRange = $TestProcedureRange
        ExtensionId = $ExtensionId
        RequiredTestIsolation = $RequiredTestIsolation
        TestType = $TestType
        TestRunnerId = (Get-TestRunnerId -TestIsolation $TestIsolation)
        CodeCoverageTrackingType = $CodeCoverageTrackingType
        ProduceCodeCoverageMap = $ProduceCodeCoverageMap
        CodeCoverageOutputPath = $CodeCoverageOutputPath
        CodeCoverageFilePrefix = $CodeCoverageFilePrefix
        CodeCoverageExporterId = $CodeCoverageExporterId
        AutorizationType = $AutorizationType
        TestPage = $TestPage
        DisableSSLVerification = $DisableSSLVerification
        ServiceUrl = $ServiceUrl
        Credential = $Credential
        DisabledTests = $DisabledTests
        Detailed = $Detailed
        StabilityRun = $StabilityRun
    }
    
    [array]$testRunResult = Run-AlTestsInternal @testRunArguments

    if($SaveResultFile -and $testRunResult)
    {
        # Import the formatter module
        $formatterPath = Join-Path $PSScriptRoot "TestResultFormatter.psm1"
        Import-Module $formatterPath -Force

        Save-TestResults -TestRunResultObject $testRunResult -ResultsFilePath $ResultsFilePath -Format $ResultsFormat -ExtensionId $ExtensionId -AppName $AppName
    }
    elseif ($SaveResultFile -and -not $testRunResult) {
        Write-Host "Warning: No test results to save - tests may not have run"
    }

    if($AzureDevOps -ne 'no' -and $testRunResult)
    {
        Report-ErrorsInAzureDevOps -AzureDevOps $AzureDevOps -TestRunResultObject $testRunResult
    }
}

function Invoke-ALTestResultVerification
(
    [string] $TestResultsFolder = $(throw "Missing argument TestResultsFolder"),
    [switch] $IgnoreErrorIfNoTestsExecuted
)
{
    $failedTestList = Get-FailedTestsFromXMLFiles -TestResultsFolder $TestResultsFolder

    if($failedTestList.Count -gt 0) 
    {
        $testsExecuted = $true;
        Write-Log "Failed tests:"
        $testsFailed = ""
        foreach($failedTest in $failedTestList)
        {
            $testsFailed += "Name: " + $failedTest.name + [environment]::NewLine
            $testsFailed += "Method: " + $failedTest.method + [environment]::NewLine
            $testsFailed += "Time: " + $failedTest.time + [environment]::NewLine
            $testsFailed += "Message: " + [environment]::NewLine + $failedTest.message + [environment]::NewLine
            $testsFailed += "StackTrace: "+ [environment]::NewLine + $failedTest.stackTrace + [environment]::NewLine  + [environment]::NewLine
        }

        Write-Log $testsFailed
        throw "Test execution failed due to the failing tests, see the list of the failed tests above."
    }

    if(-not $testsExecuted)
    {
        [array]$testResultFiles = Get-ChildItem -Path $TestResultsFolder -Filter "*.xml" | Foreach { "$($_.FullName)" }

        foreach($resultFile in $testResultFiles)
        {
            [xml]$xmlDoc = Get-Content "$resultFile"
            [array]$otherTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -ne 'Fail'}
            if($otherTests.Length -gt 0)
            {
                return;
            }

        }

        if (-not $IgnoreErrorIfNoTestsExecuted) {
            throw "No test codeunits were executed"
        }
    }
}

function Get-FailedTestsFromXMLFiles
(
    [string] $TestResultsFolder = $(throw "Missing argument TestResultsFolder")
)
{
    $failedTestList = New-Object System.Collections.ArrayList
    $testsExecuted = $false
    [array]$testResultFiles = Get-ChildItem -Path $TestResultsFolder -Filter "*.xml" | Foreach { "$($_.FullName)" }

    if($testResultFiles.Length -eq 0)
    {
        throw "No test results were found"
    }

    foreach($resultFile in $testResultFiles)
    {
        [xml]$xmlDoc = Get-Content "$resultFile"
        [array]$failedTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -eq 'Fail'}
        if($failedTests)
        {
            $testsExecuted = $true
            foreach($failedTest in $failedTests)
            {
                $failedTestObject = @{
                    codeunitID = [int]($failedTest.ParentNode.ParentNode.'x-code-unit');
                    codeunitName = $failedTest.name;
                    method = $failedTest.method;
                    time = $failedTest.time;
                    message = $failedTest.failure.message;
                    stackTrace = $failedTest.failure.'stack-trace';
                }

                $failedTestList.Add($failedTestObject) > $null
            }
        }
    }

    return $failedTestList
}

function Write-DisabledTestsJson
(
    $FailedTests,
    [string] $OutputFolder = $(throw "Missing argument OutputFolder"),
    [string] $FileName = 'DisabledTests.json'
)
{
    $testsToDisable = New-Object -TypeName "System.Collections.ArrayList"
    foreach($failedTest in $failedTests)
    {
        $test = @{
                    codeunitID = $failedTest.codeunitID;
                    codeunitName = $failedTest.name;
                    method = $failedTest.method;
                }

       $testsToDisable.Add($test)
    }

    $oututFile = Join-Path $OutputFolder $FileName
    if(-not (Test-Path $outputFolder))
    {
        New-Item -Path $outputFolder -ItemType Directory
    }

    Add-Content -Value (ConvertTo-Json $testsToDisable) -Path $oututFile
}

function Report-ErrorsInAzureDevOps
(
    [ValidateSet('no','error','warning')]
    [string] $AzureDevOps = 'no',
    $TestRunResultObject
)
{
    if ($AzureDevOps -eq 'no')
    {
        return
    }

    $failedCodeunits = $TestRunResultObject | Where-Object { $_.result -eq $script:FailureTestResultType }
    $failedTests = $failedCodeunits.testResults | Where-Object { $_.result -eq $script:FailureTestResultType }

    foreach($failedTest in $failedTests)
    {
        $methodName = $failedTest.method;
        $errorMessage = $failedTests.message
        Write-Host "##vso[task.logissue type=$AzureDevOps;sourcepath=$methodName;]$errorMessage"
    }
}

function Get-DisabledAlTests
(
    [string] $DisabledTestsPath
)
{
    $DisabledTests = @()
    if(Test-Path $DisabledTestsPath)
    {
        $DisabledTests = Get-Content $DisabledTestsPath | ConvertFrom-Json
    }

    return $DisabledTests
}

function Get-TestRunnerId
(
    [ValidateSet("Disabled", "Codeunit")]
    [string] $TestIsolation = "Codeunit"
)
{
    switch($TestIsolation)
    {
        "Codeunit" 
        {
            return Get-CodeunitTestIsolationTestRunnerId
        }
        "Disabled"
        {
            return Get-DisabledTestIsolationTestRunnerId
        }
    }
}

function Get-DisabledTestIsolationTestRunnerId()
{
    return $global:TestRunnerIsolationDisabled
}

function Get-CodeunitTestIsolationTestRunnerId()
{
    return $global:TestRunnerIsolationCodeunit
}

. "$PSScriptRoot\Internal\Constants.ps1"
Import-Module "$PSScriptRoot\Internal\ALTestRunnerInternal.psm1"