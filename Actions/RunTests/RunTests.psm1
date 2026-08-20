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
        Determines the set of test app files to run tests in.
    .DESCRIPTION
        Selects compiled apps matching normal testFolders and excludes BCPT-only apps. When
        runTestsInAllInstalledTestApps is enabled, installed test apps are included independently.
        Parentheses around installed app paths are removed to match RunPipeline behavior.
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
    $normalTestAppIds = @{}
    if ($settings.ContainsKey("testFolders")) {
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
    }

    if (Test-Path $testAppOutputFolder) {
        $selectedCompiledAppIds = @{}
        foreach ($compiledApp in @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -File -ErrorAction Stop | Sort-Object FullName)) {
            try {
                $compiledAppJson = Get-AppJsonFromAppFile -appFile $compiledApp.FullName
                $compiledAppId = "$($compiledAppJson.id)"
                if ([string]::IsNullOrWhiteSpace($compiledAppId)) {
                    throw "The compiled app metadata does not contain an app ID."
                }
            }
            catch {
                throw "Failed to read compiled test app metadata from '$($compiledApp.FullName)'. Error: $($_.Exception.Message)"
            }

            if ($normalTestAppIds.ContainsKey($compiledAppId) -and -not $selectedCompiledAppIds.ContainsKey($compiledAppId)) {
                $testApps += $compiledApp.FullName
                $selectedCompiledAppIds[$compiledAppId] = $true
            }
        }
    }

    if ($settings.runTestsInAllInstalledTestApps -and $installTestAppsJson -and (Test-Path $installTestAppsJson)) {
        try {
            $installedTestApps = Get-Content -Path $installTestAppsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
        $testApps += @($installedTestApps | ForEach-Object { "$_".TrimStart("(").TrimEnd(")") } | Where-Object { $_ -and (Test-Path $_) })
    }

    return @($testApps | Select-Object -Unique)
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
    if ($settings.ContainsKey("testFolders")) {
        foreach ($testFolder in @($settings.testFolders)) {
            $testFolderPath = Join-Path $projectPath $testFolder
            $appJsonPath = Join-Path $testFolderPath "app.json"
            if (-not (Test-Path $appJsonPath -PathType Leaf)) {
                continue
            }

            $testAppJson = Get-Content -Path $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -recurse
            if ("$($testAppJson.id)" -eq $appId) {
                $disabledTestFiles += @(Get-ChildItem -Path $testFolderPath -Filter "disabledTests.json" -File -Recurse | ForEach-Object { $_.FullName })
            }
        }
    }

    $disabledTestFiles += @(Get-ChildItem -Path $projectPath -Filter "$appId.disabledTests.json" -File -Recurse | ForEach-Object { $_.FullName })

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
        ContainerEventLog.evtx after every outcome. Event-log errors do not replace an existing test
        error.
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

    $testRunFailed = $false
    try {
        $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installTestAppsJson
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
        Push-Location $projectPath
        try {
            foreach ($testApp in $testApps) {
                $appJson = Get-AppJsonFromAppFile -appFile $testApp
                Write-Host "Running tests in $($appJson.name) ($($appJson.id))"
                $disabledTests = @(Get-DisabledTestsForApp -settings $settings -projectPath $projectPath -appId "$($appJson.id)")

                if ($runTestsOverride) {
                    $runTestsParams = @{
                        "containerName"           = $containerName
                        "credential"              = $credential
                        "companyName"             = $settings.companyName
                        "extensionId"             = $appJson.id
                        "appName"                 = $appJson.name
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
                    $alToolTestRunParams = @{
                        ContainerName       = $containerName
                        Credential          = $credential
                        ExtensionId         = "$($appJson.id)"
                        AppName             = "$($appJson.name)"
                        CompanyName         = "$($settings.companyName)"
                        Tenant              = "default"
                        DisabledTests       = @($disabledTests)
                        TestType            = ""
                        JUnitResultFileName = $testResultsFile
                    }
                    $passed = Invoke-AlToolTestRun @alToolTestRunParams
                }

                if (-not $passed) {
                    $allTestsPassed = $false
                }
            }
        }
        finally {
            Pop-Location
        }

        Copy-TestResultsToBuildArtifacts -projectPath $projectPath -testResultsFile $testResultsFile

        if (-not $allTestsPassed) {
            if ($settings.treatTestFailuresAsWarnings) {
                OutputWarning -message "There are test failures, but they are treated as warnings (treatTestFailuresAsWarnings is set)."
            }
            else {
                throw "There are test failures."
            }
        }
    }
    catch {
        $testRunFailed = $true
        throw
    }
    finally {
        try {
            Export-AlGoContainerEventLog `
                -projectPath $projectPath `
                -containerName $containerName
        }
        catch {
            if ($testRunFailed) {
                OutputWarning -message "Tests failed and the post-test container event log could not be captured. $($_.Exception.Message)"
            }
            else {
                throw
            }
        }
    }
}

Export-ModuleMember -Function Invoke-AlGoTestRun, Get-TestAppsToRun
