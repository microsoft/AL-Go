<#
.SYNOPSIS
    Helper module for the RunTests action.
.DESCRIPTION
    Contains the logic for running the normal tests (testFolders) of an AL-Go project against a
    build container that was created and kept alive by the RunPipeline action. Kept in a module
    so the logic can be unit tested independently of the action entry script.

    By default the tests are run through the AlTool (`al runtests`) runner in AlToolTestRunner.psm1.
    A RunTestsInBcContainer override script, when supplied, replaces that default with the
    BcContainerHelper test runner (this is how, for example, BCApps supplies its own runner).
#>

Import-Module (Join-Path $PSScriptRoot 'AlToolTestRunner.psm1' -Resolve) -DisableNameChecking -Force

function Get-TestAppsToRun {
    <#
    .SYNOPSIS
        Determines the set of test app files to run tests in.
    .DESCRIPTION
        Collects the test apps compiled for the project (found in the build artifacts TestApps
        folder) and, when runTestsInAllInstalledTestApps is enabled, the test apps installed from
        previous jobs (listed in installTestAppsJson). Test apps wrapped in parentheses are
        unwrapped (matching Run-AlPipeline semantics where such apps are otherwise not tested).
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

    $testAppOutputFolder = Join-Path $projectPath ".buildartifacts\TestApps"

    $testApps = @()
    if (Test-Path $testAppOutputFolder) {
        $testApps += @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }

    if ($settings.runTestsInAllInstalledTestApps -and $installTestAppsJson -and (Test-Path $installTestAppsJson)) {
        try {
            $installedTestApps = @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)
        }
        catch {
            throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
        }
        $testApps += @($installedTestApps | ForEach-Object { $_.TrimStart("(").TrimEnd(")") } | Where-Object { $_ -and (Test-Path $_) })
    }

    return @($testApps | Select-Object -Unique)
}

function Invoke-AlGoTestRun {
    <#
    .SYNOPSIS
        Runs the normal tests for an AL-Go project against a kept-alive build container.
    .DESCRIPTION
        Runs tests in each test app against the given container and writes the results to
        testResultsFile in JUnit format. Honors the treatTestFailuresAsWarnings setting. By default
        the tests are run through the AlTool (`al runtests`) runner. When a RunTestsInBcContainer
        override script is provided, it is used instead of the built-in AlTool runner.
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

    $testApps = Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installTestAppsJson
    if (@($testApps).Count -eq 0) {
        Write-Host "No test apps found to run tests in. Skipping test execution."
        return
    }

    Write-Host "Running tests against container '$containerName'"

    $testResultsFile = Join-Path $projectPath "TestResults.xml"
    if (Test-Path $testResultsFile) {
        Remove-Item $testResultsFile -Force
    }

    # Test failures surface as warnings when treatTestFailuresAsWarnings is set, otherwise as errors.
    $gitHubActionsSeverity = if ($settings.treatTestFailuresAsWarnings) { 'warning' } else { 'error' }

    $allTestsPassed = $true
    Push-Location $projectPath
    try {
        foreach ($testApp in $testApps) {
            $appJson = Get-AppJsonFromAppFile -appFile $testApp
            Write-Host "Running tests in $($appJson.name) ($($appJson.id))"

            $runTestsParams = @{
                "containerName"           = $containerName
                "credential"              = $credential
                "companyName"             = $settings.companyName
                "extensionId"             = $appJson.id
                "appName"                 = $appJson.name
                "JUnitResultFileName"     = $testResultsFile
                "AppendToJUnitResultFile" = $true
                "detailed"                = $true
                "GitHubActions"           = $gitHubActionsSeverity
                "returnTrueIfAllPassed"   = $true
            }

            if ($runTestsOverride) {
                $passed = & $runTestsOverride -parameters $runTestsParams
            }
            else {
                $passed = Invoke-AlToolTestRun -Parameters $runTestsParams
            }

            if (-not $passed) {
                $allTestsPassed = $false
            }
        }
    }
    finally {
        Pop-Location
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

Export-ModuleMember -Function Invoke-AlGoTestRun, Get-TestAppsToRun
