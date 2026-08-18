. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DownloadProjectDependencies\DownloadProjectDependencies.psm1" -Resolve) -DisableNameChecking

<#
    .Synopsis
        Gets the modified files in a GitHub pull request.
#>
function Get-ModifiedFiles {
    param(
        [Parameter(HelpMessage = "The baseline SHA", Mandatory = $true)]
        [string] $baselineSHA
    )

    Push-Location $ENV:GITHUB_WORKSPACE
    try {
        $ghEvent = Get-Content $env:GITHUB_EVENT_PATH -Encoding UTF8 | ConvertFrom-Json
        if ($ghEvent.PSObject.Properties.name -eq 'pull_request') {
            $headSHA = $ghEvent.pull_request.head.sha
            Write-Host "Using head SHA $headSHA from pull request"
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $headSHA | Out-Host }
            if ($baselineSHA) {
                Write-Host "This is a pull request, but baseline SHA was specified to $baselineSHA"
            }
            else {
                $baselineSHA = $ghEvent.pull_request.base.sha
                Write-Host "This is a pull request, using baseline SHA $baselineSHA from pull request"
            }
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $baselineSHA | Out-Host }
        }
        else {
            $headSHA = git rev-parse HEAD
            Write-Host "Current HEAD is $headSHA"
            Invoke-CommandWithRetry -ScriptBlock { RunAndCheck git fetch origin $baselineSHA | Out-Host }
            Write-Host "Not a pull request, using baseline SHA $baselineSHA and current HEAD $headSHA"
        }
        Write-Host "git diff --name-only $baselineSHA $headSHA"
        $modifiedFiles = @(RunAndCheck git diff --name-only $baselineSHA $headSHA | ForEach-Object { "$_".Replace('/', [System.IO.Path]::DirectorySeparatorChar) })
        return $modifiedFiles
    }
    finally {
        Pop-Location
    }
}

<#
.Synopsis
    Determines whether a project should be built based on the modified files.
.Outputs
    A boolean indicating whether the project should be built.
#>
function ShouldBuildProject {
    param (
        [Parameter(HelpMessage = "An AL-Go project", Mandatory = $true)]
        $project,
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        $baseFolder,
        [Parameter(HelpMessage = "A list of modified files", Mandatory = $false)]
        $modifiedFiles = @()
    )

    if (-not $modifiedFiles) {
        Write-Host "No modified files found, not building project $project"
        return $false
    }

    Write-Host "Determining whether to build project $project based on modified files"
    $projectFolders = GetProjectFolders -baseFolder $baseFolder -project $project -includeAlGoFolder

    $modifiedProjectFolders = @()
    foreach($projectFolder in $projectFolders) {
        $projectFolder = Join-Path $baseFolder "$projectFolder/*"

        if ($modifiedFiles -like $projectFolder) {
            $modifiedProjectFolders += $projectFolder
        }
    }

    if ($modifiedProjectFolders.Count -gt 0) {
        Write-Host "Modified files found for project $project : $($modifiedProjectFolders -join ', ')"
        return $true
    }

    Write-Host "No modified files found for project $project. Not building project $project"
    return $false
}

<#
.Synopsis
    Computes appBuild/appRevision from the current GitHub Actions run context (GITHUB_RUN_NUMBER,
    GITHUB_RUN_ATTEMPT) the same way Actions/ReadSettings/ReadSettings.ps1 does for the Windows
    pipeline, so a project on the Linux fast lane gets the identical version numbers the Windows
    pipeline would have computed for it.

.Description
    Get-VersionNumber (AL-Go-Helper.ps1) only reads whatever's already in Settings.appBuild/
    appRevision - it does not compute them from the run context itself. In the real Windows
    pipeline, Actions/ReadSettings/ReadSettings.ps1 does that computation as a separate step
    before Get-VersionNumber is ever called. DetermineProjectsToBuild runs in the Initialization
    job, before that step exists for a Linux fast lane project (which never runs the Windows
    ReadSettings action at all), so this mirrors that same computation here instead of leaving
    appBuild/appRevision at their schema defaults.

    Deliberately a standalone duplicate, not a shared function with ReadSettings.ps1: that script
    ships as part of upstream microsoft/AL-Go, and this fork's rule 2 (see this repo's CLAUDE.md)
    is to keep fork changes additive rather than rewriting existing upstream logic in place, to
    stay cleanly mergeable from upstream. Keep this in sync by hand if that switch ever changes.

.PARAMETER Settings
    The resolved settings hashtable. Mutated in place, matching ReadSettings.ps1's own style.
#>
function Set-RunNumberVersioning {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings
    )
    if ($ENV:GITHUB_EVENT_NAME -in @("pull_request_target", "pull_request", "merge_group")) {
        $Settings.versioningStrategy = 15
    }
    if ($Settings.appBuild -eq [int32]::MaxValue) {
        $Settings.versioningStrategy = 15
    }
    if ($Settings.versioningStrategy -eq -1) {
        # Get-VersionNumber derives everything from the resolved artifact URL for this strategy -
        # nothing to compute here.
        return
    }
    switch ($Settings.versioningStrategy -band 15) {
        0 {
            # Use RUN_NUMBER and RUN_ATTEMPT
            $Settings.appBuild = $Settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
            $Settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
        }
        2 {
            # USE DATETIME
            $Settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
            $Settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
        }
        3 {
            # USE BUILD from app.json and RUN_NUMBER
            $Settings.appBuild = -1
            $Settings.appRevision = $Settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
        }
        15 {
            # Use maxValue and RUN_NUMBER
            $Settings.appBuild = [Int32]::MaxValue
            $Settings.appRevision = $Settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
        }
        default {
            Write-Host "::warning::Unsupported versioningStrategy $($Settings.versioningStrategy) while computing the Linux fast lane app version centrally; leaving appBuild/appRevision unchanged."
        }
    }
}

<#
.Synopsis
    Creates buils dimensions for a list of projects.

.Outputs
    An array of build dimensions for the projects and their corresponding build modes.
    Each build dimension is a hashtable with the following keys:
    - project: The name of the AL-Go project
    - buildMode: The build mode to use for the project
    - linuxFastLane: Whether this project should build via the Linux BC fast lane instead of the Windows pipeline
    - linuxBcVersion: The concrete BC version to use on the Linux fast lane (best-effort resolved from the artifact/country settings; empty if it couldn't be resolved)
    - linuxAlToolVersion: The AL compiler version policy for the Linux fast lane, mapped from the project's vsixFile setting ('' (default/matching), 'latest', or 'prerelease'); empty if vsixFile is a direct download URL, which can't be mapped to a policy keyword
    - linuxAppDirs / linuxTestAppDirs: space-separated, repo-root-relative app/test folders for the Linux fast lane
    - linuxCodeunitRange: pipe-separated "from..to" span(s) built from the idRanges declared in each test app's app.json, used to scope the Linux fast lane's test-codeunit discovery; empty if no idRanges could be read (the fast lane then falls back to its own unbounded default)
    - linuxDependencySubdir: sanitized project name used as the subfolder under the LinuxFastLaneDependencies artifact holding this project's third-party (appDependencyProbingPaths) and same-repo project dependency .apps; empty if the project has none
    - linuxArtifactNameSuffix: "<sanitized project>-<buildMode>", used as bc-linux's compiled-apps upload suffix ("bc-linux-build-<suffix>") and read back by the PublishLinuxArtifacts job to re-shape that artifact into AL-Go's own Apps/TestApps naming; empty when linuxFastLane is false
    - linuxAppVersionMajorMinor / linuxAppVersionBuild / linuxAppVersionRevision: the same Major.Minor/Build/Revision Get-VersionNumber computes for the Windows pipeline's own Update-AppJsonProperties call, passed through to bc-test-from-source.yml's app_version_* inputs so the Linux fast lane's compiled apps carry a version that climbs run over run instead of reusing whatever's committed in app.json (which BC's Deploy step would then see as no higher than what's already installed, and skip). Blank/0 when linuxFastLane is false or the value couldn't be resolved.
    - artifact: the resolved BC artifact URL for this project (best-effort resolved centrally here, the same way the project's own "Determine ArtifactUrl" build step would); empty if it couldn't be resolved, in which case the build step resolves it itself as a fallback
    - artifactCacheKey: cache key for the Cache Business Central Artifacts step, mirroring DetermineArtifactUrl.ps1's own logic (set only when useCompilerFolder is true and symbolsSource is not 'nuGet'); empty otherwise, or when artifact couldn't be resolved
#>
<#
.Synopsis
    Guarantees a build dimensions array is never returned empty, so it's always safe to hand to a
    GitHub Actions strategy.matrix.include expression.

.Description
    GitHub Actions evaluates strategy.matrix for every job unconditionally, before applying that job's
    if: condition - an empty (or all-empty-object) include array throws "Error when evaluating
    'strategy' for job '<name>'" and the job never runs, even though its if: (gated on the *Count
    output alongside this array) would otherwise have skipped it cleanly. The workflow YAML has no way
    to protect against this itself, since the failure happens before if: is ever considered. Substitute
    a single placeholder vector with a real property instead; its values are never read for real builds
    because the if: guard (checked against the real Count, not this array) skips the job's steps
    whenever this substitution kicks in.

    That if: guard only skips steps, though - it does not stop GitHub from dispatching the reusable
    workflow the job calls (_BuildALGoProject.yaml), and that reusable workflow's own job evaluates its
    job-level `runs-on: ${{ fromJson(inputs.runsOn) }}` before any of ITS if: conditions apply either.
    An empty gitHubRunner value throws "Error when evaluating 'runs-on' for job 'BuildALGoProject'" the
    same way an empty array throws for strategy. The placeholder's gitHubRunner must therefore be a
    valid fromJson()-able runner label - windows-latest always exists on GitHub-hosted runners - even
    though the job it's handed to never actually builds anything.

.PARAMETER dimensions
    The build dimensions array (buildDimensions or buildDimensionsLinux) to protect.
#>
function ProtectEmptyBuildDimensions {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $dimensions
    )
    $dimensions = @($dimensions)
    if ($dimensions.Count -eq 0) {
        $dimensions = @(, @{
            project           = ''
            buildMode         = ''
            linuxFastLane     = $false
            gitHubRunner      = '"windows-latest"'
            githubRunnerShell = 'powershell'
        })
    }
    # -NoEnumerate is required: a plain `return $dimensions` (or wrapping it again in @() at the
    # call site) unrolls a single-element array back down to its bare element when PowerShell
    # captures the function's output - a Hashtable element then reports .Count as its key count,
    # not 1, and a real (already multi/single-element) array gets nested inside an extra array
    # instead. -NoEnumerate is what preserves the array itself as the one output object.
    Write-Output -NoEnumerate $dimensions
}

function CreateBuildDimensions {
    param(
        [Parameter(HelpMessage = "A list of AL-Go projects for which to generate build dimensions")]
        $projects = @(),
        $baseFolder,
        [Parameter(HelpMessage = "Token used to access dependency repositories (e.g. appDependencyProbingPaths for the Linux fast lane)", Mandatory = $false)]
        $token,
        [Parameter(HelpMessage = "A hashtable mapping project name to an array of the names of the (same-repo) projects it depends on, used to stage dependency apps for the Linux fast lane", Mandatory = $false)]
        $projectDependencies = @{},
        [Parameter(HelpMessage = "ID of the baseline workflow run, used as a fallback to resolve a same-repo project dependency for the Linux fast lane when the dependency project isn't built in the current run", Mandatory = $false)]
        $baselineWorkflowRunId = '0'
    )

    $buildDimensions = @()

    foreach($project in $projects) {
        $projectSettings = ReadSettings -project $project -baseFolder $baseFolder
        $gitHubRunner = $projectSettings.githubRunner.Split(',').Trim() | ConvertTo-Json -compress
        $githubRunnerShell = $projectSettings.githubRunnerShell
        $buildModes = @($projectSettings.buildModes)

        if(!$buildModes) {
            Write-Host "No build modes found for project $project, using default build mode 'Default'."
            $buildModes = @('Default')
        }

        $linuxFastLane = [bool]$projectSettings.linuxFastLane
        if ($linuxFastLane -and ([bool]$projectSettings.useCompilerFolder -or [bool]$projectSettings.doNotPublishApps)) {
            # The Linux fast lane exists to publish apps to a container and run tests there.
            # useCompilerFolder means "no container" and doNotPublishApps means "nothing gets
            # published" - either one makes this a compile-only project, which the fast lane
            # can't serve (it always tries to publish+test). Fall back to the standard Windows
            # pipeline, which already knows how to do a compile-only build correctly.
            Write-Host "::warning::linuxFastLane is enabled for project $project, but useCompilerFolder/doNotPublishApps make it a compile-only project (no container, nothing published). Skipping the Linux fast lane for this project; it will use the standard Windows pipeline instead."
            $linuxFastLane = $false
        }
        $linuxBcVersion = ''
        $linuxAlToolVersion = ''
        $linuxAppDirs = ''
        $linuxTestAppDirs = ''
        $linuxCodeunitRange = ''
        $linuxDependencySubdir = ''
        $linuxAppVersionMajorMinor = ''
        $linuxAppVersionBuild = 0
        $linuxAppVersionRevision = 0
        $artifact = ''
        $artifactCacheKey = ''

        # AnalyzeRepo discovers appFolders/testFolders and resolves the artifact/updateDependencies settings the
        # same way DetermineArtifactUrl does today for the Windows pipeline's own per-project "Determine
        # ArtifactUrl" build step. Resolved once here for every project (not just linuxFastLane ones) so that
        # DetermineArtifactUrl below - and the BcContainerHelper download/import it needs - runs once per
        # Initialization job instead of once per project's own separate build job (measured ~19s per job, almost
        # entirely BcContainerHelper download/import, not the actual ~2.3s artifact lookup).
        $resolvedSettings = AnalyzeRepo -settings $projectSettings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting -doNotIssueWarnings

        if ($linuxFastLane) {
            # Map AL-Go's vsixFile setting onto bc-test-from-source.yml's al_tool_version policy keyword,
            # so the same "which compiler" choice governs both the Windows and Linux fast lane builds.
            switch ($projectSettings.vsixFile) {
                { [string]::IsNullOrEmpty($_) -or $_ -eq 'default' } { $linuxAlToolVersion = '' } # blank = bc-linux's own default (matching the BC major)
                'latest' { $linuxAlToolVersion = 'latest' }
                'preview' { $linuxAlToolVersion = 'prerelease' }
                default {
                    Write-Host "::warning::vsixFile is set to a direct download URL for project $project; the Linux fast lane can't resolve a compiler version from a URL and will fall back to its own default. Use 'default', 'latest', or 'preview' for vsixFile to also control the Linux fast lane compiler."
                }
            }
            $linuxAppDirs = @($resolvedSettings.appFolders | ForEach-Object { (Join-Path $project ($_ -replace '^\.[\\/]', '')).Replace('\','/') }) -join ' '
            $testFolderRelPaths = @($resolvedSettings.testFolders | ForEach-Object { $_ -replace '^\.[\\/]', '' })
            $linuxTestAppDirs = @($testFolderRelPaths | ForEach-Object { (Join-Path $project $_).Replace('\','/') }) -join ' '

            # Scope the Linux fast lane's test-codeunit discovery to the range(s) each test app
            # actually declares, instead of handing bc-linux an unbounded "run everything"
            # sentinel. app.json's idRanges is mandatory, so every test app has one; read it
            # directly rather than guessing at a convention.
            $idRangeSpans = [System.Collections.Generic.List[string]]::new()
            foreach ($testFolderRelPath in $testFolderRelPaths) {
                $testAppJsonFile = Join-Path $baseFolder $project $testFolderRelPath 'app.json'
                if (Test-Path $testAppJsonFile) {
                    try {
                        $testAppJson = Get-Content $testAppJsonFile -Encoding UTF8 | ConvertFrom-Json
                        foreach ($idRange in $testAppJson.idRanges) {
                            $idRangeSpans.Add("$($idRange.from)..$($idRange.to)")
                        }
                    }
                    catch {
                        Write-Host "::warning::Could not read idRanges from $testAppJsonFile for project $project ($($_.Exception.Message)); the Linux fast lane will fall back to its own default codeunit range."
                    }
                }
            }
            $linuxCodeunitRange = ($idRangeSpans | Select-Object -Unique) -join '|'
        }

        try {
            $artifactUrl = DetermineArtifactUrl -projectSettings $resolvedSettings -doNotIssueWarnings
            $artifact = $artifactUrl
            if ($resolvedSettings.useCompilerFolder -and $resolvedSettings.symbolsSource -ne 'nuGet') {
                # Mirrors DetermineArtifactUrl.ps1's own cache-key logic: an empty cache key switches off the
                # Cache Business Central Artifacts steps in the workflow. When symbols come from NuGet the
                # artifact is never downloaded, so caching it would only cost a restore and a cache entry
                # nothing reads.
                $artifactCacheKey = $artifactUrl.Split('?')[0]
            }
            if ($linuxFastLane) {
                $linuxBcVersion = $artifactUrl.Split('/')[4]
            }
        }
        catch {
            # A resolution failure here must not fail the whole Initialization job - that would take every
            # project's build down with it over one project's artifact-resolution problem, a real regression in
            # blast radius compared to today (where each project's own build job fails in isolation). Leave
            # artifact/artifactCacheKey empty; the project's own "Determine ArtifactUrl" build step then runs
            # exactly as it does today as a fallback, so behavior for that project is unchanged end to end.
            Write-Host "::warning::Could not resolve the BC artifact URL centrally for project $project ($($_.Exception.Message)); its own build job will resolve it as a fallback."
            if ($linuxFastLane) {
                Write-Host "::warning::Could not resolve a concrete BC version from the artifact setting for project $project ($($_.Exception.Message)); the Linux fast lane will use its own default version. Pin the artifact setting to a concrete version to control this."
            }
        }

        if ($linuxFastLane) {
            try {
                # Independent of the artifact resolution above succeeding: Get-VersionNumber only reads
                # Settings.artifact for versioningStrategy -1 ("derive the version from the artifact
                # setting"), every other strategy ignores it completely. Gating this on artifact
                # resolution having succeeded would silently reintroduce the exact bug this fixes (see
                # bc-linux issue #38) whenever artifact resolution fails for a reason that has nothing
                # to do with versioning. $artifact is '' when resolution above failed - fine for every
                # strategy except -1, which then throws here and is caught below like everything else.
                $versionSettings = $resolvedSettings.Clone()
                $versionSettings.artifact = $artifact
                Set-RunNumberVersioning -Settings $versionSettings
                $versionNumber = Get-VersionNumber -Settings $versionSettings
                $linuxAppVersionMajorMinor = $versionNumber.MajorMinorVersion
                $linuxAppVersionBuild = $versionNumber.BuildNumber
                $linuxAppVersionRevision = $versionNumber.RevisionNumber
            }
            catch {
                Write-Host "::warning::Could not resolve the app version centrally for project $project ($($_.Exception.Message)); the Linux fast lane will compile with each app's own committed app.json version, which BC's Deploy step may then skip as not higher than what's already installed."
            }
        }

        if ($linuxFastLane) {
            # bc-test-from-source.yml only stages symbols from the BC platform artifact tree (Microsoft apps).
            # Neither third-party dependencies (appDependencyProbingPaths) nor same-repo project dependencies
            # are in that artifact, so both are downloaded here (the same mechanisms the Windows pipeline uses)
            # and staged under LinuxFastLaneDependencies_staging for a single Initialization-job upload step to
            # pick up as the LinuxFastLaneDependencies artifact.

            # '.' (the common single-project-repo project name) is a reserved relative path
            # segment - joining it onto a folder path is a no-op, not a real subfolder, which
            # would silently collapse the per-project layout the LinuxFastLaneDependencies
            # artifact depends on. Give it an explicit, unambiguous name instead.
            $sanitizedProject = ($project -replace '[\\/]', '_')
            if ($sanitizedProject -eq '.') {
                $sanitizedProject = '_root_'
            }
            $depFolder = Join-Path $baseFolder "LinuxFastLaneDependencies_staging" $sanitizedProject
            $downloadedCount = 0

            try {
                $probingSettings = CheckAppDependencyProbingPaths -settings $resolvedSettings -token $token -baseFolder $baseFolder -project $project
                if ($probingSettings.ContainsKey('appDependencyProbingPaths') -and $probingSettings.appDependencyProbingPaths) {
                    New-Item -Path $depFolder -ItemType Directory -Force | Out-Null
                    # Only the 'Apps' mask - the dependency's own production app(s), which the
                    # consumer's app.json actually declares a dependency on. Skip 'TestApps'/
                    # 'Dependencies': those exist to let the Windows pipeline install a
                    # dependency's own test fixtures, but they're not needed to compile/run
                    # the consumer's project, and can carry transitive dependencies of their
                    # own (a dependency's *test* app depending on an older/differently-
                    # published version of itself) that were never part of what this project
                    # actually needs.
                    $downloaded = @(GetDependencies -probingPathsJson $probingSettings.appDependencyProbingPaths -saveToPath $depFolder -masks @('Apps') -api_url 'https://api.github.com' | Where-Object { $_ })
                    Write-Host "GetDependencies returned $($downloaded.Count) item(s) for project $project`: $($downloaded -join ', ')"
                    $downloaded = @(Resolve-DependencyFiles -Dependencies $downloaded -DestinationPath $depFolder)
                    Write-Host "Resolve-DependencyFiles left $($downloaded.Count) app file(s) in $depFolder`: $((Get-ChildItem -Path $depFolder -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', ')"
                    $downloadedCount += $downloaded.Count
                }
            }
            catch {
                Write-Host "::warning::Could not download appDependencyProbingPaths dependencies for the Linux fast lane build of project $project ($($_.Exception.Message)); production apps depending on them will fail to compile on the Linux fast lane."
            }

            if ($projectDependencies.Keys -contains $project -and $projectDependencies."$project") {
                try {
                    New-Item -Path $depFolder -ItemType Directory -Force | Out-Null
                    # Same reasoning as above for the 'Apps'-only mask: the fast lane only needs
                    # a same-repo dependency project's production app(s) to compile/publish
                    # against, not its test fixtures.
                    $downloaded = @(Get-DependenciesFromCurrentBuild -baseFolder $baseFolder -project $project -projectDependencies $projectDependencies -buildMode 'Default' -baselineWorkflowRunID $baselineWorkflowRunId -destinationPath $depFolder -token $token -masks @('Apps') | Where-Object { $_ })
                    Write-Host "Get-DependenciesFromCurrentBuild left $($downloaded.Count) app file(s) in $depFolder for project $project`: $($downloaded -join ', ')"
                    $downloadedCount += $downloaded.Count
                }
                catch {
                    Write-Host "::warning::Could not download same-repo project dependencies for the Linux fast lane build of project $project ($($_.Exception.Message)); apps depending on them will fail to compile on the Linux fast lane."
                }
            }

            if ($downloadedCount -gt 0) {
                $linuxDependencySubdir = $sanitizedProject
            }
        }

        foreach($buildMode in $buildModes) {
            # GitHub Actions expressions have no string-replace function, so this can't be
            # computed inline in workflow YAML - done here in PowerShell (which has
            # .Replace()) and carried through the matrix instead, so both the BuildLinux job
            # (passes it to bc-linux as the upload suffix) and the PublishLinuxArtifacts job
            # (uses it to find that same upload again) read the identical precomputed value
            # off the same matrix entry, with no risk of the two independently-written
            # expressions drifting out of sync.
            $linuxArtifactNameSuffix = ''
            if ($linuxFastLane) {
                $linuxArtifactNameSuffix = "$($project.Replace('\','_').Replace('/','_'))-$buildMode"
            }
            $buildDimensions += @{
                project = $project
                projectName = $projectSettings.projectName
                buildMode = $buildMode
                gitHubRunner = $gitHubRunner
                githubRunnerShell = $githubRunnerShell
                linuxFastLane = $linuxFastLane
                linuxBcVersion = $linuxBcVersion
                linuxAlToolVersion = $linuxAlToolVersion
                linuxCountry = $projectSettings.country
                linuxAppDirs = $linuxAppDirs
                linuxTestAppDirs = $linuxTestAppDirs
                linuxCodeunitRange = $linuxCodeunitRange
                linuxDependencySubdir = $linuxDependencySubdir
                linuxArtifactNameSuffix = $linuxArtifactNameSuffix
                linuxAppVersionMajorMinor = $linuxAppVersionMajorMinor
                linuxAppVersionBuild = $linuxAppVersionBuild
                linuxAppVersionRevision = $linuxAppVersionRevision
                artifact = $artifact
                artifactCacheKey = $artifactCacheKey
            }
        }
    }

    return @(, $buildDimensions) # force array
}

<#
.Synopsis
    Analyzes a folder for AL-Go projects and determines the build order of these projects.

.Description
    Analyzes a folder for AL-Go projects and determines the build order of these projects.
    The build order is determined by the project dependencies and the projects that have been modified.

.Outputs
    The function returns the following values:
    - projects: An array of all projects found in the folder
    - modifiedProjects: An array of projects that have been modified
    - projectsToBuild: An array of projects that need to be built
    - projectDependencies: A hashtable with the project dependencies
    - projectsOrderToBuild: An array of build dimensions, each build dimension contains the following properties:
        - projects: An array of projects to build
        - projectsCount: The number of projects to build
        - buildDimensions: An array of build dimensions, to be used in a build matrix. Properties of the build dimension are:
            - project: The project to build
            - buildMode: The build mode to use

.PARAMETER supportsLinuxFastLane
    Whether the calling workflow has a job that consumes buildDimensionsLinux. Defaults to $true
    for direct/test callers of this function; the DetermineProjectsToBuild action itself always
    passes this explicitly, defaulting to $false for every workflow except PullRequestHandler, so
    a linuxFastLane-enabled project ends up in buildDimensions instead of being dropped from the
    build entirely.
#>
function Get-ProjectsToBuild {
    param (
        [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
        $baseFolder,
        [Parameter(HelpMessage = "Whether a full build is required", Mandatory = $false)]
        [bool] $buildAllProjects = $true,
        [Parameter(HelpMessage = "An array of changed files paths, used to filter the projects to build", Mandatory = $false)]
        [string[]] $modifiedFiles = @(),
        [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
        [int] $maxBuildDepth = 0,
        [Parameter(HelpMessage = "Token used to access dependency repositories (e.g. appDependencyProbingPaths for the Linux fast lane)", Mandatory = $false)]
        $token,
        [Parameter(HelpMessage = "Whether the calling workflow has a job that consumes buildDimensionsLinux. When false, projects with linuxFastLane enabled are folded back into the regular buildDimensions instead of being dropped silently.", Mandatory = $false)]
        [bool] $supportsLinuxFastLane = $true,
        [Parameter(HelpMessage = "ID of the baseline workflow run, used as a fallback to resolve a same-repo project dependency for the Linux fast lane when the dependency project isn't built in the current run", Mandatory = $false)]
        $baselineWorkflowRunId = '0'
    )

    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

    Write-Host "Determining projects to build in $baseFolder"

    Push-Location $baseFolder
    try {
        $settings = $env:Settings | ConvertFrom-Json
        $projects = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $settings.projects)
        Write-Host "Found AL-Go Projects: $($projects -join ', ')"

        $modifiedProjects = @()
        $projectsToBuild = @()
        $projectsOrderToBuild = @()

        if ($projects) {
            # Calculate the full projects order
            $projectBuildInfo = AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects

            if ($modifiedFiles) {
                Write-Host "Calculating modified projects based on the modified files"

                #Include the base folder in the modified files
                $modifiedFilesFullPaths = @($modifiedFiles | ForEach-Object { return Join-Path $baseFolder $_ })
                $modifiedProjects = @($projects |
                                        Where-Object { ShouldBuildProject -baseFolder $baseFolder -project $_ -modifiedFiles $modifiedFilesFullPaths } |
                                        ForEach-Object { $_; if ($projectBuildInfo.AdditionalProjectsToBuild.Keys -contains $_) { $projectBuildInfo.AdditionalProjectsToBuild."$_" } } |
                                        Select-Object -Unique)
            }

            if($buildAllProjects) {
                Write-Host "Calculating full build matrix"
                $projectsToBuild = @($projects)
            }
            else {
                Write-Host "Calculating incremental build matrix"
                $projectsToBuild = @($modifiedProjects)
            }

            # Create a project order based on the projects to build
            foreach($depth in $projectBuildInfo.FullProjectsOrder) {
                $projectsOnDepth = @($depth.projects | Where-Object { $projectsToBuild -contains $_ })

                if ($projectsOnDepth) {
                    # Create build dimensions for the projects on the current depth
                    # buildDimensions only contains projects using the standard Windows pipeline; projects with linuxFastLane enabled are split into buildDimensionsLinux instead
                    $buildDimensions = CreateBuildDimensions -baseFolder $baseFolder -projects $projectsOnDepth -token $token -projectDependencies $projectBuildInfo.projectDependencies -baselineWorkflowRunId $baselineWorkflowRunId
                    if (-not $supportsLinuxFastLane) {
                        # The calling workflow has no job that consumes buildDimensionsLinux (e.g. CICD, CreateRelease -
                        # only PullRequestHandler does). Routing a project there anyway would mean it silently never
                        # builds: no job spawns, no error, no warning, PostProcess still reports success. Fold it back
                        # into the regular Windows dimension instead - "linuxFastLane is for PRs, not main" should mean
                        # the standard pipeline runs, not that the project vanishes.
                        $buildDimensions | Where-Object { $_.linuxFastLane } | ForEach-Object { $_.linuxFastLane = $false }
                    }
                    $windowsBuildDimensions = @($buildDimensions | Where-Object { -not $_.linuxFastLane })
                    $linuxBuildDimensions = @($buildDimensions | Where-Object { $_.linuxFastLane })
                    $projectsOrderToBuild += @{
                        projects = $projectsOnDepth
                        projectsCount = $projectsOnDepth.Count
                        buildDimensions = ProtectEmptyBuildDimensions -dimensions $windowsBuildDimensions
                        # GitHub Actions expressions have no length()/array-count function, so the count is precomputed here for the if: conditions gating the Build/BuildLinux jobs
                        buildDimensionsCount = $windowsBuildDimensions.Count
                        buildDimensionsLinux = ProtectEmptyBuildDimensions -dimensions $linuxBuildDimensions
                        buildDimensionsLinuxCount = $linuxBuildDimensions.Count
                    }
                }
            }
        }

        if ($projectsOrderToBuild.Count -eq 0) {
            Write-Host "Did not find any projects to add to the build order, adding default values"
            $projectsOrderToBuild += @{
                projects = @()
                projectsCount = 0
                buildDimensions = ProtectEmptyBuildDimensions -dimensions @()
                buildDimensionsCount = 0
                buildDimensionsLinux = ProtectEmptyBuildDimensions -dimensions @()
                buildDimensionsLinuxCount = 0
            }
        }
        Write-Host "Projects to build: $($projectsToBuild -join ', ')"

        if($maxBuildDepth -and ($projectsOrderToBuild.Count -gt $maxBuildDepth)) {
            throw "The build depth is too deep, the maximum build depth is $maxBuildDepth. You need to run 'Update AL-Go System Files' to update the workflows"
        }

        return $projects, $modifiedProjects, $projectsToBuild, $projectBuildInfo.projectDependencies, $projectsOrderToBuild
    }
    finally {
        Pop-Location
    }
}

<#
.Synopsis
    Determines whether a full build is required and whether to publish artifacts from skipped projects based on the event and settings.
.Outputs
    A boolean indicating whether a full build is required and a boolean indicating whether to publish artifacts from skipped projects.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - Deprecated setting alwaysBuildAllProjects is set to true
    - property incrementalBuilds.onPull_Request is set to false for pull_request and pull_request_target events
    - property incrementalBuilds.onPush is set to false for push events
    - property incrementalBuilds.onSchedule is set to false for schedule events
    Skipped projects are published if:
    - The event is not a pull_request or pull_request_target event
#>
function Get-BuildAllProjectsBasedOnEventAndSettings {
    Param(
        [string] $ghEventName,
        [PSCustomObject] $settings
    )
    $buildAllProjects = $true
    $publishSkippedProjects = $true
    if ($ghEventName -eq 'pull_request' -or $ghEventName -eq 'pull_request_target') {
        # DEPRECATION: REMOVE AFTER October 1st 2025 --->
        if ($settings.PSObject.Properties.Name -eq 'alwaysBuildAllProjects' -and $settings.alwaysBuildAllProjects) {
            $buildAllProjects = $settings.alwaysBuildAllProjects
            Trace-DeprecationWarning -Message "alwaysBuildAllProjects is deprecated" -DeprecationTag "alwaysBuildAllProjects"
        }
        # <--- REMOVE AFTER October 1st 2025
        else {
            $buildAllProjects = !$settings.incrementalBuilds.onPull_Request
        }
        $publishSkippedProjects = $false
    }
    else {
        # onPush, onSchedule or onWorkflow_Dispatch
        if ($settings.incrementalBuilds.PSObject.Properties.Name -eq "on$GhEventName") {
            $buildAllProjects = !$settings.incrementalBuilds."on$GhEventName"
        }
    }
    return $buildAllProjects, $publishSkippedProjects
}

<#
.Synopsis
    Determines whether a full build is required.
.Outputs
    A boolean indicating whether a full build is required.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - The modified files contain a file that matches one of the fullBuildPatterns
#>
function IsFullBuildRequired {
    param(
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The modified files", Mandatory = $false)]
        [string[]] $modifiedFiles = @(),
        [Parameter(HelpMessage = "Full build patterns", Mandatory = $false)]
        [string[]] $fullBuildPatterns = @(),
        [string] $noticeMessage = ''
    )

    $settings = $env:Settings | ConvertFrom-Json

    if (!$modifiedFiles) {
        Write-Host "No modified files"
        return $false
    }

    $fullBuildPatterns += @(Join-Path '.github' '*.json')
    if($settings.fullBuildPatterns) {
        $fullBuildPatterns += $settings.fullBuildPatterns
    }

    #Include the base folder in the modified files
    $modifiedFiles = @($modifiedFiles | ForEach-Object { return Join-Path $baseFolder $_ })

    foreach($fullBuildFolder in $fullBuildPatterns) {
        # The Join-Path is needed to make sure the path has the correct slashes
        $fullBuildFolder = Join-Path $baseFolder $fullBuildFolder

        if ($modifiedFiles -like $fullBuildFolder) {
            if ($noticeMessage) {
                Write-Host "::notice::Changes to $fullBuildFolder detected, $noticeMessage"
            }
            else {
                Write-Host "Changes to $fullBuildFolder detected"
            }
            return $true
        }
    }
    Write-Host "No changes to full build patterns detected"
    return $false
}

<#
.Synopsis
    Determines whether all projects in a repository should be built
.Outputs
    A boolean indicating whether a full build is required.
.Description
    Determines whether a full build is required.
    A full build is required if:
    - The modified files contain a file that matches one of the fullBuildPatterns
#>
function Get-BuildAllProjects {
    param(
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The modified files", Mandatory = $false)]
        [string[]] $modifiedFiles = @()
    )

    return (IsFullBuildRequired -baseFolder $baseFolder -modifiedFiles $modifiedFiles -noticeMessage "building everything")
}

<#
.Synopsis
    Determines whether all apps in a project should be built
.Outputs
    A boolean indicating whether all apps in a project should be built.
.Description
    Determines whether all apps in a project should be built.
    All apps should be built if:
    - The modified files contain a file that matches one of the fullBuildPatterns
    - The .AL-Go/settings.json file has been modified
#>
function Get-BuildAllApps {
    param(
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The project", Mandatory = $false)]
        [string] $project = '',
        [Parameter(HelpMessage = "The modified files", Mandatory = $false)]
        [string[]] $modifiedFiles = @()
    )

    if (IsFullBuildRequired -baseFolder $baseFolder -modifiedFiles $modifiedFiles) {
        # Notice already given in Initialize
        return $true
    }
    if ($project) {
        $ALGoSettingsFile = @(Join-Path $project '.AL-Go/settings.json')
    }
    else {
        $ALGoSettingsFile = @('.AL-Go/settings.json')
    }
    return (IsFullBuildRequired -baseFolder $baseFolder -modifiedFiles $modifiedFiles -fullBuildPatterns @($ALGoSettingsFile) -noticeMessage "building all apps")
}

<#
.Synopsis
    Converts a project-relative folder path to a repo-relative path.
.Description
    Converts a project-relative folder path (from settings.appFolders etc.) to a repo-relative path
    that matches the format used by skipFolders (produced by GetFoldersFromAllProjects).
    Settings folders may use ../ to reference paths above the project folder,
    so the function resolves to an absolute path first, then strips the base folder prefix
    to produce a clean repo-relative path.
.Parameter folder
    The project-relative folder path to convert (e.g. '.\app' or '..\..\..\src\Apps\MyApp\App').
.Parameter projectPath
    The absolute path to the project directory.
.Parameter baseFolder
    The absolute path to the repository root.
.Outputs
    A repo-relative path string, or $null if the folder cannot be resolved or is outside the base folder.
#>
function ConvertTo-RepoRelativePath {
    param(
        [string] $folder,
        [string] $projectPath,
        [string] $baseFolder
    )
    $fullPath = Join-Path $projectPath $folder -Resolve -ErrorAction SilentlyContinue
    if (-not $fullPath) {
        return $null
    }
    $normalizedBase = $baseFolder.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($normalizedBase.Length)
    }
    return $null
}

<#
.Synopsis
    Downloads unmodified artifacts from the baseline workflow run
.Outputs
    An array of objects containing the type, mask and a list of downloaded app file names.
.Description
    Downloads unmodified artifacts from the baseline workflow run
    - Downloads the artifacts (apps, testapps and bcpttestapps) for the specified project and build mode from the last known good build.
    - Copies the downloaded artifacts to the build artifact folder.
#>
function Get-UnmodifiedAppsFromBaselineWorkflowRun {
    Param(
        [Parameter(HelpMessage = "The GitHub token to use for downloading artifacts", Mandatory = $true)]
        [String] $token,
        [Parameter(HelpMessage = "The resolved AL-Go Project Settings", Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(HelpMessage = "The base folder", Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(HelpMessage = "The current project", Mandatory = $false)]
        [string] $project = '',
        [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $true)]
        [string] $baselineWorkflowRunId,
        [Parameter(HelpMessage = "Array of modified files in the repository (all projects)", Mandatory = $false)]
        [string[]] $modifiedFiles = @(),
        [Parameter(HelpMessage = "The build artifact folder", Mandatory = $true)]
        [string] $buildArtifactFolder,
        [Parameter(HelpMessage = "The build mode", Mandatory = $true)]
        [string] $buildMode,
        [Parameter(HelpMessage = "The project path", Mandatory = $true)]
        [string] $projectPath
    )

    $skipFolders = @()
    $unknownDependencies = @()
    $knownApps = @()
    $allFolders = @(GetFoldersFromAllProjects -baseFolder $baseFolder | ForEach-Object { $_.Replace('\', $([System.IO.Path]::DirectorySeparatorChar)).Replace('/', $([System.IO.Path]::DirectorySeparatorChar)) } )
    $modifiedFolders = @($allFolders | Where-Object {
        $modifiedFiles -like "$($_)$([System.IO.Path]::DirectorySeparatorChar)*"
    })
    OutputMessageAndArray -message "Modified folders" -arrayOfStrings $modifiedFolders
    Sort-AppFoldersByDependencies -appFolders $allFolders -baseFolder $baseFolder -skippedApps ([ref] $skipFolders) -unknownDependencies ([ref]$unknownDependencies) -knownApps ([ref] $knownApps) -selectSubordinates $modifiedFolders | Out-Null
    OutputMessageAndArray -message "Skip folders" -arrayOfStrings $skipFolders

    $downloadAppFolders = @($settings.appFolders | Where-Object { $skipFolders -contains (ConvertTo-RepoRelativePath -folder $_ -projectPath $projectPath -baseFolder $baseFolder) })
    $downloadTestFolders = @($settings.testFolders | Where-Object { $skipFolders -contains (ConvertTo-RepoRelativePath -folder $_ -projectPath $projectPath -baseFolder $baseFolder) })
    $downloadBcptTestFolders = @($settings.bcptTestFolders | Where-Object { $skipFolders -contains (ConvertTo-RepoRelativePath -folder $_ -projectPath $projectPath -baseFolder $baseFolder) })

    OutputMessageAndArray -message "Download appFolders" -arrayOfStrings $downloadAppFolders
    OutputMessageAndArray -message "Download testFolders" -arrayOfStrings $downloadTestFolders
    OutputMessageAndArray -message "Download bcptTestFolders" -arrayOfStrings $downloadBcptTestFolders

    if ($project) { $projectName = $project } else { $projectName = $env:GITHUB_REPOSITORY -replace '.+/' }
    # Download missing apps - or add then to build folders if the artifact doesn't exist
    $appsToDownload = [ordered]@{
        "appFolders" = @{
            "Mask" = "Apps"
            "Downloads" = $downloadAppFolders
            "Downloaded" = 0
        }
        "testFolders" = @{
            "Mask" = "TestApps"
            "Downloads" = $downloadTestFolders
            "Downloaded" = 0
        }
        "bcptTestFolders" = @{
            "Mask" = "TestApps"
            "Downloads" = $downloadBcptTestFolders
            "Downloaded" = 0
        }
    }
    $additionalDataForTelemetry = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
    $appsToDownload.Keys | ForEach-Object {
        $appType = $_
        $mask = $appsToDownload."$appType".Mask
        $downloads = $appsToDownload."$appType".Downloads
        $thisArtifactFolder = Join-Path $buildArtifactFolder $mask
        if (!(Test-Path $thisArtifactFolder)) {
            New-Item $thisArtifactFolder -ItemType Directory | Out-Null
        }
        if ($downloads) {
            Write-Host "Downloading from $mask"
            $tempFolder = NewTemporaryFolder
            if ($buildMode -eq 'Default') {
                $artifactMask = $mask
            }
            else {
                $artifactMask = "$buildMode$mask"
            }
            $runArtifact = GetArtifactsFromWorkflowRun -workflowRun $baselineWorkflowRunId -token $token -api_url $env:GITHUB_API_URL -repository $env:GITHUB_REPOSITORY -mask $artifactMask -projects $projectName
            if ($runArtifact) {
                if ($runArtifact -is [Array]) {
                    throw "Multiple artifacts found with mask $artifactMask for project $projectName"
                }
                $file = DownloadArtifact -path $tempFolder -token $token -artifact $runArtifact
                $artifactFolder = Join-Path $tempFolder $mask
                Expand-Archive -Path $file -DestinationPath $artifactFolder -Force
                Remove-Item -Path $file -Force
                $downloads | ForEach-Object {
                    $appJsonPath = Join-Path $projectPath "$_/app.json"
                    $appJson = Get-Content -Encoding UTF8 -Path $appJsonPath -Raw | ConvertFrom-Json
                    $appName = ("$($appJson.Publisher)_$($appJson.Name)".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '') + "_*.*.*.*.app"
                    $appPath = Join-Path $artifactFolder $appName
                    if (Test-Path $appPath) {
                        $item = Get-Item -Path $appPath
                        Write-Host "Copy $($item.Name) to build folders"
                        Copy-Item -Path $item.FullName -Destination $thisArtifactFolder -Force
                        $appsToDownload."$appType".Downloaded++
                    }
                }
            }
            Remove-Item -Path $tempFolder -Recurse -force
        }
        $additionalDataForTelemetry.Add("$($appType)ToDownload", $appsToDownload."$appType".Downloads.Count)
        $additionalDataForTelemetry.Add("$($appType)Downloaded", $appsToDownload."$appType".Downloaded)
    }
    Trace-Information -Message "Incremental builds (apps)" -AdditionalData $additionalDataForTelemetry
}

Export-ModuleMember *-*
