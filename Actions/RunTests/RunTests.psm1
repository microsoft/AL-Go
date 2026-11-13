<#
.SYNOPSIS
    Helper module for the RunTests action.
.DESCRIPTION
    Selects and runs normal test apps against the kept-alive build container. AlTool is the default
    executor. RunTestsInBcContainer overrides retain their historical per-app execution and receive
    an app-specific code coverage context when coverage is enabled.
#>

Import-Module (Join-Path $PSScriptRoot 'AlToolTestRunner.psm1' -Resolve) -DisableNameChecking -Force
Import-Module (Join-Path $PSScriptRoot 'CodeCoverageCoordinator.psm1' -Resolve) `
    -DisableNameChecking -Force

function Get-TestAppsToRun {
    <#
    .SYNOPSIS
        Determines the selected test apps and their validated metadata.
    .DESCRIPTION
        Selects compiled apps matching normal testFolders and excludes BCPT-only apps. Unwrapped
        installed test app paths are always included. Parenthesized paths are included and unwrapped
        only when runTestsInAllInstalledTestApps is enabled. Returns each selected app as a record
        containing Path, Id, and Name.
    .PARAMETER settings
        The (analyzed) AL-Go settings hashtable.
    .PARAMETER projectPath
        The full path to the project folder.
    .PARAMETER baseFolder
        The full path to the repository root.
    .PARAMETER project
        Repository-relative AL-Go project path.
    .PARAMETER projectName
        Project display name.
    .PARAMETER buildMode
        Build mode used for this project run.
    .PARAMETER installTestAppsJson
        Path to a JSON file with the list of installed test apps.
    #>
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $installTestAppsJson = ''
    )

    $testAppOutputFolder = Join-Path (Join-Path $projectPath ".buildartifacts") "TestApps"

    $testApps = @()
    $selectedAppIds = @{}
    $normalTestAppIds = @{}
    foreach ($testFolder in @($settings.testFolders)) {
        $appJsonPath = Join-Path (Join-Path $projectPath $testFolder) "app.json"
        try {
            $sourceAppJson = Get-Content -Path $appJsonPath -Raw -Encoding UTF8 -ErrorAction Stop |
                ConvertFrom-Json |
                ConvertTo-HashTable -recurse
            $sourceAppId = "$($sourceAppJson.id)"
            if ([string]::IsNullOrWhiteSpace($sourceAppId)) {
                throw "The app.json file does not contain an app ID."
            }
        }
        catch {
            throw "Failed to read normal test app metadata from '$appJsonPath'. Error: $($_.Exception.Message)"
        }
        $normalTestAppIds[$sourceAppId] = $true
    }

    if (Test-Path $testAppOutputFolder) {
        foreach ($compiledApp in @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -File -ErrorAction Stop | Sort-Object FullName)) {
            try {
                $compiledAppJson = Get-AppJsonFromAppFile -appFile $compiledApp.FullName
                $compiledAppId = "$($compiledAppJson.id)"
            }
            catch {
                throw "Failed to read compiled test app metadata from '$($compiledApp.FullName)'. Error: $($_.Exception.Message)"
            }

            if ($normalTestAppIds.ContainsKey($compiledAppId) -and -not $selectedAppIds.ContainsKey($compiledAppId)) {
                $compiledAppName = "$($compiledAppJson.name)"
                if ([string]::IsNullOrWhiteSpace($compiledAppName)) {
                    throw "Failed to read compiled test app metadata from '$($compiledApp.FullName)'. Error: The compiled app metadata does not contain an app name."
                }
                $testApps += [PSCustomObject]@{
                    Path = $compiledApp.FullName
                    Id   = $compiledAppId
                    Name = $compiledAppName
                }
                $selectedAppIds[$compiledAppId] = $true
            }
        }
    }

    if ($installTestAppsJson) {
        try {
            $installedTestApps = Get-Content -Path $installTestAppsJson -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
        foreach ($installedTestApp in @($installedTestApps)) {
            $installedTestAppValue = "$installedTestApp"
            $isParenthesized = $installedTestAppValue.StartsWith("(") -and $installedTestAppValue.EndsWith(")")
            if ($isParenthesized -and -not $settings.runTestsInAllInstalledTestApps) {
                continue
            }
            $installedTestAppPath = if ($isParenthesized) {
                $installedTestAppValue.Substring(1, $installedTestAppValue.Length - 2)
            }
            else {
                $installedTestAppValue
            }
            if ([string]::IsNullOrWhiteSpace($installedTestAppPath)) {
                throw "The installed test app list '$installTestAppsJson' contains a blank path."
            }
            try {
                $installedAppJson = Get-AppJsonFromAppFile -appFile $installedTestAppPath
                $installedAppId = "$($installedAppJson.id)"
                $installedAppName = "$($installedAppJson.name)"
                if ([string]::IsNullOrWhiteSpace($installedAppId) -or [string]::IsNullOrWhiteSpace($installedAppName)) {
                    throw "The installed app metadata does not contain an app ID and name."
                }
            }
            catch {
                throw "Failed to read installed test app metadata from '$installedTestAppPath'. Error: $($_.Exception.Message)"
            }
            if (-not $selectedAppIds.ContainsKey($installedAppId)) {
                $testApps += [PSCustomObject]@{
                    Path = $installedTestAppPath
                    Id   = $installedAppId
                    Name = $installedAppName
                }
                $selectedAppIds[$installedAppId] = $true
            }
        }
    }

    return @($testApps)
}

function Get-DisabledTestsForApp {
    <#
    .SYNOPSIS
        Gets the disabled tests configured for a test app.
    .DESCRIPTION
        Loads disabledTests.json files recursively under the matching test folder and project-wide
        <appId>.disabledTests.json files.
    .PARAMETER settings
        The analyzed AL-Go settings hashtable.
    .PARAMETER projectPath
        The full path to the project folder.
    .PARAMETER appId
        The ID of the test app.
    #>
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $appId
    )

    $disabledTestFiles = @()
    foreach ($testFolder in @($settings.testFolders)) {
        $testFolderPath = Join-Path $projectPath $testFolder
        $appJsonPath = Join-Path $testFolderPath "app.json"
        if (-not (Test-Path $appJsonPath -PathType Leaf)) {
            continue
        }

        $testAppJson = Get-Content -Path $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -recurse
        if ("$($testAppJson.id)" -eq $appId) {
            $disabledTestFiles += @(Get-ChildItem -LiteralPath $testFolderPath -Filter "disabledTests.json" -File -Recurse -Force | ForEach-Object { $_.FullName })
        }
    }

    $disabledTestFiles += @(Get-ChildItem -LiteralPath $projectPath -Filter "$appId.disabledTests.json" -File -Recurse -Force | ForEach-Object { $_.FullName })

    $disabledTests = @()
    foreach ($disabledTestFile in @($disabledTestFiles | Sort-Object -Unique)) {
        try {
            $disabledTestsJson = Get-Content -Path $disabledTestFile -Raw -Encoding UTF8
            $parsedDisabledTests = $disabledTestsJson | ConvertFrom-Json
            foreach ($disabledTest in $parsedDisabledTests) {
                $disabledTests += @(ConvertTo-HashTable -object $disabledTest -recurse)
            }
        }
        catch {
            throw "Failed to parse disabled tests JSON file '$disabledTestFile'. Error: $($_.Exception.Message)"
        }
    }

    return @($disabledTests)
}

function Copy-TestResultsToBuildArtifacts {
    <#
    .SYNOPSIS
        Copies an existing test result file to the project build artifacts folder.
    .DESCRIPTION
        Preserves the project result for AnalyzeTests and creates an artifact copy only when a result
        exists.
    .PARAMETER projectPath
        The full path to the project folder.
    .PARAMETER testResultsFile
        The canonical test result file in the project root.
    #>
    Param(
        [string] $projectPath,
        [string] $testResultsFile
    )

    $buildArtifactsFolder = Join-Path $projectPath ".buildartifacts"
    $artifactTestResultsFile = Join-Path $buildArtifactsFolder "TestResults.xml"
    try {
        if (-not (Test-Path -Path $testResultsFile -PathType Leaf -ErrorAction Stop)) {
            return
        }
        New-Item -Path $buildArtifactsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path $testResultsFile -Destination $artifactTestResultsFile -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to copy test results from '$testResultsFile' to '$artifactTestResultsFile'. Error: $($_.Exception.Message)"
    }
}

function Export-AlGoContainerEventLog {
    <#
    .SYNOPSIS
        Exports the kept-alive container event log to the project folder.
    .DESCRIPTION
        Replaces ContainerEventLog.evtx only after a readable export is available, preserving an
        existing diagnostic when export fails.
    .PARAMETER projectPath
        The full path to the project folder.
    .PARAMETER containerName
        The name of the kept-alive build container.
    #>
    Param(
        [string] $projectPath,
        [string] $containerName
    )

    $containerEventLogFile = Join-Path $projectPath "ContainerEventLog.evtx"
    try {
        $exportedEventLogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
        if ([string]::IsNullOrWhiteSpace("$exportedEventLogFile") -or -not (Test-Path -Path $exportedEventLogFile -PathType Leaf -ErrorAction Stop)) {
            throw "Get-BcContainerEventLog did not return a readable event log file."
        }

        Copy-Item -Path $exportedEventLogFile -Destination $containerEventLogFile -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to capture event log from container '$containerName' to '$containerEventLogFile'. Error: $($_.Exception.Message)"
    }
}

function Invoke-AlGoTestRun {
    <#
    .SYNOPSIS
        Runs the normal tests for an AL-Go project against a kept-alive build container.
    .DESCRIPTION
        Runs each selected test app with AlTool or the original RunTestsInBcContainer override.
        When coverage is supported, coverage-specific values are added to the existing per-app
        override parameters. AL-Go owns coverage validation and status finalization.
        Preserves TestResults.xml for AnalyzeTests, copies results to .buildartifacts, and refreshes
        ContainerEventLog.evtx after every outcome. Event-log capture failures are warnings and do
        not change the test outcome.
    .PARAMETER settings
        The (analyzed) AL-Go settings hashtable.
    .PARAMETER projectPath
        The full path to the project folder.
    .PARAMETER containerName
        The name of the build container to run the tests against.
    .PARAMETER credential
        The credential used to connect to the build container.
    .PARAMETER installTestAppsJson
        Path to a JSON file with the list of installed test apps.
    .PARAMETER runTestsOverride
        Optional scriptblock overriding the built-in AlTool test runner (RunTestsInBcContainer).
    .PARAMETER alToolPath
        Full path to the AlTool executable used by the built-in runner.
    .PARAMETER getAlToolPath
        Shared resolver used to discover or install AlTool when alToolPath is omitted.
    .PARAMETER analyzeRepo
        Caller-scoped AnalyzeRepo callback used to resolve direct projectsToTest source roots.
    .PARAMETER containerPlatformVersion
        Actual build container platform version exported by RunPipeline.
    .PARAMETER containerPlatformVersionReason
        Non-sensitive reason supplied when RunPipeline could not determine the platform version.
    #>
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $baseFolder = "",
        [string] $project = ".",
        [string] $projectName = "",
        [string] $buildMode = "Default",
        [string] $containerName,
        [System.Management.Automation.PSCredential] $credential,
        [string] $installTestAppsJson = '',
        [scriptblock] $runTestsOverride = $null,
        [string] $alToolPath = '',
        [scriptblock] $getAlToolPath = $null,
        [scriptblock] $analyzeRepo = $null,
        [AllowEmptyString()][string] $containerPlatformVersion = $env:containerPlatformVersion,
        [AllowEmptyString()][string] $containerPlatformVersionReason = $env:containerPlatformVersionReason
    )

    try {
        if (@($settings.restoreDatabases | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }).Count -gt 0) {
            Write-Host "::Warning::restoreDatabases is configured, but database restore is not currently supported by the separate RunTests action and will not be performed."
        }

        $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath `
            -installTestAppsJson $installTestAppsJson
        if (@($testApps).Count -eq 0) {
            Write-Host "No test apps found to run tests in. Skipping test execution."
            return
        }

        Write-Host "Running tests against container '$containerName'"

        $testResultsFile = Join-Path $projectPath "TestResults.xml"
        $artifactTestResultsFile = Join-Path (Join-Path $projectPath ".buildartifacts") "TestResults.xml"
        foreach ($previousResultFile in @($testResultsFile, $artifactTestResultsFile)) {
            if (Test-Path $previousResultFile) {
                Remove-Item $previousResultFile -Force
            }
        }

        # Test failures surface as warnings when treatTestFailuresAsWarnings is set, otherwise as errors.
        $gitHubActionsSeverity = if ($settings.treatTestFailuresAsWarnings) { 'warning' } else { 'error' }
        $testType = if ($settings.ContainsKey("useSeparateTestAction")) {
            "$($settings.useSeparateTestAction.testType)"
        }
        else {
            ""
        }
        $coverageRequested = $settings.ContainsKey("useSeparateTestAction") -and
            [bool]$settings.useSeparateTestAction.codeCoverageEnabled
        $coverageSession = $null
        if ($coverageRequested) {
            $coverageCapability = Get-AlGoCodeCoverageCapability `
                -platformVersion $containerPlatformVersion `
                -platformVersionReason $containerPlatformVersionReason
            if ($runTestsOverride -and $coverageCapability.Supported -and
                [string]::IsNullOrWhiteSpace($alToolPath)) {
                if (-not $getAlToolPath) {
                    throw "A coverage-aware RunTestsInBcContainer override requires an AlTool path or path resolver."
                }
                $alToolPath = & $getAlToolPath
            }
            $coverageSession = New-AlGoCodeCoverageSession -settings $settings `
                -projectPath $projectPath -baseFolder $baseFolder -project $project `
                -projectName $projectName -buildMode $buildMode `
                -testApps $testApps -analyzeRepo $analyzeRepo `
                -capability $coverageCapability
            if ($coverageSession.Supported) {
                Write-Host "Code coverage enabled: mode=line, formats=$($coverageSession.Formats -join ','), container platform $containerPlatformVersion."
                Write-Host "Code coverage artifacts will be retained under '$($coverageSession.RootPath)'."
            }
            else {
                OutputWarning -message "Code coverage requires container platform 30.0.56026.0 or later. $($coverageCapability.Reason) Tests will continue without coverage."
            }
        }

        if (-not $runTestsOverride -and [string]::IsNullOrWhiteSpace($alToolPath)) {
            if (-not $getAlToolPath) {
                throw "The built-in AlTool runner requires an AlTool path or path resolver."
            }
            $alToolPath = & $getAlToolPath
        }

        $allTestsPassed = $true
        $testRunError = $null
        $currentCoverageRun = $null
        $coverageInvocationActive = $false
        Push-Location $projectPath
        try {
            $testAppIndex = 0
            foreach ($testApp in $testApps) {
                Write-Host "Running tests in $($testApp.Name) ($($testApp.Id))"
                $disabledTests = @(Get-DisabledTestsForApp -settings $settings `
                    -projectPath $projectPath -appId "$($testApp.Id)")
                $currentCoverageRun = if ($coverageSession) {
                    $coverageSession.Runs[$testAppIndex]
                }
                else {
                    $null
                }
                $coverageInvocationActive = $coverageSession -and $coverageSession.Supported
                $coverageIsComplete = $null
                $coverageOutputPath = if ($coverageInvocationActive) {
                    [System.IO.Path]::GetFullPath((
                            Join-Path $coverageSession.RootPath "$($currentCoverageRun.AppId)"
                        ))
                }
                else {
                    ""
                }
                $coverageSourceRoots = if ($coverageInvocationActive) {
                    @($coverageSession.SourceRootRecords | ForEach-Object { "$($_.Path)" })
                }
                else {
                    @()
                }
                $coverageApplicationIds = if ($coverageInvocationActive) {
                    @($coverageSession.SourceRootRecords |
                        Where-Object {
                            "$($_.Kind)" -eq "app" -and
                            -not [string]::IsNullOrWhiteSpace("$($_.AppId)")
                        } |
                        ForEach-Object { "$($_.AppId)".ToLowerInvariant() } |
                        Sort-Object -Unique)
                }
                else {
                    @()
                }
                if ($coverageInvocationActive) {
                    $currentCoverageRun.StartedAtUtc = [DateTime]::UtcNow
                }

                if ($runTestsOverride) {
                    $runTestsParams = @{
                        "containerName" = $containerName
                        "credential" = $credential
                        "companyName" = $settings.companyName
                        "extensionId" = $testApp.Id
                        "appName" = $testApp.Name
                        "disabledTests" = $disabledTests
                        "JUnitResultFileName" = $testResultsFile
                        "AppendToJUnitResultFile" = $true
                        "detailed" = $true
                        "GitHubActions" = $gitHubActionsSeverity
                        "returnTrueIfAllPassed" = $true
                    }
                    if ($coverageInvocationActive -or -not [string]::IsNullOrWhiteSpace($testType)) {
                        $runTestsParams["testType"] = $testType
                    }
                    if ($coverageInvocationActive) {
                        $runTestsParams["codeCoverageFormats"] = @($coverageSession.Formats)
                        $runTestsParams["codeCoverageSourceRoots"] = @($coverageSourceRoots)
                        $runTestsParams["codeCoverageApplicationIds"] = @($coverageApplicationIds)
                        $runTestsParams["codeCoverageOutputPath"] = $coverageOutputPath
                        $runTestsParams["codeCoverageAlToolModulePath"] = (
                            Join-Path $PSScriptRoot "AlToolTestRunner.psm1"
                        )
                        $runTestsParams["codeCoverageAlToolPath"] = $alToolPath
                        $runTestsParams["codeCoverageIsComplete"] = $null
                    }
                    $passed = & $runTestsOverride -parameters $runTestsParams
                    if ($coverageSession -and $passed -isnot [bool]) {
                        throw "The coverage-aware RunTestsInBcContainer override must return a Boolean test result."
                    }
                    if ($coverageInvocationActive) {
                        $coverageIsComplete = $runTestsParams.codeCoverageIsComplete
                    }
                }
                else {
                    $alToolParameters = @{
                        ContainerName = $containerName
                        Credential = $credential
                        ExtensionId = "$($testApp.Id)"
                        AppName = "$($testApp.Name)"
                        CompanyName = "$($settings.companyName)"
                        Tenant = "default"
                        TestType = $testType
                        DisabledTests = @($disabledTests)
                        AlToolPath = $alToolPath
                        JUnitResultFileName = $testResultsFile
                    }
                    if ($coverageInvocationActive) {
                        $alToolParameters.CoverageOutputPath = $coverageOutputPath
                        $alToolParameters.CoverageFormats = @($coverageSession.Formats)
                        $alToolParameters.CoverageSourceRoots = @($coverageSourceRoots)
                        $alToolParameters.CoverageIsComplete = [ref] $coverageIsComplete
                    }
                    $passed = Invoke-AlToolTestRun @alToolParameters
                }

                if ($coverageSession -and $coverageSession.Supported) {
                    $coverageInvocationActive = $false
                    Complete-AlGoCodeCoverageRun -session $coverageSession `
                        -run $currentCoverageRun `
                        -coverageIsComplete $coverageIsComplete
                }
                $currentCoverageRun = $null
                $testAppIndex++
                if (-not $passed) {
                    $allTestsPassed = $false
                }
            }
        }
        catch {
            $caughtTestRunError = $_
            if ($coverageInvocationActive -and $currentCoverageRun) {
                try {
                    Complete-AlGoCodeCoverageRun -session $coverageSession `
                        -run $currentCoverageRun -executionFailed
                }
                catch {
                    OutputWarning -message "Failed to record the current code coverage run after test execution failed. $($_.Exception.Message)"
                }
            }
            $testRunError = $caughtTestRunError
        }
        finally {
            Pop-Location
        }
        if ($coverageSession) {
            try {
                Complete-AlGoCodeCoverageSession -session $coverageSession `
                    -suppressFailure:([bool]$testRunError)
            }
            catch {
                if ($testRunError) {
                    OutputWarning -message "Failed to finalize code coverage status after test execution failed. $($_.Exception.Message)"
                }
                else {
                    $testRunError = $_
                }
            }
        }

        try {
            Copy-TestResultsToBuildArtifacts -projectPath $projectPath -testResultsFile $testResultsFile
        }
        catch {
            if ($testRunError) {
                OutputWarning -message "The test run failed and produced test results could not be copied to build artifacts. $($_.Exception.Message)"
            }
            else {
                throw
            }
        }

        if ($testRunError) {
            throw $testRunError
        }

        if (-not $allTestsPassed) {
            if ($settings.treatTestFailuresAsWarnings) {
                OutputWarning -message "There are test failures, but they are treated as warnings (treatTestFailuresAsWarnings is set)."
            }
            else {
                throw "There are test failures."
            }
        }
    }
    finally {
        try {
            Export-AlGoContainerEventLog `
                -projectPath $projectPath `
                -containerName $containerName
        }
        catch {
            OutputWarning -message "The post-test container event log could not be captured. $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Invoke-AlGoTestRun, Get-TestAppsToRun
