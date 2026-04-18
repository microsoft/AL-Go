[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'buildMode', Justification = 'Accepted from workflow; reserved for future incremental build support')]
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
    [string] $baselineWorkflowSHA = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "..\.Modules\CompileFromWorkspace.psm1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking

# ANALYZE - Analyze the repository and determine settings
$baseFolder = (Get-BasePath)
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting
$settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

# Check if there are any app folders or test app folders to compile
if ($settings.appFolders.Count -eq 0 -and $settings.testFolders.Count -eq 0) {
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

    # Set up the compiler folder
    if ($settings.vsixFile) {
        OutputWarning "The 'vsixFile' setting is ignored when workspace compilation is enabled. The AL compiler is installed from NuGet instead."
    }
    # TEMPORARY: Download custom nupkg for testing workspace restore
    $releaseBaseUrl = "https://github.com/Aholstrup1-PersonalOrg/BugBash7/releases/download/ALTool"
    $localNugetSource = Join-Path $ENV:RUNNER_TEMP "custom-nuget"
    New-Item -Path $localNugetSource -ItemType Directory -Force | Out-Null
    @(
        "Microsoft.Dynamics.BusinessCentral.Development.Tools.18.0.0-beta.nupkg",
        "Microsoft.Dynamics.BusinessCentral.Development.Tools.Linux.18.0.0-beta.nupkg",
        "Microsoft.Dynamics.BusinessCentral.Development.Tools.Win.18.0.0-beta.nupkg",
        "Microsoft.Dynamics.BusinessCentral.Development.Tools.Altpgen.18.0.0-beta.nupkg"
    ) | ForEach-Object {
        Invoke-WebRequest -Uri "$releaseBaseUrl/$_" -OutFile (Join-Path $localNugetSource $_)
    }
    OutputColor "Downloaded custom AL compiler nupkgs for testing" -Color Yellow

    $containerName = GetContainerName($project)
    $compilerFolder = Join-Path $ENV:RUNNER_TEMP "$($containerName)compiler"
    Install-ALCompiler -CompilerFolder $compilerFolder -CompilerVersion "18.0.0-beta" -AdditionalNuGetSource $localNugetSource
    $packageCachePath = Join-Path $compilerFolder "symbols"

    # Get AL tool path early — needed for workspace restore and workspace creation
    $alToolPath = Get-ALTool -CompilerFolder $compilerFolder

    # Copy project dependency apps to the package cache BEFORE restore so the restore can skip them
    foreach ($appFile in $dependencyApps) {
        $appFile = $appFile.Trim('()')
        if ($appFile -and (Test-Path $appFile)) {
            Copy-Item -Path $appFile -Destination $packageCachePath -Force
            OutputDebug "Copied dependency app to package cache: $(Split-Path $appFile -Leaf)"
        }
    }

    # Create workspace file and restore any remaining dependencies from NuGet feeds
    $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
    $workspaceFile = Join-Path $projectFolder "tempWorkspace$datetimeStamp.code-workspace"
    New-WorkspaceFromFolders -Folders ($settings.appFolders + $settings.testFolders) -WorkspaceFile $workspaceFile -AltoolPath $alToolPath

    # Download only missing symbols from NuGet feeds — already-cached packages are skipped
    Invoke-WorkspaceRestore -ALToolPath $alToolPath -WorkspaceFile $workspaceFile -PackageCachePath $packageCachePath -Country $settings.country

    # Optionally install assembly probing DLLs (only needed for apps referencing .NET types)
    if ($settings.workspaceCompilation.includeAssemblyProbing) {
        DownloadAndImportBcContainerHelper
        Install-AssemblyProbingDLLs -ArtifactUrl $artifact -CompilerFolder $compilerFolder
    }

    # Incremental Builds - Determine unmodified apps from baseline workflow run if applicable
    if ($baselineWorkflowSHA -and $baselineWorkflowRunId -ne '0' -and $settings.incrementalBuilds.mode -eq 'modifiedApps') {
        #TODO: Implement support for incremental builds (AB#620492)
        Write-Host "Incremental builds based on modified apps is not yet implemented."
    }

    if ((-not $settings.skipUpgrade) -and $settings.enableAppSourceCop) {
        # TODO: Missing implementation of around using latest release as a baseline (skipUpgrade) / Appsourcecop.json baseline implementation (AB#620310)
        Write-Host "Checking for required upgrades using AppSourceCop..."
    }

    # Update the app jsons with version number (and other properties) from the app manifest files
    Update-AppJsonProperties -Folders ($settings.appFolders + $settings.testFolders) `
        -MajorMinorVersion $versionNumber.MajorMinorVersion -BuildNumber $versionNumber.BuildNumber -RevisionNumber $versionNumber.RevisionNumber `
        -BuildBy $buildMetadata.BuildBy -BuildUrl $buildMetadata.BuildUrl

    # Collect common parameters for Build-AppsInWorkspace
    $buildParams = @{
        CompilerFolder              = $compilerFolder
        WorkspaceFile               = $workspaceFile
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

    # Start compilation
    $appFiles = @()
    $testAppFiles = @()
    try {
        if ($settings.appFolders.Count -gt 0) {
            # Compile Apps
            $appFiles = Build-AppsInWorkspace @buildParams `
                -Folders $settings.appFolders `
                -OutFolder $appOutputFolder `
                -AppType 'app'
        }

        if ($settings.testFolders.Count -gt 0) {
            if (-not ($settings.enableCodeAnalyzersOnTestApps)) {
                $buildParams.Analyzers = @()
            }

            # Compile Test Apps
            $testAppFiles = Build-AppsInWorkspace @buildParams `
                -Folders $settings.testFolders `
                -OutFolder $testAppOutputFolder `
                -AppType 'testApp'
        }

    } finally {
        New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath (Join-Path $projectFolder "BuildOutput.txt") -DisplayInConsole -FailOn $settings.failOn
        Remove-Item $workspaceFile -Force -ErrorAction SilentlyContinue
    }

    # OUTPUT - Output the updated list of dependency apps and test apps to JSON files for downstream steps
    $dependencyApps += $appFiles
    $dependencyTestApps += $testAppFiles
    Trace-Information -message "Compilation completed. Compiled $(@($appFiles).Count) apps and $(@($testAppFiles).Count) test apps."

    ConvertTo-Json $dependencyApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $dependencyAppsJson
    ConvertTo-Json $dependencyTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $dependencyTestAppsJson
} finally {
    Pop-Location
}
