$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

<#
    .SYNOPSIS
    Creates a RunTestsInBcContainer override scriptblock that uses the AL Test Runner with code coverage support.

    .DESCRIPTION
    Builds and returns a scriptblock compatible with the BcContainerHelper RunTestsInBcContainer parameter.
    The scriptblock connects to a BC container via client services, executes tests using Run-AlTests,
    collects code coverage data, and handles test result file accumulation (append mode for multi-app runs).

    .PARAMETER BuildArtifactFolder
    Path to the build artifact folder where coverage output will be stored under a 'CodeCoverage' subfolder.

    .PARAMETER TrackingType
    Code coverage tracking granularity: 'PerRun', 'PerCodeunit', or 'PerTest'.

    .PARAMETER ProduceMap
    Code coverage map granularity: 'Disabled', 'PerCodeunit', or 'PerTest'.
#>
function New-ALTestRunnerOverride {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildArtifactFolder,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PerRun', 'PerCodeunit', 'PerTest')]
        [string] $TrackingType,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Disabled', 'PerCodeunit', 'PerTest')]
        [string] $ProduceMap
    )

    Write-Host "Creating test runner override: TrackingType=$TrackingType, ProduceMap=$ProduceMap, OutputFolder=$BuildArtifactFolder"

    # Return a scriptblock that captures these parameters via closure
    return {
        Param([Hashtable]$parameters)

        $containerName = $parameters.containerName
        $credential = $parameters.credential
        $extensionId = $parameters.extensionId
        $appName = $parameters.appName

        # Handle both JUnit and XUnit result file names
        $resultsFilePath = $null
        $resultsFormat = 'JUnit'
        if ($parameters.JUnitResultFileName) {
            $resultsFilePath = $parameters.JUnitResultFileName
            $resultsFormat = 'JUnit'
        } elseif ($parameters.XUnitResultFileName) {
            $resultsFilePath = $parameters.XUnitResultFileName
            $resultsFormat = 'XUnit'
        }

        # Handle append mode for result file accumulation across test apps
        $appendToResults = $false
        $tempResultsFilePath = $null
        if ($resultsFilePath -and ($parameters.AppendToJUnitResultFile -or $parameters.AppendToXUnitResultFile)) {
            $appendToResults = $true
            $tempResultsFilePath = Join-Path ([System.IO.Path]::GetDirectoryName($resultsFilePath)) "TempTestResults_$([Guid]::NewGuid().ToString('N')).xml"
        }

        # Get container web client URL for connecting from host
        $containerConfig = Get-BcContainerServerConfiguration -ContainerName $containerName
        $publicWebBaseUrl = $containerConfig.PublicWebBaseUrl
        if (-not $publicWebBaseUrl) {
            # Fallback to constructing URL from container name
            $publicWebBaseUrl = "http://$($containerName):80/BC/"
        }
        # Ensure tenant parameter is included (required for client services connection)
        $tenant = if ($parameters.tenant) { $parameters.tenant } else { "default" }
        if ($publicWebBaseUrl -notlike "*tenant=*") {
            if ($publicWebBaseUrl.Contains("?")) {
                $serviceUrl = "$publicWebBaseUrl&tenant=$tenant"
            } else {
                $serviceUrl = "$($publicWebBaseUrl.TrimEnd('/'))/?tenant=$tenant"
            }
        } else {
            $serviceUrl = $publicWebBaseUrl
        }
        Write-Host "Using ServiceUrl: $serviceUrl"

        # Code coverage output path
        $codeCoverageOutputPath = Join-Path $BuildArtifactFolder "CodeCoverage"
        if (-not (Test-Path $codeCoverageOutputPath)) {
            New-Item -Path $codeCoverageOutputPath -ItemType Directory | Out-Null
        }
        Write-Host "Code coverage output path: $codeCoverageOutputPath"

        # Run tests with ALTestRunner from the host
        $testRunParams = @{
            ServiceUrl = $serviceUrl
            Credential = $credential
            AutorizationType = 'NavUserPassword'
            TestSuite = if ($parameters.testSuite) { $parameters.testSuite } else { 'DEFAULT' }
            Detailed = $true
            # SSL verification is disabled because this connects to a local Docker container
            # which uses self-signed certificates. The ServiceUrl is always a local container URL.
            DisableSSLVerification = $true
            ResultsFormat = $resultsFormat
            CodeCoverageTrackingType = $TrackingType
            ProduceCodeCoverageMap = $ProduceMap
            CodeCoverageOutputPath = $codeCoverageOutputPath
            CodeCoverageFilePrefix = "CodeCoverage_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }

        if ($extensionId) {
            $testRunParams.ExtensionId = $extensionId
        }

        if ($appName) {
            $testRunParams.AppName = $appName
        }

        if ($resultsFilePath) {
            $testRunParams.ResultsFilePath = if ($appendToResults) { $tempResultsFilePath } else { $resultsFilePath }
            $testRunParams.SaveResultFile = $true
        }

        # Forward optional pipeline parameters
        if ($parameters.disabledTests) {
            $testRunParams.DisabledTests = $parameters.disabledTests
        }
        if ($parameters.testCodeunitRange) {
            $testRunParams.TestCodeunitsRange = $parameters.testCodeunitRange
        }
        elseif ($parameters.testCodeunit -and $parameters.testCodeunit -ne "*") {
            $testRunParams.TestCodeunitsRange = $parameters.testCodeunit
        }
        if ($parameters.testFunction -and $parameters.testFunction -ne "*") {
            $testRunParams.TestProcedureRange = $parameters.testFunction
        }
        if ($parameters.requiredTestIsolation) {
            $testRunParams.RequiredTestIsolation = $parameters.requiredTestIsolation
        }
        if ($parameters.testType) {
            $testRunParams.TestType = $parameters.testType
        }
        if ($parameters.testRunnerCodeunitId) {
            # Map BCApps test runner codeunit IDs to Run-AlTests TestIsolation values
            # 130450 = Codeunit isolation (default), 130451 = Disabled isolation
            $testRunParams.TestIsolation = if ($parameters.testRunnerCodeunitId -eq "130451") { "Disabled" } else { "Codeunit" }
        }

        Run-AlTests @testRunParams

        # Determine which file to check for this app's results
        $checkResultsFile = if ($appendToResults) { $tempResultsFilePath } else { $resultsFilePath }
        $testsPassed = $true

        if ($checkResultsFile -and (Test-Path $checkResultsFile)) {
            # Parse results to determine pass/fail
            try {
                [xml]$testResults = Get-Content $checkResultsFile -Encoding UTF8
                if ($testResults.testsuites) {
                    $failures = 0; $errors = 0
                    if ($testResults.testsuites.testsuite) {
                        foreach ($ts in $testResults.testsuites.testsuite) {
                            if ($ts.failures) { $failures += [int]$ts.failures }
                            if ($ts.errors) { $errors += [int]$ts.errors }
                        }
                    }
                    $testsPassed = ($failures -eq 0 -and $errors -eq 0)
                }
                elseif ($testResults.assemblies) {
                    $failed = if ($testResults.assemblies.assembly.failed) { [int]$testResults.assemblies.assembly.failed } else { 0 }
                    $testsPassed = ($failed -eq 0)
                }
            }
            catch {
                Write-Host "Warning: Could not parse test results file: $_"
            }

            # Merge this app's results into the consolidated file if append mode
            if ($appendToResults) {
                if (-not (Test-Path $resultsFilePath)) {
                    Copy-Item -Path $tempResultsFilePath -Destination $resultsFilePath
                }
                else {
                    try {
                        [xml]$source = Get-Content $tempResultsFilePath -Encoding UTF8
                        [xml]$target = Get-Content $resultsFilePath -Encoding UTF8
                        $rootElement = if ($resultsFormat -eq 'JUnit') { 'testsuites' } else { 'assemblies' }
                        foreach ($node in $source.$rootElement.ChildNodes) {
                            if ($node.NodeType -eq 'Element') {
                                $imported = $target.ImportNode($node, $true)
                                $target.$rootElement.AppendChild($imported) | Out-Null
                            }
                        }
                        $target.Save($resultsFilePath)
                    }
                    catch {
                        Write-Host "Warning: Could not merge test results, copying instead: $_"
                        Copy-Item -Path $tempResultsFilePath -Destination $resultsFilePath -Force
                    }
                }
                Remove-Item $tempResultsFilePath -Force -ErrorAction SilentlyContinue
            }
        }

        return $testsPassed
    }.GetNewClosure()
}
