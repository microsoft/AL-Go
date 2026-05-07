# Test form UI control helpers.
# These functions interact with the BC test tool page via the ClientContext.

# These Set-* functions modify in-memory BC form objects, not system state.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope='Function', Target='*')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. "$PSScriptRoot\Constants.ps1"

<#
.SYNOPSIS
    Opens the BC test tool page via the ClientContext.
#>
function Open-TestForm(
    [int] $TestPage = $global:DefaultTestPage,
    [ClientContext] $ClientContext
)
{
    $form = $ClientContext.OpenForm($TestPage)
    if (!$form)
    {
        throw "Cannot open page $TestPage. Verify if the test tool and test objects are imported and can be opened manually."
    }

    return $form;
}

<#
.SYNOPSIS
    Sets the test codeunit range filter on the test form.
#>
function Set-TestCodeunits
(
    [string] $TestCodeunitsFilter,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$TestCodeunitsFilter)
    {
        return
    }

    $testCodeunitRangeFilterControl = $ClientContext.GetControlByName($Form, "TestCodeunitRangeFilter")
    $ClientContext.SaveValue($testCodeunitRangeFilterControl, $TestCodeunitsFilter)
}

<#
.SYNOPSIS
    Sets the test runner codeunit ID on the test form.
#>
function Set-TestRunner
(
    [int] $TestRunnerId,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$TestRunnerId)
    {
        return
    }

    $testRunnerCodeunitIdControl = $ClientContext.GetControlByName($Form, "TestRunnerCodeunitId")
    $ClientContext.SaveValue($testRunnerCodeunitIdControl, $TestRunnerId)
}

<#
.SYNOPSIS
    Clears test results on the test form.
#>
function Clear-TestResults
(
    [ClientContext] $ClientContext,
    $Form
)
{
    $ClientContext.InvokeAction($ClientContext.GetActionByName($Form, "ClearTestResults"))
}

<#
.SYNOPSIS
    Sets the extension ID filter on the test form.
#>
function Set-ExtensionId
(
    [string] $ExtensionId,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$ExtensionId)
    {
        return
    }

    $extensionIdControl = $ClientContext.GetControlByName($Form, "ExtensionId")
    $ClientContext.SaveValue($extensionIdControl, $ExtensionId)
}

<#
.SYNOPSIS
    Sets the required test isolation level on the test form.
#>
function Set-RequiredTestIsolation {
    param (
        [ValidateSet('None','Disabled','Codeunit','Function')]
        [string] $RequiredTestIsolation = "None",
        [ClientContext] $ClientContext,
        $Form
    )
    $TestIsolationValues = @{
        None = 0
        Disabled = 1
        Codeunit = 2
        Function = 3
    }
    $testIsolationControl = $ClientContext.GetControlByName($Form, "RequiredTestIsolation")
    $ClientContext.SaveValue($testIsolationControl, $TestIsolationValues[$RequiredTestIsolation])
}

<#
.SYNOPSIS
    Sets the test type filter on the test form.
#>
function Set-TestType {
    param (
        [ValidateSet("UnitTest","IntegrationTest","Uncategorized")]
        [string] $TestType,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{
        UnitTest = 1
        IntegrationTest = 2
        Uncategorized = 3
    }
    $testTypeControl = $ClientContext.GetControlByName($Form, "TestType")
    $ClientContext.SaveValue($testTypeControl, $TypeValues[$TestType])
}

<#
.SYNOPSIS
    Sets the test suite name on the test form.
#>
function Set-TestSuite
(
    [string] $TestSuite = $script:DefaultTestSuite,
    [ClientContext] $ClientContext,
    $Form
)
{
    $suiteControl = $ClientContext.GetControlByName($Form, "CurrentSuiteName")
    $ClientContext.SaveValue($suiteControl, $TestSuite)
}

<#
.SYNOPSIS
    Sets the test procedure range filter on the test form.
#>
function Set-TestProcedures
{
    param (
        [string] $Filter,
        [ClientContext] $ClientContext,
        $Form
    )
    $Control = $ClientContext.GetControlByName($Form, "TestProcedureRangeFilter")
    $ClientContext.SaveValue($Control, $Filter)
}

<#
.SYNOPSIS
    Marks specified test methods as disabled on the test form.
#>
function Set-RunFalseOnDisabledTests
(
    [ClientContext] $ClientContext,
    [array] $DisabledTests,
    $Form
)
{
    if(!$DisabledTests)
    {
        return
    }

    foreach($disabledTestMethod in $DisabledTests)
    {
        $testKey = $disabledTestMethod.codeunitName + "," + $disabledTestMethod.method
        $removeTestMethodControl = $ClientContext.GetControlByName($Form, "DisableTestMethod")
        $ClientContext.SaveValue($removeTestMethodControl, $testKey)
    }
}

<#
.SYNOPSIS
    Sets the stability run flag on the test form.
#>
function Set-StabilityRun
(
    [bool] $StabilityRun,
    [ClientContext] $ClientContext,
    $Form
)
{
    $stabilityRunControl = $ClientContext.GetControlByName($Form, "StabilityRun")
    $ClientContext.SaveValue($stabilityRunControl, $StabilityRun)
}

<#
.SYNOPSIS
    Sets the code coverage tracking type on the test form.
#>
function Set-CCTrackingType
{
    param (
        [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{
        Disabled = 0
        PerRun = 1
        PerCodeunit=2
        PerTest=3
    }
    $suiteControl = $ClientContext.GetControlByName($Form, "CCTrackingType")
    $ClientContext.SaveValue($suiteControl, $TypeValues[$Value])
}

<#
.SYNOPSIS
    Enables code coverage tracking for all sessions on the test form.
#>
function Set-CCTrackAllSessions
{
    param (
        [switch] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    if($Value){
        $suiteControl = $ClientContext.GetControlByName($Form, "CCTrackAllSessions");
        $ClientContext.SaveValue($suiteControl, $Value)
    }
}

<#
.SYNOPSIS
    Sets the code coverage exporter ID on the test form.
#>
function Set-CCExporterID
{
    param (
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    if($Value){
        $suiteControl = $ClientContext.GetControlByName($Form, "CCExporterID");
        $ClientContext.SaveValue($suiteControl, $Value)
    }
}

<#
.SYNOPSIS
    Sets the code coverage map production granularity on the test form.
#>
function Set-CCProduceCodeCoverageMap
{

    param (
        [ValidateSet('Disabled', 'PerCodeunit', 'PerTest')]
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{
        Disabled = 0
        PerCodeunit = 1
        PerTest=2
    }
    $suiteControl = $ClientContext.GetControlByName($Form, "CCMap")
    $ClientContext.SaveValue($suiteControl, $TypeValues[$Value])
}

<#
.SYNOPSIS
    Clears code coverage results on the test form.
#>
function Clear-CCResults
{
    param (
        [ClientContext] $ClientContext,
        $Form
    )
    $ClientContext.InvokeAction($ClientContext.GetActionByName($Form, "ClearCodeCoverage"))
}

Export-ModuleMember -Function Open-TestForm, Set-TestCodeunits, Set-TestRunner, Clear-TestResults, `
    Set-ExtensionId, Set-RequiredTestIsolation, Set-TestType, Set-TestSuite, Set-TestProcedures, `
    Set-RunFalseOnDisabledTests, Set-StabilityRun, Set-CCTrackingType, Set-CCTrackAllSessions, `
    Set-CCExporterID, Set-CCProduceCodeCoverageMap, Clear-CCResults
