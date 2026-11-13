$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregate.psm1" -Resolve) `
    -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregateFormat.psm1" -Resolve) `
    -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
    -DisableNameChecking

$script:CodeCoverageMode = "line"

<#
.SYNOPSIS
    Resolves the ordered source roots used for coverage collection and analysis.
.DESCRIPTION
    Collects appFolders and testFolders that contain AL source files from the current project
    and direct projectsToTest targets. Rejects roots outside the repository or behind reparse
    points, deduplicates paths, reads available app identity, and returns deterministic records.
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
                if (-not (Test-CoveragePathWithoutReparsePoint -Path $resolvedFullPath -Root $repositoryRoot)) {
                    throw "Code coverage source root '$resolvedFullPath' contains a reparse point or is outside the repository."
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
    Converts internal source-root records to the portable status and aggregate shape.
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
    Returns the isolated coverage output path for one test app.
.PARAMETER session
    AL-Go-owned code coverage session.
.PARAMETER run
    AL-Go-owned run record containing the normalized app ID.
.OUTPUTS
    Absolute per-app coverage output directory.
#>
function Get-CodeCoverageRunOutputPath {
    Param(
        [hashtable] $session,
        [hashtable] $run
    )

    return [System.IO.Path]::GetFullPath((Join-Path $session.RootPath "$($run.AppId)"))
}

<#
.SYNOPSIS
    Atomically writes the final AL-Go coverage status manifest.
.DESCRIPTION
    Serializes final run states, source-root metadata, and the optional validated aggregate
    descriptor to a temporary file before moving it to coverage-status.json.
.PARAMETER session
    Finalized AL-Go-owned code coverage session.
.PARAMETER aggregate
    Optional validated aggregate descriptor returned by the background compactor.
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
                [ordered]@{
                    appId = "$($run.AppId)"
                    appName = "$($run.AppName)"
                    outputDirectory = "CodeCoverage/$($run.AppId)"
                    state = if ($session.Supported) { "$($run.State)" } else { "unsupported" }
                }
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
            $status["aggregate"] = [ordered]@{
                format = "$($aggregate.Format)"
                contractVersion = [int]$aggregate.ContractVersion
                path = "$($aggregate.Path)"
                sha256 = "$($aggregate.Sha256)"
                sourceRootFingerprint = "$($aggregate.SourceRootFingerprint)"
                runCount = [int]$aggregate.RunCount
                lineCount = [int]$aggregate.LineCount
                sizeBytes = [long]$aggregate.SizeBytes
            }
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
    Drains and logs available per-report compactor telemetry.
.DESCRIPTION
    Moves report events from the worker's concurrent event queue into session telemetry for
    final overlap calculation while writing concise GitHub action log output.
.PARAMETER session
    AL-Go-owned code coverage session containing the active compactor.
#>
function Write-CodeCoverageCompactorEvents {
    Param([hashtable] $session)

    if (-not $session.Compactor -or -not $session.Compactor.ContainsKey("Telemetry")) {
        return
    }
    foreach ($telemetryEvent in @($session.Compactor.Telemetry)) {
        $session.CompactorTelemetry.Add($telemetryEvent)
    }
    $session.Compactor.Telemetry = @()
}

<#
.SYNOPSIS
    Deletes raw per-app BC JSON reports after durable aggregate publication.
.PARAMETER session
    Finalized AL-Go-owned code coverage session.
.OUTPUTS
    Total number of raw report bytes removed.
#>
function Remove-CodeCoverageRawReports {
    Param([hashtable] $session)

    $removedBytes = [long]0
    foreach ($run in @($session.Runs)) {
        $reportPath = Join-Path (Get-CodeCoverageRunOutputPath -session $session -run $run) `
            "coverage.bc.json"
        if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
            $removedBytes += (Get-Item -LiteralPath $reportPath).Length
            Remove-Item -LiteralPath $reportPath -Force
        }
    }
    return $removedBytes
}

<#
.SYNOPSIS
    Validates and reads required metadata from one BC JSON coverage report.
.DESCRIPTION
    Uses the shared metadata-only reader and translates parser failure details into
    coordinator-facing validation errors.
.PARAMETER path
    Path to coverage.bc.json.
.OUTPUTS
    Hashtable containing schema version, coverage mode, completeness, and reader name.
#>
function Read-CodeCoverageReportMetadata {
    Param([string] $path)

    $result = Read-BcCoverageReport -Path $path -MetadataOnly
    if (-not $result.Valid) {
        if ("$($result.FailureDetail)".StartsWith("duplicate:", [System.StringComparison]::Ordinal)) {
            $propertyName = "$($result.FailureDetail)".Substring("duplicate:".Length)
            throw "The JSON contains duplicate top-level property '$propertyName'."
        }
        $message = switch ("$($result.FailureDetail)") {
            "schema" { "The produced BC JSON schemaVersion is not supported." }
            "mode" { "The produced BC JSON coverage mode does not match the requested mode." }
            "complete" { "The produced BC JSON completeness value is invalid." }
            default { "$($result.Reason)" }
        }
        throw $message
    }
    return @{
        SchemaVersion = "$($result.Data.schemaVersion)"
        CoverageMode = "$($result.Data.coverageMode)"
        Complete = [bool]$result.Data.complete
        Reader = "$($result.Reader)"
    }
}

<#
.SYNOPSIS
    Validates the requested coverage artifacts for one completed app run.
.DESCRIPTION
    Requires every requested fixed artifact and, for BC JSON, verifies the supported schema,
    line mode, complete document, and agreement with the runner's completeness result.
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
        $artifactPath = Join-Path (Get-CodeCoverageRunOutputPath -session $session -run $run) `
            $expectedArtifacts[$coverageFormat]
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "The expected '$coverageFormat' coverage artifact '$artifactPath' was not created."
        }
    }

    if ("bc-json" -in $session.Formats) {
        $reportPath = Join-Path (Get-CodeCoverageRunOutputPath -session $session -run $run) `
            "coverage.bc.json"
        try {
            $report = Read-CodeCoverageReportMetadata -path $reportPath
        }
        catch {
            throw "The coverage-aware test runner produced invalid BC JSON at '$reportPath'. Error: $($_.Exception.Message)"
        }
        if ($report.SchemaVersion -ne "1.0") {
            throw "The produced BC JSON schemaVersion is not supported."
        }
        if ($report.CoverageMode.ToLowerInvariant() -ne $script:CodeCoverageMode) {
            throw "The produced BC JSON coverage mode does not match the requested mode."
        }
        if ($report.Complete -ne [bool]$rawComplete) {
            throw "The reported coverage completeness does not match the BC JSON report."
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
    minimal ordered run record per selected test app. Output paths and override contexts are
    derived only when needed.
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
    if (-not $capability -or -not $capability.ContainsKey("Supported") -or
        -not $capability.ContainsKey("Reason")) {
        throw "A valid code coverage capability result is required."
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

    $runs = [System.Collections.Generic.List[object]]::new()
    $appIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
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
                AppId = $appId
                AppName = "$($testApp.Name)"
                State = ""
            })
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
        Runs = @($runs)
        Compactor = $null
        CompactorFailure = ""
        CompactorTelemetry = [System.Collections.Generic.List[object]]::new()
    }
    return $session
}

<#
.SYNOPSIS
    Starts the single background aggregate worker for a supported session.
.DESCRIPTION
    Builds immutable aggregate metadata from the session, derives temporary and published
    paths, and starts the PowerShell 7 worker that consumes validated report descriptors.
.PARAMETER session
    Supported AL-Go-owned code coverage session requesting BC JSON.
.OUTPUTS
    Worker handle returned by Start-CodeCoverageAggregateWorker.
#>
function Start-CodeCoverageCompactorInternal {
    Param([hashtable] $session)

    $sourceRootDetails = @(Get-CodeCoverageSourceRootDetails $session.SourceRootRecords)
    $sourceRoots = @($session.SourceRootRecords | ForEach-Object { "$($_.RelativePath)" })
    $fingerprint = Get-CodeCoverageSourceRootFingerprint `
        -sourceRoots $sourceRoots -sourceRootDetails $sourceRootDetails
    $aggregatePath = Get-CodeCoverageAggregatePath -session $session
    $metadata = @{
        Project = "$($session.Project)"
        ProjectName = "$($session.ProjectName)"
        BuildMode = "$($session.BuildMode)"
        Mode = $script:CodeCoverageMode
        Formats = @($session.Formats)
        SourceRoots = @($sourceRoots)
        SourceRootDetails = @($sourceRootDetails)
        SourceRootFingerprint = $fingerprint
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
    Validates required artifacts and BC JSON metadata. Test pass or failure does not affect coverage
    completeness, so failed tests can retain valid coverage.
.PARAMETER session
    AL-Go-owned session returned by New-AlGoCodeCoverageSession.
.PARAMETER run
    AL-Go-owned run record for the current test app.
.PARAMETER coverageIsComplete
    Completeness value returned by the current built-in runner or override invocation.
.PARAMETER executionFailed
    Marks an invocation that failed before valid coverage could be produced.
#>
function Complete-AlGoCodeCoverageRun {
    Param(
        [hashtable] $session,
        [hashtable] $run,
        $coverageIsComplete = $null,
        [switch] $executionFailed
    )

    if (-not $session -or -not $session.ContainsKey("Runs") -or -not $run) {
        throw "The code coverage session is invalid or uses an unsupported coordinator contract."
    }
    if (-not $session.Supported) {
        return
    }
    if (-not [string]::IsNullOrWhiteSpace("$($run.State)")) {
        throw "Code coverage for test app '$($run.AppId)' cannot complete from state '$($run.State)'."
    }
    if ($executionFailed) {
        $run.State = "failed"
        $run.CompletedAtUtc = [DateTime]::UtcNow
        return
    }
    try {
        Test-CodeCoverageArtifacts -session $session -run $run `
            -rawComplete $coverageIsComplete
        $run.State = if ([bool]$coverageIsComplete) { "complete" } else { "incomplete" }
        $run.CompletedAtUtc = [DateTime]::UtcNow
        if ("bc-json" -in $session.Formats -and
            [string]::IsNullOrWhiteSpace($session.CompactorFailure)) {
            try {
                if (-not $session.Compactor) {
                    $session.Compactor = Start-CodeCoverageCompactorInternal -session $session
                    Write-Host "Started one PowerShell 7 code coverage compactor worker."
                }
                $sequence = [array]::IndexOf([object[]]$session.Runs, $run)
                if ($sequence -lt 0) {
                    throw "The code coverage run is not part of the supplied session."
                }
                Add-CodeCoverageAggregateWorkItem -worker $session.Compactor -descriptor @{
                    Sequence = $sequence
                    AppId = "$($run.AppId)"
                    AppName = "$($run.AppName)"
                    Complete = [bool]$coverageIsComplete
                    ReportPath = Join-Path (
                        Get-CodeCoverageRunOutputPath -session $session -run $run
                    ) "coverage.bc.json"
                }
            }
            catch {
                $session.CompactorFailure = $_.Exception.Message
                throw "Code coverage compaction could not accept app '$($run.AppName)'. $($session.CompactorFailure)"
            }
        }
        Write-CodeCoverageCompactorEvents -session $session
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

    if (-not $session -or -not $session.ContainsKey("Runs")) {
        throw "The code coverage session is invalid or uses an unsupported coordinator contract."
    }

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
            Write-CodeCoverageCompactorEvents -session $session
            if (-not [string]::IsNullOrWhiteSpace($session.CompactorFailure)) {
                throw $session.CompactorFailure
            }
            $expectedRunCount = @($session.Runs | Where-Object {
                    $_.State -in @("complete", "incomplete")
                }).Count
            if (-not $aggregate -or [int]$aggregate.RunCount -ne $expectedRunCount) {
                throw "The code coverage aggregate does not contain every valid run."
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

        $overlappedReports = 0
        foreach ($telemetry in @($session.CompactorTelemetry)) {
            $parseStart = [DateTime]$telemetry.ParseStartedAtUtc
            $parseEnd = [DateTime]$telemetry.ParseEndedAtUtc
            if (@($session.Runs | Where-Object {
                        $candidate = $_
                        $candidate.ContainsKey("StartedAtUtc") -and
                        [DateTime]$candidate.StartedAtUtc -lt $parseEnd -and
                        ($candidate.ContainsKey("CompletedAtUtc") -eq $false -or
                            [DateTime]$candidate.CompletedAtUtc -gt $parseStart) -and
                        "$($candidate.AppId)" -ne "$($telemetry.AppId)"
                    }).Count -gt 0) {
                $overlappedReports++
            }
        }
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        Write-Host ("Code coverage compaction complete: runs={0}, lines={1}, activeParse={2}s, finalDrain={3}s, aggregateSize={4} MiB, rawRemoved={5} MiB, parserProducerOverlap={6}/{0}, outcome=passed." -f
            $aggregate.RunCount,
            $aggregate.LineCount,
            ([double]$aggregate.TotalParseMilliseconds / 1000).ToString("0.000", $culture),
            $drainStopwatch.Elapsed.TotalSeconds.ToString("0.000", $culture),
            ([long]$aggregate.SizeBytes / 1MB).ToString("0.0", $culture),
            ($removedBytes / 1MB).ToString("0.0", $culture),
            $overlappedReports)
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
