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
$installApps = @()
$installTestApps = @()

if ($installAppsJson -and (Test-Path $installAppsJson)) {
    try {
        $installApps += Get-Content -Path $installAppsJson | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
    }
}

if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    try {
        $installTestApps += Get-Content -Path $installTestAppsJson | ConvertFrom-Json
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
    #TODO: Implement support for incremental builds
    Write-Host "Incremental builds based on modified apps is not yet implemented."
}

if ((-not $settings.skipUpgrade) -and $settings.enableAppSourceCop) {
    # TODO: Missing implementation of around using latest release as a baseline (skipUpgrade) / Appsourcecop.json baseline implementation
    Write-Host "Checking for required upgrades using AppSourceCop..."
}

# Update the app jsons with version number (and other properties) from the app manifest files
Update-AppJsonProperties -Folders ($settings.appFolders + $settings.testFolders) `
    -MajorMinorVersion $versionNumber.MajorMinorVersion -BuildNumber $versionNumber.BuildNumber -RevisionNumber $versionNumber.RevisionNumber

# Collect common parameters for Build-AppsInWorkspace
$buildParams = @{
    CompilerFolder              = $compilerFolder
    PackageCachePath            = (Join-Path $compilerFolder "symbols")
    LogDirectory                = $buildArtifactFolder
    Ruleset                     = $rulesetPath
    AssemblyProbingPaths        = (Get-AssemblyProbingPaths -CompilerFolder $CompilerFolder)
    Preprocessorsymbols         = $settings.preprocessorSymbols
    Features                    = $settings.features
    MajorMinorVersion           = $versionNumber.MajorMinorVersion
    BuildNumber                 = $versionNumber.BuildNumber
    RevisionNumber              = $versionNumber.RevisionNumber
    MaxCpuCount                 = $settings.workspaceCompilationParallelism
    SourceRepositoryUrl         = $buildMetadata.SourceRepositoryUrl
    SourceCommit                = $buildMetadata.SourceCommit
    BuildBy                     = $buildMetadata.BuildBy
    BuildUrl                    = $buildMetadata.BuildUrl
    ReportSuppressedDiagnostics = $settings.reportSuppressedDiagnostics
    EnableExternalRulesets      = $settings.enableExternalRulesets
    PreCompileApp               = $scriptOverrides.PreCompileApp
    PostCompileApp              = $scriptOverrides.PostCompileApp
    Analyzers                   = (Get-CodeAnalyzers -Settings $settings)
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
}

# OUTPUT - Output the install apps and test apps as JSON
$installApps += $appFiles
$installTestApps += $testAppFiles
Trace-Information -message "Compilation completed. Compiled $(@($appFiles).Count) apps and $(@($testAppFiles).Count) test apps."

ConvertTo-Json $installApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installAppsJson
ConvertTo-Json $installTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installTestAppsJson