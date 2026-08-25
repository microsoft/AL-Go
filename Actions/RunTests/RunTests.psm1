<#
.SYNOPSIS
    Helper module for the RunTests action.
.DESCRIPTION
    Selects and runs normal test apps against the kept-alive build container. AlTool is the default
    executor; a RunTestsInBcContainer override can replace it.
#>

Import-Module (Join-Path $PSScriptRoot 'AlToolTestRunner.psm1' -Resolve) -DisableNameChecking -Force

function Get-TestAppsToRun {
    <#
    .SYNOPSIS
        Determines the selected test apps and their validated metadata.
    .DESCRIPTION
        Selects compiled apps matching normal testFolders and excludes BCPT-only apps. When
        runTestsInAllInstalledTestApps is enabled, installed test apps are included independently.
        Parentheses around installed app paths are removed to match RunPipeline behavior. Returns
        each selected app as a record containing Path, Id, and Name.
    .PARAMETER settings
        The (analyzed) AL-Go settings hashtable.
    .PARAMETER projectPath
        The full path to the project folder.
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
    $selectedAppPaths = @{}
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
        $selectedCompiledAppIds = @{}
        foreach ($compiledApp in @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -File -ErrorAction Stop | Sort-Object FullName)) {
            try {
                $compiledAppJson = Get-AppJsonFromAppFile -appFile $compiledApp.FullName
                $compiledAppId = "$($compiledAppJson.id)"
            }
            catch {
                throw "Failed to read compiled test app metadata from '$($compiledApp.FullName)'. Error: $($_.Exception.Message)"
            }

            if ($normalTestAppIds.ContainsKey($compiledAppId) -and -not $selectedCompiledAppIds.ContainsKey($compiledAppId)) {
                $compiledAppName = "$($compiledAppJson.name)"
                if ([string]::IsNullOrWhiteSpace($compiledAppName)) {
                    throw "Failed to read compiled test app metadata from '$($compiledApp.FullName)'. Error: The compiled app metadata does not contain an app name."
                }
                $testApps += [PSCustomObject]@{
                    Path = $compiledApp.FullName
                    Id   = $compiledAppId
                    Name = $compiledAppName
                }
                $selectedCompiledAppIds[$compiledAppId] = $true
                $selectedAppPaths[$compiledApp.FullName] = $true
            }
        }
    }

    if ($settings.runTestsInAllInstalledTestApps -and $installTestAppsJson) {
        try {
            $installedTestApps = Get-Content -Path $installTestAppsJson -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
        foreach ($installedTestApp in @($installedTestApps)) {
            $installedTestAppPath = "$installedTestApp".TrimStart("(").TrimEnd(")")
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
            if (-not $selectedAppPaths.ContainsKey($installedTestAppPath)) {
                $testApps += [PSCustomObject]@{
                    Path = $installedTestAppPath
                    Id   = $installedAppId
                    Name = $installedAppName
                }
                $selectedAppPaths[$installedTestAppPath] = $true
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
        Runs each selected test app with AlTool or a RunTestsInBcContainer override. Preserves
        TestResults.xml for AnalyzeTests, copies produced results to .buildartifacts, and refreshes
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
    #>
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $containerName,
        [System.Management.Automation.PSCredential] $credential,
        [string] $installTestAppsJson = '',
        [scriptblock] $runTestsOverride = $null
    )

    try {
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

        if (-not $runTestsOverride) {
            Install-AlTool | Out-Null
        }

        # Test failures surface as warnings when treatTestFailuresAsWarnings is set, otherwise as errors.
        $gitHubActionsSeverity = if ($settings.treatTestFailuresAsWarnings) { 'warning' } else { 'error' }

        $allTestsPassed = $true
        $testRunError = $null
        Push-Location $projectPath
        try {
            foreach ($testApp in $testApps) {
                Write-Host "Running tests in $($testApp.Name) ($($testApp.Id))"
                $disabledTests = @(Get-DisabledTestsForApp -settings $settings -projectPath $projectPath -appId "$($testApp.Id)")

                if ($runTestsOverride) {
                    $runTestsParams = @{
                        "containerName"           = $containerName
                        "credential"              = $credential
                        "companyName"             = $settings.companyName
                        "extensionId"             = $testApp.Id
                        "appName"                 = $testApp.Name
                        "disabledTests"           = $disabledTests
                        "JUnitResultFileName"     = $testResultsFile
                        "AppendToJUnitResultFile" = $true
                        "detailed"                = $true
                        "GitHubActions"           = $gitHubActionsSeverity
                        "returnTrueIfAllPassed"   = $true
                    }
                    $passed = & $runTestsOverride -parameters $runTestsParams
                }
                else {
                    $passed = Invoke-AlToolTestRun `
                        -ContainerName $containerName `
                        -Credential $credential `
                        -ExtensionId "$($testApp.Id)" `
                        -AppName "$($testApp.Name)" `
                        -CompanyName "$($settings.companyName)" `
                        -Tenant "default" `
                        -DisabledTests @($disabledTests) `
                        -JUnitResultFileName $testResultsFile
                }

                if (-not $passed) {
                    $allTestsPassed = $false
                }
            }
        }
        catch {
            $testRunError = $_
        }
        finally {
            Pop-Location
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
