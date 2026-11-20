$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregate.psm1" -Resolve) `
    -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
    -DisableNameChecking

<#
.SYNOPSIS
    Resolves ordered repository source-root metadata for coverage collection and analysis.
.DESCRIPTION
    Collects appFolders and testFolders that contain AL source files from the current project
    and direct projectsToTest targets. Rejects roots outside the repository, deduplicates paths,
    reads available app identity, and returns deterministic records.
.PARAMETER settings
    Analyzed settings for the current project.
.PARAMETER projectPath
    Absolute path to the current project.
.PARAMETER baseFolder
    Absolute repository root used to resolve projectsToTest and reject outside paths.
.PARAMETER analyzeRepo
    Callback used to analyze settings for each direct projectsToTest target.
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

    $projects = @(@{
            Settings = $settings
            Path = $projectPath
        })
    foreach ($targetProject in $settings["projectsToTest"]) {
        $targetSettings = ReadSettings -project "$targetProject" -baseFolder $baseFolder |
            ConvertTo-HashTable -recurse
        $targetSettings = & $analyzeRepo -settings $targetSettings `
            -baseFolder $baseFolder -project "$targetProject"
        $projects += @{
            Settings = $targetSettings
            Path = [System.IO.Path]::GetFullPath((Join-Path $baseFolder "$targetProject"))
        }
    }

    foreach ($sourceProject in $projects) {
        foreach ($folderSetting in @("appFolders", "testFolders")) {
            $kind = if ($folderSetting -eq "appFolders") { "app" } else { "test" }
            foreach ($folder in $sourceProject.Settings[$folderSetting]) {
                $folderPath = [System.IO.Path]::GetFullPath((Join-Path $sourceProject.Path "$folder"))
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
    Ordered source-root records returned by Resolve-CodeCoverageSourceRootData.
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

function Get-CodeCoverageApplicationObjectIdRanges {
    <#
    .SYNOPSIS
        Returns object ID ranges owned by regular repository applications.
    .PARAMETER sourceRootRecords
        Source-root records whose regular application roots contain app.json files.
    #>
    Param([object[]] $sourceRootRecords)

    $ranges = @()
    foreach ($sourceRoot in @($sourceRootRecords |
            Where-Object { "$($_.Kind)" -eq "app" })) {
        $appJsonPath = Join-Path "$($sourceRoot.Path)" "app.json"
        $appJson = Get-Content -LiteralPath $appJsonPath -Raw -Encoding UTF8 |
            ConvertFrom-Json | ConvertTo-HashTable -recurse
        foreach ($idRange in @($appJson["idRanges"])) {
            if ($null -eq $idRange) {
                continue
            }
            $ranges += @{
                From = [int]$idRange["from"]
                To = [int]$idRange["to"]
            }
        }
    }
    return @($ranges | Sort-Object From, To -Unique)
}

<#
.SYNOPSIS
    Returns the final coverage status path for a session.
.PARAMETER session
    Coverage session containing the output root path.
#>
function Get-CodeCoverageStatusPath {
    Param([hashtable] $session)

    return Join-Path $session.RootPath "coverage-status.json"
}

<#
.SYNOPSIS
    Returns the published aggregate path for a session.
.PARAMETER session
    Coverage session containing the output root path.
#>
function Get-CodeCoverageAggregatePath {
    Param([hashtable] $session)

    return Join-Path $session.RootPath "coverage-aggregate.bin.gz"
}

<#
.SYNOPSIS
    Atomically writes the final AL-Go coverage status manifest.
.PARAMETER session
    Coverage session containing source roots and per-app run state.
.PARAMETER aggregate
    Optional completed aggregate metadata and per-run diagnostics.
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
                $diagnostics = @()
                if ($aggregate -and
                    $aggregate.RunDiagnostics.ContainsKey("$($run.AppId)")) {
                    $diagnostics = @(
                        $aggregate.RunDiagnostics["$($run.AppId)"] |
                            ForEach-Object { "$_" }
                    )
                }
                $runStatus = [ordered]@{
                    appId = "$($run.AppId)"
                    appName = "$($run.AppName)"
                    state = if ($session.Supported) { "$($run.State)" } else { "unsupported" }
                    diagnostics = @($diagnostics)
                }
                $runStatus
            }
        )
        $status = [ordered]@{
            project = "$($session.Project)"
            projectName = "$($session.ProjectName)"
            buildMode = "$($session.BuildMode)"
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
    Coverage session containing per-app output paths and run states.
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
.PARAMETER session
    Coverage session containing the required output formats.
.PARAMETER run
    Per-app run record containing its unique output path.
.PARAMETER rawComplete
    Boolean completeness value reported by AlTool.
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
    run record per selected test app. Reusable source roots, application IDs, and output paths
    are resolved once for the session.
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
    $generateCobertura = [bool]$settings.useSeparateTestAction.codeCoverageGenerateCobertura
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
    $applicationIds = @($sourceRootData |
        Where-Object {
            "$($_.Kind)" -eq "app" -and
            -not [string]::IsNullOrWhiteSpace("$($_.AppId)")
        } |
        ForEach-Object { "$($_.AppId)".ToLowerInvariant() } |
        Sort-Object -Unique)
    $applicationObjectIdRanges = @(
        Get-CodeCoverageApplicationObjectIdRanges $sourceRootData
    )

    $runs = [System.Collections.Generic.List[object]]::new()
    foreach ($testApp in @($testApps)) {
        $appId = "$($testApp.Id)"
        $runs.Add(@{
                AppId = $appId
                AppName = "$($testApp.Name)"
                OutputPath = [System.IO.Path]::GetFullPath((Join-Path $coverageRoot $appId))
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
        ApplicationIds = @($applicationIds)
        ApplicationObjectIdRanges = @($applicationObjectIdRanges)
        Runs = @($runs)
        Compactor = $null
    }
    return $session
}

<#
.SYNOPSIS
    Starts the single background aggregate worker for a supported session.
.PARAMETER session
    Supported coverage session containing source metadata and PowerShell 7 path.
#>
function Start-CodeCoverageCompactorInternal {
    Param([hashtable] $session)

    $applicationSourceRootRecords = @(
        $session.SourceRootRecords | Where-Object { "$($_.Kind)" -eq "app" }
    )
    $sourceRootDetails = @(Get-CodeCoverageSourceRootDetails $applicationSourceRootRecords)
    $aggregatePath = Get-CodeCoverageAggregatePath -session $session
    $metadata = @{
        SourceRootDetails = @($sourceRootDetails)
        ApplicationObjectIdRanges = @($session.ApplicationObjectIdRanges)
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
    try {
        Test-CodeCoverageArtifacts -session $session -run $run `
            -rawComplete $coverageIsComplete
        $run.State = if ([bool]$coverageIsComplete) { "complete" } else { "incomplete" }
        try {
            if (-not $session.Compactor) {
                $session.Compactor = Start-CodeCoverageCompactorInternal -session $session
                Write-Host "Started one PowerShell 7 code coverage compactor worker."
            }
            Add-CodeCoverageAggregateWorkItem -worker $session.Compactor -descriptor @{
                AppId = "$($run.AppId)"
                Complete = [bool]$coverageIsComplete
                ReportPath = Join-Path $run.OutputPath "coverage.bc.json"
            }
        }
        catch {
            throw "Code coverage compaction could not accept app '$($run.AppName)'. $($_.Exception.Message)"
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
            foreach ($run in @($session.Runs | Where-Object { $_.State -eq "incomplete" })) {
                if ($aggregate.RunCompleteness.ContainsKey("$($run.AppId)") -and
                    [bool]$aggregate.RunCompleteness["$($run.AppId)"]) {
                    $run.State = "complete"
                }
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
            $aggregate.RunDiagnostics.Count,
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
