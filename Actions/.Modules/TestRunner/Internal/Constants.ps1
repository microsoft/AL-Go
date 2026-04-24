# Shared constants for the CodeCoverage test runner module.
# Dot-sourced by ALTestRunner.psm1 and Internal modules.

# Line types
$script:CodeunitLineType = '0'
$script:FunctionLineType = '1'

# Test result types
$script:FailureTestResultType = '1'
$script:SuccessTestResultType = '2'
$script:SkippedTestResultType = '3'

# Defaults
$script:DefaultAuthorizationType = 'NavUserPassword'
$script:DefaultTestSuite = 'DEFAULT'
$script:DefaultErrorActionPreference = 'Stop'
$script:DateTimeFormat = 's'

# Network defaults
$script:DefaultTcpKeepActive = [timespan]::FromMinutes(2)
$script:DefaultTransactionTimeout = [timespan]::FromMinutes(10)
$script:DefaultCulture = "en-US"

# Test runner codeunit IDs
$global:TestRunnerIsolationCodeunit = 130450
$global:TestRunnerIsolationDisabled = 130451
$global:DefaultTestRunner = $global:TestRunnerIsolationCodeunit
$global:TestRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"

# Console test tool page
$global:DefaultTestPage = 130455
$global:AadTokenProvider = $null

# XMLport 130470 (Code Coverage Results) - exports covered/partially covered lines as CSV
# XMLport 130007 (Code Coverage Internal) - exports all lines including not covered as XML
$script:DefaultCodeCoverageExporter = 130470

# Sentinel values
$script:NumberOfUnexpectedFailuresBeforeAborting = 50
$script:AllTestsExecutedResult = "All tests executed."
$script:CCCollectedResult = "Done."
