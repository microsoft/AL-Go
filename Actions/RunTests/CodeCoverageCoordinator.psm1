$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregate.psm1" -Resolve) `
    -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
    -DisableNameChecking

$script:CodeCoverageMode = "line"

<#
.SYNOPSIS
    Resolves the ordered source roots used for coverage collection and analysis.
.DESCRIPTION
    Collects appFolders and testFolders that contain AL source files from the current project
    and direct projectsToTest targets. Rejects roots outside the repository, deduplicates paths,
    reads available app identity, and returns deterministic records.
.PARAMETER settings
    Analyzed settings for the current AL-Go project.
.PARAMETER projectPath
    Full path to the current AL-Go project.
.PARAMETER baseFolder
    Full repository root used for containment and repository-relative paths.
.PARAMETER analyzeRepo
    Callback used to analyze settings for direct projectsToTest targets.
.OUTPUTS
    Ordered hashtables containing absolute path, relative path, kind, app ID, and app name.
#>
function Resolve-CodeCoverageSourceRootData {
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $baseFolder = "",
        [scriptblock] $analyzeRepo = $null
    )

    if ([string]::IsNullOrWhiteSpace($baseFolder)) {
        $baseFolder = $projectPath
    }
    $repositoryRoot = [System.IO.Path]::GetFullPath($baseFolder).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $repositoryPrefix = $repositoryRoot + [System.IO.Path]::DirectorySeparatorChar
    $sourceRoots = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $addProjectRoots = {
        param(
            [hashtable] $projectSettings,
            [string] $sourceProjectPath
        )

        foreach ($folderSetting in @("appFolders", "testFolders")) {
            $kind = if ($folderSetting -eq "appFolders") { "app" } else { "test" }
            if (-not $projectSettings.ContainsKey($folderSetting)) {
                continue
            }
            foreach ($folder in @($projectSettings[$folderSetting])) {
                if ([string]::IsNullOrWhiteSpace("$folder")) {
                    continue
                }
                $folderPath = [System.IO.Path]::GetFullPath((Join-Path $sourceProjectPath "$folder"))
                if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                    continue
                }
                $resolvedPath = Resolve-Path -LiteralPath $folderPath
                $resolvedFullPath = [System.IO.Path]::GetFullPath($resolvedPath.ProviderPath)
                if (-not (Test-PathInsideRoot -Path $resolvedFullPath -Root $repositoryRoot)) {
                    throw "Code coverage source root '$resolvedFullPath' is outside the repository."
                }
                $alSourceFile = Get-ChildItem -LiteralPath $resolvedFullPath -Filter "*.al" `
                    -File -Recurse -ErrorAction Stop | Select-Object -First 1
                if (-not $alSourceFile) {
                    continue
                }
                if (-not $sourceRoots.ContainsKey($resolvedFullPath)) {
                    $relativePath = if ($resolvedFullPath.Equals($repositoryRoot, $comparison)) {
                        "."
                    }
                    else {
                        $resolvedFullPath.Substring($repositoryPrefix.Length).Replace('\', '/')
                    }
                    $appId = ""
                    $appName = [System.IO.Path]::GetFileName($resolvedFullPath.TrimEnd(
                            [System.IO.Path]::DirectorySeparatorChar,
                            [System.IO.Path]::AltDirectorySeparatorChar))
                    $appJsonPath = Join-Path $resolvedFullPath "app.json"
                    if (Test-Path -LiteralPath $appJsonPath -PathType Leaf) {
                        try {
                            $appJson = Get-Content -LiteralPath $appJsonPath -Raw -Encoding UTF8 |
                                ConvertFrom-Json | ConvertTo-HashTable -recurse
                            if ($appJson.ContainsKey("id")) {
                                $appId = "$($appJson.id)"
                            }
                            if ($appJson.ContainsKey("name") -and
                                -not [string]::IsNullOrWhiteSpace("$($appJson.name)")) {
                                $appName = "$($appJson.name)"
                            }
                        }
                        catch {
                            throw "Failed to read code coverage source root metadata from '$appJsonPath'. Error: $($_.Exception.Message)"
                        }
                    }
                    $sourceRoots.Add($resolvedFullPath, @{
                            Path = $resolvedFullPath
                            RelativePath = $relativePath
                            Kinds = @{}
                            AppId = $appId
                            AppName = $appName
                        })
                }
                $sourceRoots[$resolvedFullPath].Kinds[$kind] = $true
            }
        }
    }

    & $addProjectRoots -projectSettings $settings -sourceProjectPath $projectPath

    $visitedTargets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($settings.ContainsKey("projectsToTest")) {
        foreach ($targetProject in @($settings.projectsToTest)) {
            if ([string]::IsNullOrWhiteSpace("$targetProject")) {
                continue
            }
            $targetProjectPath = [System.IO.Path]::GetFullPath((Join-Path $baseFolder "$targetProject"))
            if (-not $visitedTargets.Add($targetProjectPath)) {
                continue
            }
            $targetSettings = ReadSettings -project "$targetProject" -baseFolder $baseFolder |
                ConvertTo-HashTable -recurse
            if (-not $analyzeRepo) {
                throw "Analyzing projectsToTest source roots requires the AnalyzeRepo callback."
            }
            $targetSettings = & $analyzeRepo -settings $targetSettings `
                -baseFolder $baseFolder -project "$targetProject"
            & $addProjectRoots -projectSettings $targetSettings -sourceProjectPath $targetProjectPath
        }
    }

    $sourceRootPaths = [string[]]@($sourceRoots.Keys)
    [System.Array]::Sort($sourceRootPaths, [System.StringComparer]::Ordinal)
    $result = @()
    foreach ($sourceRootPath in $sourceRootPaths) {
        $sourceRoot = $sourceRoots[$sourceRootPath]
        $kinds = @($sourceRoot.Kinds.Keys)
        $kind = if ($kinds.Count -eq 1) { "$($kinds[0])" } else { "unknown" }
        $result += @{
            Path = $sourceRootPath
            RelativePath = "$($sourceRoot.RelativePath)"
            Kind = $kind
            AppId = "$($sourceRoot.AppId)"
            AppName = "$($sourceRoot.AppName)"
        }
    }
    return @($result)
}

<#
.SYNOPSIS
    Converts internal source-root records to the portable status shape.
.PARAMETER sourceRootRecords
    Internal source-root records returned by Resolve-CodeCoverageSourceRootData.
.OUTPUTS
    Ordered hashtables containing path, kind, appId, and appName.
#>
function Get-CodeCoverageSourceRootDetails {
    Param([object[]] $sourceRootRecords)

    return @(
        foreach ($sourceRoot in $sourceRootRecords) {
            [ordered]@{
                path = "$($sourceRoot.RelativePath)"
                kind = "$($sourceRoot.Kind)"
                appId = "$($sourceRoot.AppId)"
                appName = "$($sourceRoot.AppName)"
            }
        }
    )
}

<#
.SYNOPSIS
    Returns the final coverage status path for a session.
.PARAMETER session
    AL-Go-owned code coverage session.
.OUTPUTS
    Absolute path to coverage-status.json.
#>
function Get-CodeCoverageStatusPath {
    Param([hashtable] $session)

    return Join-Path $session.RootPath "coverage-status.json"
}

<#
.SYNOPSIS
    Returns the published aggregate path for a session.
.PARAMETER session
    AL-Go-owned code coverage session.
.OUTPUTS
    Absolute path to coverage-aggregate.bin.gz.
#>
function Get-CodeCoverageAggregatePath {
    Param([hashtable] $session)

    return Join-Path $session.RootPath "coverage-aggregate.bin.gz"
}

<#
.SYNOPSIS
    Atomically writes the final AL-Go coverage status manifest.
.DESCRIPTION
    Serializes final run states, assessments, source-root metadata, and the optional fixed
    aggregate reference to a temporary file before moving it to coverage-status.json.
.PARAMETER session
    Finalized AL-Go-owned code coverage session.
.PARAMETER aggregate
    Optional aggregate result returned by the background compactor.
#>
function Write-CodeCoverageStatusInternal {
    Param(
        [hashtable] $session,
        [hashtable] $aggregate = $null
    )

    New-Item -Path $session.RootPath -ItemType Directory -Force | Out-Null
    $temporaryPath = Join-Path $session.RootPath "coverage-status.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $runs = @(
            foreach ($run in @($session.Runs)) {
                $runStatus = [ordered]@{
                    appId = "$($run.AppId)"
                    appName = "$($run.AppName)"
                    outputDirectory = "CodeCoverage/$($run.AppId)"
                    state = if ($session.Supported) { "$($run.State)" } else { "unsupported" }
                }
                if ($aggregate -and $run.State -in @("complete", "incomplete")) {
                    $runStatus["lineReasons"] = @($run.LineReasons)
                    $runStatus["notices"] = @($run.Notices)
                    $runStatus["lineGlobalUnsafe"] = [bool]$run.LineGlobalUnsafe
                    $runStatus["lineAffectedSources"] = @($run.LineAffectedSources)
                    $runStatus["excludedLineFacts"] = [int]$run.ExcludedLineFacts
                }
                $runStatus
            }
        )
        $status = [ordered]@{
            project = "$($session.Project)"
            projectName = "$($session.ProjectName)"
            buildMode = "$($session.BuildMode)"
            formats = @($session.Formats)
            sourceRoots = @($session.SourceRootRecords | ForEach-Object { "$($_.RelativePath)" })
            sourceRootDetails = @(Get-CodeCoverageSourceRootDetails $session.SourceRootRecords)
            runs = @($runs)
        }
        if ($aggregate) {
            $status["aggregate"] = "coverage-aggregate.bin.gz"
        }
        ConvertTo-Json -InputObject $status -Depth 6 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        [System.IO.File]::Move($temporaryPath, (Get-CodeCoverageStatusPath -session $session))
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Deletes raw BC JSON reports for successfully compacted runs.
.PARAMETER session
    Finalized AL-Go-owned code coverage session.
.OUTPUTS
    Total number of raw report bytes removed.
#>
function Remove-CodeCoverageRawReports {
    Param([hashtable] $session)

    $removedBytes = [long]0
    foreach ($run in @($session.Runs)) {
        if ($run.State -notin @("complete", "incomplete")) {
            continue
        }
        $reportPath = Join-Path $run.OutputPath "coverage.bc.json"
        if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
            $removedBytes += (Get-Item -LiteralPath $reportPath).Length
            Remove-Item -LiteralPath $reportPath -Force
        }
    }
    return $removedBytes
}

<#
.SYNOPSIS
    Validates the coverage handoff for one completed app run.
.DESCRIPTION
    Requires a Boolean completeness result and every requested fixed artifact. The compactor
    performs all BC JSON schema, line-mode, completeness, diagnostic, and line-fact validation.
.PARAMETER session
    AL-Go-owned code coverage session.
.PARAMETER run
    AL-Go-owned run record for the completed test app.
.PARAMETER rawComplete
    Completeness value returned by the built-in runner or custom override.
#>
function Test-CodeCoverageArtifacts {
    Param(
        [hashtable] $session,
        [hashtable] $run,
        $rawComplete
    )

    if ($rawComplete -isnot [bool]) {
        throw "The coverage-aware test runner did not report whether coverage is complete."
    }

    $expectedArtifacts = @{
        "bc-json" = "coverage.bc.json"
        "cobertura" = "coverage.cobertura.xml"
    }
    foreach ($coverageFormat in @($session.Formats)) {
        $artifactPath = Join-Path $run.OutputPath $expectedArtifacts[$coverageFormat]
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "The expected '$coverageFormat' coverage artifact '$artifactPath' was not created."
        }
    }

}

<#
.SYNOPSIS
    Determines whether the handed-off container platform supports code coverage.
.DESCRIPTION
    Code coverage requires container platform 30.0.56026.0 or later and PowerShell 7 for
    mandatory compaction. Missing capabilities are treated as unavailable.
.PARAMETER platformVersion
    Actual build container platform version exported by RunPipeline.
.PARAMETER platformVersionReason
    Non-sensitive reason supplied when the platform version could not be determined.
.OUTPUTS
    Hashtable containing Supported, Reason, and the resolved PowerShell 7 path.
#>
function Get-AlGoCodeCoverageCapability {
    Param(
        [AllowEmptyString()][string] $platformVersion,
        [AllowEmptyString()][string] $platformVersionReason
    )

    $minimumVersion = [version]"30.0.56026.0"
    if ([string]::IsNullOrWhiteSpace($platformVersion)) {
        return @{
            Supported = $false
            Reason = if ([string]::IsNullOrWhiteSpace($platformVersionReason)) {
                "RunPipeline did not provide the build container platform version. Code coverage requires container platform $minimumVersion or later."
            }
            else {
                "$platformVersionReason Code coverage requires container platform $minimumVersion or later."
            }
            PwshPath = ""
        }
    }

    $parsedVersion = $null
    if (-not [version]::TryParse($platformVersion.Trim(), [ref] $parsedVersion)) {
        return @{
            Supported = $false
            Reason = "RunPipeline provided an invalid build container platform version. Code coverage requires container platform $minimumVersion or later."
            PwshPath = ""
        }
    }

    if ($parsedVersion -lt $minimumVersion) {
        return @{
            Supported = $false
            Reason = "Container platform $parsedVersion is older than the required $minimumVersion."
            PwshPath = ""
        }
    }

    $pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $pwshCommand) {
        return @{
            Supported = $false
            Reason = "PowerShell 7 (pwsh) is required for code coverage compaction."
            PwshPath = ""
        }
    }

    return @{
        Supported = $true
        Reason = "Container platform $parsedVersion and PowerShell 7 support code coverage."
        PwshPath = "$($pwshCommand.Source)"
    }
}

<#
.SYNOPSIS
    Creates the AL-Go-owned code coverage session for one project test run.
.DESCRIPTION
    Resolves authoritative ordered source roots while AnalyzeRepo is in scope and creates one
    ordered run record per selected test app. Reusable source roots, application IDs, sequence
    numbers, and output paths are resolved once for the session.
.PARAMETER settings
    Analyzed AL-Go settings for the project.
.PARAMETER projectPath
    Full path to the AL-Go project.
.PARAMETER baseFolder
    Full repository root used for containment checks and repository-relative source roots.
.PARAMETER project
    Repository-relative project path recorded in coverage-status.json.
.PARAMETER projectName
    Display name recorded in coverage-status.json.
.PARAMETER buildMode
    Build-mode dimension recorded in coverage-status.json.
.PARAMETER testApps
    Selected test apps for this run.
.PARAMETER analyzeRepo
    Callback used to analyze source roots from projectsToTest.
.PARAMETER capability
    Capability result computed once by Get-AlGoCodeCoverageCapability.
.OUTPUTS
    AL-Go-owned session hashtable used for per-app completion and finalization.
#>
function New-AlGoCodeCoverageSession {
    Param(
        [hashtable] $settings,
        [string] $projectPath,
        [string] $baseFolder = "",
        [string] $project = ".",
        [string] $projectName = "",
        [string] $buildMode = "Default",
        [object[]] $testApps = @(),
        [scriptblock] $analyzeRepo = $null,
        [hashtable] $capability
    )

    if ([string]::IsNullOrWhiteSpace($baseFolder)) {
        $baseFolder = $projectPath
    }
    $generateCobertura = $true
    if ($settings.ContainsKey("useSeparateTestAction") -and
        $settings.useSeparateTestAction.ContainsKey("codeCoverageGenerateCobertura")) {
        $generateCobertura = [bool]$settings.useSeparateTestAction.codeCoverageGenerateCobertura
    }
    $coverageFormats = @("bc-json")
    if ($generateCobertura) {
        $coverageFormats += "cobertura"
    }

    $coverageRoot = [System.IO.Path]::GetFullPath(
        (Join-Path (Join-Path $projectPath ".buildartifacts") "CodeCoverage")
    )
    if (Test-Path -LiteralPath $coverageRoot) {
        Remove-Item -LiteralPath $coverageRoot -Recurse -Force
    }
    $sourceRootData = @()
    if ($capability.Supported) {
        $sourceRootData = @(Resolve-CodeCoverageSourceRootData -settings $settings `
            -projectPath $projectPath -baseFolder $baseFolder -analyzeRepo $analyzeRepo)
    }
    $sourceRoots = @($sourceRootData | ForEach-Object { "$($_.Path)" })
    $applicationIds = @($sourceRootData |
        Where-Object {
            "$($_.Kind)" -eq "app" -and
            -not [string]::IsNullOrWhiteSpace("$($_.AppId)")
        } |
        ForEach-Object { "$($_.AppId)".ToLowerInvariant() } |
        Sort-Object -Unique)

    $runs = [System.Collections.Generic.List[object]]::new()
    $appIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $testAppSequence = 0
    foreach ($testApp in @($testApps)) {
        $candidateAppId = "$($testApp.Id)"
        if ([string]::IsNullOrWhiteSpace($candidateAppId)) {
            throw "A selected test app does not contain an app ID."
        }
        $parsedAppId = [guid]::Empty
        if (-not [guid]::TryParse($candidateAppId, [ref]$parsedAppId)) {
            throw "Selected test app ID '$candidateAppId' is invalid."
        }
        $appId = $parsedAppId.ToString()
        if (-not $appIds.Add($appId)) {
            throw "Selected test app ID '$candidateAppId' is duplicated."
        }
        $runs.Add(@{
                Sequence = $testAppSequence
                AppId = $appId
                AppName = "$($testApp.Name)"
                OutputPath = [System.IO.Path]::GetFullPath((Join-Path $coverageRoot $appId))
                State = ""
            })
        $testAppSequence++
    }

    $session = @{
        Supported = [bool]$capability.Supported
        PwshPath = "$($capability.PwshPath)"
        Project = if ([string]::IsNullOrWhiteSpace($project)) { "." } else { $project.Replace('\', '/') }
        ProjectName = $projectName
        BuildMode = $buildMode
        Formats = @($coverageFormats)
        RootPath = $coverageRoot
        RepositoryRoot = [System.IO.Path]::GetFullPath($baseFolder)
        SourceRootRecords = @($sourceRootData)
        SourceRoots = @($sourceRoots)
        ApplicationIds = @($applicationIds)
        Runs = @($runs)
        Compactor = $null
    }
    return $session
}

<#
.SYNOPSIS
    Starts the single background aggregate worker for a supported session.
.DESCRIPTION
    Builds immutable reader metadata from the session, derives temporary and published paths,
    and starts the PowerShell 7 worker that consumes validated report descriptors.
.PARAMETER session
    Supported AL-Go-owned code coverage session requesting BC JSON.
.OUTPUTS
    Worker handle returned by Start-CodeCoverageAggregateWorker.
#>
function Start-CodeCoverageCompactorInternal {
    Param([hashtable] $session)

    $sourceRootDetails = @(Get-CodeCoverageSourceRootDetails $session.SourceRootRecords)
    $sourceRoots = @($session.SourceRootRecords | ForEach-Object { "$($_.RelativePath)" })
    $aggregatePath = Get-CodeCoverageAggregatePath -session $session
    $metadata = @{
        Mode = $script:CodeCoverageMode
        SourceRoots = @($sourceRoots)
        SourceRootDetails = @($sourceRootDetails)
    }
    return Start-CodeCoverageAggregateWorker `
        -readerModulePath (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
        -repositoryRoot $session.RepositoryRoot `
        -metadata $metadata `
        -temporaryPath "$aggregatePath.$([guid]::NewGuid().ToString('N')).tmp" `
        -publishedPath $aggregatePath `
        -pwshPath $session.PwshPath
}

<#
.SYNOPSIS
    Completes and validates one test app's code coverage run.
.DESCRIPTION
    Validates the completeness handoff and required fixed artifacts before handing BC JSON to the
    compactor. Test pass or failure does not affect coverage completeness, so failed tests can
    retain valid coverage.
.PARAMETER session
    AL-Go-owned session returned by New-AlGoCodeCoverageSession.
.PARAMETER run
    AL-Go-owned run record for the current test app.
.PARAMETER coverageIsComplete
    Completeness value returned by the current built-in runner or override invocation.
#>
function Complete-AlGoCodeCoverageRun {
    Param(
        [hashtable] $session,
        [hashtable] $run,
        $coverageIsComplete = $null
    )

    if (-not $session.Supported) {
        return
    }
    if (-not [string]::IsNullOrWhiteSpace("$($run.State)")) {
        throw "Code coverage for test app '$($run.AppId)' cannot complete from state '$($run.State)'."
    }
    try {
        Test-CodeCoverageArtifacts -session $session -run $run `
            -rawComplete $coverageIsComplete
        $run.State = if ([bool]$coverageIsComplete) { "complete" } else { "incomplete" }
        if ("bc-json" -in $session.Formats) {
            try {
                if (-not $session.Compactor) {
                    $session.Compactor = Start-CodeCoverageCompactorInternal -session $session
                    Write-Host "Started one PowerShell 7 code coverage compactor worker."
                }
                Add-CodeCoverageAggregateWorkItem -worker $session.Compactor -descriptor @{
                    Sequence = [int]$run.Sequence
                    AppId = "$($run.AppId)"
                    AppName = "$($run.AppName)"
                    Complete = [bool]$coverageIsComplete
                    ReportPath = Join-Path $run.OutputPath "coverage.bc.json"
                }
            }
            catch {
                throw "Code coverage compaction could not accept app '$($run.AppName)'. $($_.Exception.Message)"
            }
        }
    }
    catch {
        $run.State = "failed"
        throw
    }
}

<#
.SYNOPSIS
    Finalizes the AL-Go-owned code coverage session.
.DESCRIPTION
    Verifies that every supported app run reached a final state, drains aggregate compaction,
    and atomically writes the single final status manifest. Unsupported sessions retain
    unsupported runs without failing test execution.
.PARAMETER session
    AL-Go-owned session returned by New-AlGoCodeCoverageSession.
.PARAMETER suppressFailure
    Writes the best available status without replacing an earlier executor exception.
#>
function Complete-AlGoCodeCoverageSession {
    Param(
        [hashtable] $session,
        [switch] $suppressFailure
    )

    $failureReasons = @()
    if ($session.Supported) {
        foreach ($run in @($session.Runs)) {
            if ([string]::IsNullOrWhiteSpace("$($run.State)")) {
                $run.State = "failed"
                if (-not $suppressFailure) {
                    $failureReasons += "Test app '$($run.AppName)' did not produce final code coverage."
                }
            }
            elseif ($run.State -eq "failed") {
                $failureReasons += "Test app '$($run.AppName)' did not produce valid code coverage."
            }
        }
    }
    $aggregate = $null
    $drainStopwatch = $null
    $compactionFailed = $false
    if ($session.Compactor) {
        $drainStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $aggregate = Complete-CodeCoverageAggregateWorker -worker $session.Compactor
            $expectedRunCount = @($session.Runs | Where-Object {
                    $_.State -in @("complete", "incomplete")
                }).Count
            if (-not $aggregate -or [int]$aggregate.RunCount -ne $expectedRunCount) {
                throw "The code coverage aggregate does not contain every valid run."
            }
            $assessments = @($aggregate.RunAssessments)
            if ($assessments.Count -ne $expectedRunCount) {
                throw "The code coverage compactor did not assess every valid run."
            }
            $seenSequences = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($assessment in $assessments) {
                $sequence = 0
                if (-not [int]::TryParse("$($assessment.Sequence)", [ref]$sequence) -or
                    $sequence -lt 0 -or $sequence -ge $session.Runs.Count -or
                    -not $seenSequences.Add($sequence)) {
                    throw "The code coverage compactor returned an invalid run assessment."
                }
                $run = $session.Runs[$sequence]
                if ("$($assessment.AppId)" -cne "$($run.AppId)" -or
                    "$($assessment.AppName)" -cne "$($run.AppName)" -or
                    "$($assessment.State)".ToLowerInvariant() -cne "$($run.State)") {
                    throw "The code coverage compactor run assessment does not match the session."
                }
                if ($assessment.LineGlobalUnsafe -isnot [bool]) {
                    throw "The code coverage compactor returned an invalid run assessment."
                }
                $excludedLineFacts = 0
                if (-not [int]::TryParse(
                        "$($assessment.ExcludedLineFacts)", [ref]$excludedLineFacts) -or
                    $excludedLineFacts -lt 0) {
                    throw "The code coverage compactor returned an invalid run assessment."
                }
                $run["LineReasons"] = @($assessment.LineReasons | ForEach-Object { "$_" })
                $run["Notices"] = @($assessment.Notices | ForEach-Object { "$_" })
                $run["LineGlobalUnsafe"] = [bool]$assessment.LineGlobalUnsafe
                $run["LineAffectedSources"] = @(
                    $assessment.LineAffectedSources | ForEach-Object { "$_" }
                )
                $run["ExcludedLineFacts"] = $excludedLineFacts
            }
        }
        catch {
            $compactionFailed = $true
            $aggregate = $null
            Remove-Item -LiteralPath (Get-CodeCoverageAggregatePath -session $session) `
                -Force -ErrorAction SilentlyContinue
            $failureReasons += "Code coverage compaction failed. Raw BC JSON reports were retained. $($_.Exception.Message)"
        }
        finally {
            $session.Compactor = $null
        }
    }
    try {
        Write-CodeCoverageStatusInternal -session $session -aggregate $aggregate
    }
    catch {
        throw "The final code coverage status could not be written. $($_.Exception.Message)"
    }
    if ($aggregate) {
        $removedBytes = [long]0
        if ("$env:RUNNER_DEBUG" -eq "1") {
            Write-Host "RUNNER_DEBUG=1; retaining raw BC JSON code coverage reports."
        }
        else {
            try {
                $removedBytes = Remove-CodeCoverageRawReports -session $session
            }
            catch {
                Write-Host "::Warning::The code coverage aggregate was published, but one or more raw BC JSON reports could not be deleted. $($_.Exception.Message)"
            }
        }
        $drainStopwatch.Stop()

        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        Write-Host ("Code coverage compaction complete: runs={0}, lines={1}, parse={2}s, finalDrain={3}s, aggregateSize={4} MiB, rawRemoved={5} MiB, outcome=passed." -f
            $aggregate.RunCount,
            $aggregate.LineCount,
            ([double]$aggregate.TotalParseMilliseconds / 1000).ToString("0.000", $culture),
            $drainStopwatch.Elapsed.TotalSeconds.ToString("0.000", $culture),
            ([long]$aggregate.SizeBytes / 1MB).ToString("0.0", $culture),
            ($removedBytes / 1MB).ToString("0.0", $culture))
    }
    if ($failureReasons.Count -gt 0 -and ($compactionFailed -or -not $suppressFailure)) {
        throw ($failureReasons | Select-Object -Unique) -join " "
    }
}

Export-ModuleMember -Function `
    Get-AlGoCodeCoverageCapability, `
    New-AlGoCodeCoverageSession, `
    Complete-AlGoCodeCoverageRun, `
    Complete-AlGoCodeCoverageSession
