Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of dependency apps", Mandatory = $false)]
    [string] $dependencyAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of dependency test apps", Mandatory = $false)]
    [string] $dependencyTestAppsJson = '',
    [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowRunId = '0',
    [Parameter(HelpMessage = "SHA of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowSHA = '',
    [Parameter(HelpMessage = "Path to folder containing previous release apps for AppSourceCop baseline", Mandatory = $false)]
    [string] $previousAppsPath = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "..\.Modules\CompileFromWorkspace.psm1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

# ANALYZE - Analyze the repository and determine settings
$baseFolder = (Get-BasePath)
if ($project -eq ".") { $project = "" }
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting
$settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

# Check if there are any app folders or test app folders to compile
if ($settings.appFolders.Count -eq 0 -and $settings.testFolders.Count -eq 0 -and $settings.bcptTestFolders.Count -eq 0) {
    Write-Host "No app folders or test app folders specified for compilation. Skipping compilation step."
    return
}

$projectFolder = Join-Path $baseFolder $project
Push-Location $projectFolder
try {
    # Set up output folders
    $buildArtifactFolder = Join-Path $projectFolder ".buildartifacts"
    $appOutputFolder = Join-Path $buildArtifactFolder "Apps"
    $testAppOutputFolder = Join-Path $buildArtifactFolder "TestApps"
    if (-not (Test-Path $buildArtifactFolder)) {
        New-Item $buildArtifactFolder -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $appOutputFolder)) {
        New-Item $appOutputFolder -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $testAppOutputFolder)) {
        New-Item $testAppOutputFolder -ItemType Directory -Force | Out-Null
    }

    # Check for precompile and postcompile overrides
    $scriptOverrides = Get-ScriptOverrides -ALGoFolderName (Join-Path $projectFolder ".AL-Go") -OverrideScriptNames @("PreCompileApp", "PostCompileApp")
    $scriptOverrides.Keys | ForEach-Object { Trace-Information -Message "Using override for $_" }

    # Prepare build metadata
    $buildMetadata = Get-BuildMetadata

    # Get version number
    $versionNumber = Get-VersionNumber -Settings $settings

    # Get ruleset file if specified
    $rulesetPath = $settings.rulesetFile
    if ($settings.rulesetFile) {
        $rulesetPath = Join-Path $projectFolder $settings.rulesetFile -Resolve
        if (-not (Test-Path $rulesetPath)) {
            throw "Ruleset file specified in settings.rulesetFile not found at path '$rulesetPath'."
        }
    }

    # Read existing install apps and test apps from JSON files
    $dependencyApps = @()
    $dependencyTestApps = @()

    if ($dependencyAppsJson -and (Test-Path $dependencyAppsJson)) {
        try {
            $dependencyApps += Get-Content -Path $dependencyAppsJson | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$dependencyAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    if ($dependencyTestAppsJson -and (Test-Path $dependencyTestAppsJson)) {
        try {
            $dependencyTestApps += Get-Content -Path $dependencyTestAppsJson | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file at path '$dependencyTestAppsJson'. Error: $($_.Exception.Message)"
        }
    }

    # Set up a compiler folder
    $containerName = GetContainerName($project)
    $cacheFolder = ""
    if ($settings.gitHubRunner -like "windows-*" -or $settings.gitHubRunner -like "ubuntu-*") {
        # On GitHub-hosted runners, use a folder in the runner temp directory for caching to speed up subsequent builds
        $cacheFolder = Join-Path $ENV:RUNNER_TEMP ".artifactcache"
    }
    $compilerFolder = New-BcCompilerFolder -artifactUrl $artifact -vsixFile $settings.vsixFile -containerName "$($containerName)compiler" -cacheFolder $cacheFolder
    $packageCachePath = Join-Path $compilerFolder "symbols"

    # Copy dependency apps and test apps to the package cache so the compiler can resolve them
    foreach ($appFile in ($dependencyApps + $dependencyTestApps)) {
        $appFile = $appFile.Trim('()')
        if ($appFile -and (Test-Path $appFile)) {
            Copy-Item -Path $appFile -Destination $packageCachePath -Force
            OutputDebug "Copied dependency app to package cache: $(Split-Path $appFile -Leaf)"
        }
        elseif ($appFile) {
            OutputWarning -message "Dependency app file not found: $appFile"
        }
    }

    # Incremental Builds - Determine which folders need to be built vs downloaded from baseline
    $appFoldersToBuild = $settings.appFolders
    $testFoldersToBuild = $settings.testFolders
    $bcptTestFoldersToBuild = $settings.bcptTestFolders

    if ($baselineWorkflowSHA -and $baselineWorkflowRunId -ne '0' -and $settings.incrementalBuilds.mode -eq 'modifiedApps') {
        try {
            $modifiedFiles = @(Get-ModifiedFiles -baselineSHA $baselineWorkflowSHA)
            OutputMessageAndArray -message "Modified files" -arrayOfStrings $modifiedFiles
            $buildAll = Get-BuildAllApps -baseFolder $baseFolder -project $project -modifiedFiles $modifiedFiles
        }
        catch {
            OutputNotice -message "Failed to calculate modified files since $baselineWorkflowSHA, building all apps"
            $buildAll = $true
        }

        if (!$buildAll) {
            Write-Host "Incremental build: downloading unmodified apps from baseline workflow run"

            # Snapshot existing files before the download so we can identify what was added
            $appsBefore = @(Get-ChildItem -Path $appOutputFolder -Filter "*.app" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            $testAppsBefore = @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

            Get-UnmodifiedAppsFromBaselineWorkflowRun `
                -token $token `
                -settings $settings `
                -baseFolder $baseFolder `
                -project $project `
                -baselineWorkflowRunId $baselineWorkflowRunId `
                -modifiedFiles $modifiedFiles `
                -buildArtifactFolder $buildArtifactFolder `
                -buildMode $buildMode `
                -projectPath $projectFolder

            # Identify only the newly downloaded baseline apps (exclude files that existed before the download)
            $downloadedApps = @(Get-ChildItem -Path $appOutputFolder -Filter "*.app" -ErrorAction SilentlyContinue | Where-Object { $appsBefore -notcontains $_.Name })
            $downloadedTestApps = @(Get-ChildItem -Path $testAppOutputFolder -Filter "*.app" -ErrorAction SilentlyContinue | Where-Object { $testAppsBefore -notcontains $_.Name })

            # Copy downloaded baseline apps to the package cache so the compiler can resolve them as dependencies
            ($downloadedApps + $downloadedTestApps) | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $packageCachePath -Force
            }

            # Filter folders: only compile folders whose app was NOT already downloaded from the baseline
            $downloadedAppNames = @($downloadedApps + $downloadedTestApps | ForEach-Object { $_.Name })
            $appFoldersToBuild = @($settings.appFolders | Where-Object { -not (Test-BaselineAppDownloaded -folder (Join-Path $projectFolder $_) -downloadedAppNames $downloadedAppNames) })
            $testFoldersToBuild = @($settings.testFolders | Where-Object { -not (Test-BaselineAppDownloaded -folder (Join-Path $projectFolder $_) -downloadedAppNames $downloadedAppNames) })
            $bcptTestFoldersToBuild = @($settings.bcptTestFolders | Where-Object { -not (Test-BaselineAppDownloaded -folder (Join-Path $projectFolder $_) -downloadedAppNames $downloadedAppNames) })

            OutputMessageAndArray -message "Folders to compile (apps)" -arrayOfStrings $appFoldersToBuild
            OutputMessageAndArray -message "Folders to compile (test)" -arrayOfStrings $testFoldersToBuild
            OutputMessageAndArray -message "Folders to compile (bcpt)" -arrayOfStrings $bcptTestFoldersToBuild
        }
    }

    if ($settings.enableAppSourceCop) {
        # Collect baseline apps for upgrade testing (only when skipUpgrade is false)
        $baselineApps = @()
        if ((-not $settings.skipUpgrade) -and $previousAppsPath -and (Test-Path $previousAppsPath)) {
            $baselineApps = @(Get-ChildItem -Path $previousAppsPath -Recurse -Filter "*.app" | ForEach-Object { $_.FullName })
            if ($baselineApps.Count -gt 0) {
                # Copy baseline apps to the package cache so AppSourceCop can resolve them alongside their dependencies
                $baselineApps | ForEach-Object {
                    Copy-Item -Path $_ -Destination $packageCachePath -Force
                }
            }
        }

        # Generate AppSourceCop.json with mandatory affixes / obsoleteTag settings (always when AppSourceCop is enabled)
        # When baseline apps are available, also include the baseline version + package cache path for breaking change detection
        New-AppSourceCopJson -AppFolders $settings.appFolders -BaselineApps $baselineApps -BaselinePackageCachePath $packageCachePath -CompilerFolder $compilerFolder -Settings $settings
    }

    # Update the app jsons with version number (and other properties) from the app manifest files
    Update-AppJsonProperties -Folders ($settings.appFolders + $settings.testFolders + $settings.bcptTestFolders) `
        -MajorMinorVersion $versionNumber.MajorMinorVersion -BuildNumber $versionNumber.BuildNumber -RevisionNumber $versionNumber.RevisionNumber `
        -BuildBy $buildMetadata.BuildBy -BuildUrl $buildMetadata.BuildUrl

    # Collect common parameters for Build-AppsInWorkspace
    $buildParams = @{
        CompilerFolder              = $compilerFolder
        PackageCachePath            = $packageCachePath
        LogDirectory                = $buildArtifactFolder
        Ruleset                     = $rulesetPath
        AssemblyProbingPaths        = (Get-AssemblyProbingPaths -CompilerFolder $compilerFolder)
        PreprocessorSymbols         = $settings.preprocessorSymbols
        Features                    = $settings.features
        MaxCpuCount                 = $settings.workspaceCompilation.parallelism
        SourceRepositoryUrl         = $buildMetadata.SourceRepositoryUrl
        SourceCommit                = $buildMetadata.SourceCommit
        ReportSuppressedDiagnostics = $settings.reportSuppressedDiagnostics
        EnableExternalRulesets      = $settings.enableExternalRulesets
        PreCompileApp               = $scriptOverrides['PreCompileApp']
        PostCompileApp              = $scriptOverrides['PostCompileApp']
        Analyzers                   = (Get-CodeAnalyzers -Settings $settings)
        CustomAnalyzers             = (Get-CustomAnalyzers -Settings $settings -CompilerFolder $compilerFolder)
    }

    # Start compilation - only compile folders that need building (all in full build, modified-only in incremental)
    $appFiles = @()
    $testAppFiles = @()
    $bcptTestAppFiles = @()
    try {
        if ($appFoldersToBuild.Count -gt 0) {
            # Compile Apps
            $appFiles = Build-AppsInWorkspace @buildParams `
                -Folders $appFoldersToBuild `
                -OutFolder $appOutputFolder `
                -AppType 'app'
        }

        if ($testFoldersToBuild.Count -gt 0) {
            if (-not ($settings.enableCodeAnalyzersOnTestApps)) {
                $buildParams.Analyzers = @()
            }

            # Compile Test Apps
            $testAppFiles = Build-AppsInWorkspace @buildParams `
                -Folders $testFoldersToBuild `
                -OutFolder $testAppOutputFolder `
                -AppType 'testApp'
        }

        if ($bcptTestFoldersToBuild.Count -gt 0) {
            if (-not ($settings.enableCodeAnalyzersOnTestApps)) {
                $buildParams.Analyzers = @()
            }

            # Compile BCPT Test Apps
            $bcptTestAppFiles = Build-AppsInWorkspace @buildParams `
                -Folders $bcptTestFoldersToBuild `
                -OutFolder $testAppOutputFolder `
                -AppType 'bcptApp'
        }

    } finally {
        New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath (Join-Path $projectFolder "BuildOutput.txt") -DisplayInConsole -FailOn $settings.failOn
    }

    Trace-Information -message "Compilation completed. Compiled $(@($appFiles).Count) apps, $(@($testAppFiles).Count) test apps and $(@($bcptTestAppFiles).Count) BCPT test apps."
} finally {
    Pop-Location
}
