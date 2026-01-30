Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '',
    [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowRunId = '0',
    [Parameter(HelpMessage = "SHA of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowSHA = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "..\.Modules\CompileFromWorkspace.psm1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

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
Set-Location $projectFolder

# Set up output folders
$buildArtifactFolder = Join-Path $projectFolder ".buildartifacts"
New-Item $buildArtifactFolder -ItemType Directory | Out-Null
$appOutputFolder = Join-Path $buildArtifactFolder "Apps"
New-Item $appOutputFolder -ItemType Directory | Out-Null
$testAppOutputFolder = Join-Path $buildArtifactFolder "TestApps"
New-Item $testAppOutputFolder -ItemType Directory | Out-Null

# Check for precompile and postcompile overrides
$scriptOverrides = Get-ScriptOverrides -ALGoFolderName $projectFolder

# Determine which code analyzers to use
$analyzers = Get-CodeAnalyzers -Settings $settings

# Prepare build metadata
$buildMetadata = Get-BuildMetadata

# Collect preprocessor symbols
$preprocessorSymbols = @()
if ($settings.ContainsKey('preprocessorSymbols')) {
    $preprocessorSymbols += $settings.preprocessorSymbols
}

# Collect features
$features = @()
if ($settings.ContainsKey('features')) {
    $features += $settings.features
}

# Get version number
$versionNumber = Get-VersionNumber -Settings $settings

# Get assembly probing paths
$assemblyProbingPaths = Get-AssemblyProbingPaths -CompilerFolder $CompilerFolder

# Read existing install apps and test apps from JSON files
$installApps = $settings.installApps
$installTestApps = $settings.installTestApps

if ($installAppsJson -and (Test-Path $installAppsJson)) {
    try {
        $installApps += @(Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
    }
}

if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    try {
        $installTestApps += @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
    }
}

# Set up a compiler folder
$containerName = GetContainerName($project)
$compilerFolder = New-BcCompilerFolder -artifactUrl $artifact -containerName "$($containerName)compiler"

# Incremental Builds - Determine unmodified apps from baseline workflow run if applicable
if ($baselineWorkflowSHA -and $baselineWorkflowRunId -ne '0' -and $settings.incrementalBuilds.mode -eq 'modifiedApps') {
    # Incremental builds are enabled and we are only building modified apps
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
        Write-Host "Get unmodified apps from baseline workflow run"
        # Downloaded apps are placed in the build artifacts folder, which is detected by Run-AlPipeline, meaning only non-downloaded apps are built
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
    }

    # Print the content of the build artifacts folder for debugging purposes
    $buildArtifactContents = Get-ChildItem -Path $buildArtifactFolder -Recurse
    Write-Host "Build artifacts folder contents:"
    foreach ($item in $buildArtifactContents) {
        # Copy to the packagecache path
        Write-Host "Copying $($item.FullName) to package cache"
        Copy-Item -Path $item.FullName -Destination (Join-Path $compilerFolder "symbols") -Recurse -Force
    }
}

if ((-not $settings.skipUpgrade) -and $settings.enableAppSourceCop) {
    # TODO: Missing implementation of around using latest release as a baseline (skipUpgrade) / Appsourcecop.json baseline implementation
    Write-Host "Checking for required upgrades using AppSourceCop..."
}

# Start compilation
$appFiles = @()
$testAppFiles = @()
try {
    if ($settings.appFolders.Count -gt 0) {
        # COMPILE - Compiling apps and test apps
        $appFiles = Build-AppsInWorkspace `
            -Folders $settings.appFolders `
            -CompilerFolder $compilerFolder `
            -PackageCachePath (Join-Path $compilerFolder "symbols") `
            -OutFolder $appOutputFolder `
            -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
            -AssemblyProbingPaths $assemblyProbingPaths `
            -Analyzers $analyzers `
            -Preprocessorsymbols $preprocessorSymbols `
            -Features $features `
            -MajorMinorVersion $versionNumber.MajorMinorVersion `
            -BuildNumber $versionNumber.BuildNumber `
            -RevisionNumber $versionNumber.RevisionNumber `
            -MaxCpuCount $settings.workspaceCompilationParallelism `
            -SourceRepositoryUrl $buildMetadata.SourceRepositoryUrl `
            -SourceCommit $buildMetadata.SourceCommit `
            -BuildBy $buildMetadata.BuildBy `
            -BuildUrl $buildMetadata.BuildUrl `
            -ReportSuppressedDiagnostics:($settings.reportSuppressedDiagnostics) `
            -EnableExternalRulesets:($settings.enableExternalRulesets) `
            -AppType 'app' `
            -PreCompileApp $scriptOverrides.PreCompileApp `
            -PostCompileApp $scriptOverrides.PostCompileApp
    }

    if ($settings.testFolders.Count -gt 0) {
        if (-not $settings.enableCodeAnalyzersOnTestApps) {
            $analyzers = @()
        }

        $testAppFiles = Build-AppsInWorkspace `
            -Folders $settings.testFolders `
            -CompilerFolder $compilerFolder `
            -OutFolder $testAppOutputFolder `
            -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
            -AssemblyProbingPaths $assemblyProbingPaths `
            -Analyzers $analyzers `
            -Preprocessorsymbols $preprocessorSymbols `
            -Features $features `
            -MajorMinorVersion $versionNumber.MajorMinorVersion `
            -BuildNumber $versionNumber.BuildNumber `
            -RevisionNumber $versionNumber.RevisionNumber `
            -MaxCpuCount $settings.workspaceCompilationParallelism `
            -SourceRepositoryUrl $buildMetadata.SourceRepositoryUrl `
            -SourceCommit $buildMetadata.SourceCommit `
            -BuildBy $buildMetadata.BuildBy `
            -BuildUrl $buildMetadata.BuildUrl `
            -ReportSuppressedDiagnostics:($settings.reportSuppressedDiagnostics) `
            -EnableExternalRulesets:($settings.enableExternalRulesets) `
            -AppType 'testApp' `
            -PreCompileApp $scriptOverrides.PreCompileApp `
            -PostCompileApp $scriptOverrides.PostCompileApp
    }
} finally {
    New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath (Join-Path $projectFolder "BuildOutput.txt") -DisplayInConsole -FailOn $settings.failOn
}

# OUTPUT - Output the install apps and test apps as JSON
$installApps += $appFiles
$installTestApps += $testAppFiles
ConvertTo-Json $installApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installAppsJson
ConvertTo-Json $installTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installTestAppsJson