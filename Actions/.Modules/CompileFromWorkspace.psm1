Import-Module (Join-Path -Path $PSScriptRoot "./DebugLogHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../TelemetryHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../Github-Helper.psm1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

$script:alTool = $null
$script:alCompilerPackageName = "Microsoft.Dynamics.BusinessCentral.Development.Tools"

<#
.SYNOPSIS
    Resolves the AL compiler version to install.
.DESCRIPTION
    Determines the version constraint for the AL compiler NuGet package using this priority:
    1. Explicit version from settings (exact version or wildcard like "26.*")
    2. Major version derived from artifact URL (e.g. "26.*" from a v26 artifact)
    3. Latest available version ("*")
.PARAMETER CompilerVersion
    Optional explicit version from settings. Can be an exact version (e.g. "26.0.12345.67890")
    or a wildcard (e.g. "26.*").
.PARAMETER ArtifactUrl
    Optional artifact URL. The BC major version is extracted from the URL path to derive a
    version constraint (e.g. "26.*").
.OUTPUTS
    A version string suitable for 'dotnet tool install --version'.
#>
function Get-CompilerVersionConstraint {
    param(
        [Parameter(Mandatory = $false)]
        [string] $CompilerVersion = '',

        [Parameter(Mandatory = $false)]
        [string] $ArtifactUrl = ''
    )

    # 1. Explicit setting takes priority
    if ($CompilerVersion) {
        OutputDebug "Using compiler version from settings: $CompilerVersion"
        return $CompilerVersion
    }

    # 2. Derive runtime version from artifact URL
    # NuGet package is versioned by AL runtime version, not BC internal version.
    # The mapping is: runtime = BC internal major - 11 (e.g. BC 28.0 → runtime 17.0)
    if ($ArtifactUrl) {
        try {
            $versionSegment = $ArtifactUrl.Split('?')[0].Split('/')[4]
            $bcMajor = [int]($versionSegment.Split('.')[0])
            $runtimeMajor = $bcMajor - 11
            if ($runtimeMajor -gt 0) {
                $constraint = "$runtimeMajor.*"
                OutputDebug "Derived compiler version constraint from artifact URL (BC $bcMajor → runtime $runtimeMajor): $constraint"
                return $constraint
            }
        }
        catch {
            OutputDebug "Could not parse version from artifact URL '$ArtifactUrl': $_"
        }
    }

    # 3. Fall back to latest
    OutputDebug "No version constraint available. Using latest compiler version."
    return '*'
}

<#
.SYNOPSIS
    Installs the AL compiler from a NuGet package.
.DESCRIPTION
    Uses 'dotnet tool install' to install the AL compiler tool from the
    Microsoft.Dynamics.BusinessCentral.Development.Tools NuGet package.
    Creates a compiler folder with tool/ and symbols/ subfolders.

    Version is resolved in this order:
    1. Explicit compilerVersion setting
    2. Major version derived from artifact URL
    3. Latest available version
.PARAMETER CompilerFolder
    The root folder where the compiler will be installed.
.PARAMETER CompilerVersion
    Optional explicit version to install (from settings). Supports wildcards (e.g. "26.*").
.PARAMETER ArtifactUrl
    Optional artifact URL used to derive the BC major version for version matching.
.OUTPUTS
    The path to the compiler folder.
#>
function Install-ALCompiler {
    param(
        [Parameter(Mandatory = $false)]
        [string] $CompilerFolder = '',

        [Parameter(Mandatory = $false)]
        [string] $CompilerVersion = '',

        [Parameter(Mandatory = $false)]
        [string] $ArtifactUrl = '',

        [Parameter(Mandatory = $false)]
        [string] $AdditionalNuGetSource = ''
    )

    if (-not $CompilerFolder) {
        $CompilerFolder = Join-Path $ENV:RUNNER_TEMP "alcompiler"
    }

    $versionConstraint = Get-CompilerVersionConstraint -CompilerVersion $CompilerVersion -ArtifactUrl $ArtifactUrl
    $isExplicitVersion = [bool]$CompilerVersion

    $toolPath = Join-Path $CompilerFolder 'tool'
    $symbolsPath = Join-Path $CompilerFolder 'symbols'

    # Clean up any previous compiler folder to ensure idempotent installs
    if (Test-Path $CompilerFolder) {
        Remove-Item -Path $CompilerFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create folder structure
    New-Item -Path $CompilerFolder -ItemType Directory -Force | Out-Null
    New-Item -Path $toolPath -ItemType Directory -Force | Out-Null
    New-Item -Path $symbolsPath -ItemType Directory -Force | Out-Null

    OutputColor "Installing AL compiler $($script:alCompilerPackageName) version $versionConstraint..." -Color Green
    $arguments = @("tool", "install", "--tool-path", $toolPath, $script:alCompilerPackageName, "--version", $versionConstraint)
    if ($AdditionalNuGetSource) {
        $arguments += @("--add-source", $AdditionalNuGetSource)
    }
    try {
        RunAndCheck "dotnet" @arguments | Out-Host
    }
    catch {
        if ($isExplicitVersion) {
            throw
        }
        # Fall back to latest if the auto-derived version is not available on NuGet
        OutputWarning "Could not install compiler version '$versionConstraint'. Falling back to latest version."
        Remove-Item -Path $toolPath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $toolPath -ItemType Directory -Force | Out-Null
        $arguments = @("tool", "install", "--tool-path", $toolPath, $script:alCompilerPackageName)
        RunAndCheck "dotnet" @arguments | Out-Host
    }

    # Workaround: dotnet tool install places analyzer DLLs in the 'any' folder alongside the compiler,
    # but the al tool looks for them at '../Analyzers/' relative to that folder. Copy them to the expected location.
    $toolsNetFolder = Get-ChildItem -Path (Join-Path $toolPath ".store") -Recurse -Directory -Filter "net*" |
        Where-Object { Test-Path (Join-Path $_.FullName "any") } |
        Select-Object -First 1
    if ($toolsNetFolder) {
        $anyFolder = Join-Path $toolsNetFolder.FullName "any"
        $analyzersFolder = Join-Path $toolsNetFolder.FullName "Analyzers"
        if (-not (Test-Path $analyzersFolder)) {
            New-Item -Path $analyzersFolder -ItemType Directory -Force | Out-Null
            Get-ChildItem -Path $anyFolder -File | Where-Object { $_.Name -like '*Analyzers*' -or $_.Name -like '*Cop*' } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $analyzersFolder -Force
            }
            OutputDebug "Created Analyzers folder at $analyzersFolder"
        }
    }

    # Find and cache the al tool path
    if ($IsLinux) {
        $candidates = @("altool", "al")
    } else {
        $candidates = @("altool.exe", "al.exe")
    }
    foreach ($candidate in $candidates) {
        $alExe = Join-Path $toolPath $candidate
        if (Test-Path $alExe) {
            $script:alTool = $alExe
            break
        }
    }

    OutputColor "AL compiler installed to $toolPath" -Color Green
    return $CompilerFolder
}

<#
.SYNOPSIS
    Downloads missing external dependencies from NuGet feeds for all workspace projects.
.DESCRIPTION
    Invokes 'altool workspace restore' to resolve and download app dependencies
    from NuGet feeds into the package cache folder. The tool resolves the correct
    versions based on the compiler version and app.json dependencies.
.PARAMETER ALToolPath
    The path to the AL tool executable.
.PARAMETER WorkspaceFile
    The path to the workspace file describing the apps.
.PARAMETER PackageCachePath
    The folder where downloaded dependency .app files will be stored.
.PARAMETER Country
    The country/region code for symbol resolution (e.g. 'w1', 'us', 'dk'). Defaults to 'w1'.
#>
function Invoke-WorkspaceRestore {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ALToolPath,

        [Parameter(Mandatory = $true)]
        [string] $WorkspaceFile,

        [Parameter(Mandatory = $true)]
        [string] $PackageCachePath,

        [Parameter(Mandatory = $false)]
        [string] $Country = 'w1'
    )

    if (-not (Test-Path $PackageCachePath)) {
        New-Item -Path $PackageCachePath -ItemType Directory -Force | Out-Null
    }

    OutputColor "Restoring workspace dependencies (country: $Country)..." -Color Green
    $arguments = @("workspace", "restore", $WorkspaceFile, "--packagecachepath", $PackageCachePath, "--symbolscountryregion", $Country)
    RunAndCheck $ALToolPath @arguments | Out-Host
    OutputColor "Workspace dependencies restored to $PackageCachePath" -Color Green
}

<#
.SYNOPSIS
    Resolves symbol dependencies into the package cache.
.DESCRIPTION
    Downloads symbol .app files needed for compilation. Supports two sources:
    - 'nuget': Uses 'altool workspace restore' to download only referenced symbols from NuGet feeds.
    - 'artifact': Uses New-BcCompilerFolder to extract all symbols from the full BC artifact (legacy).
.PARAMETER SymbolsSource
    The source to resolve symbols from. 'nuget' (default) or 'artifact'.
.PARAMETER PackageCachePath
    The folder where symbol .app files will be placed.
.PARAMETER Folders
    Array of app and test folder paths to resolve dependencies for.
.PARAMETER Country
    Country/region code for symbol resolution (e.g. 'us', 'w1'). Defaults to 'w1'.
.PARAMETER ArtifactUrl
    The BC artifact URL. Required for the 'artifact' source.
.PARAMETER VsixFile
    Optional vsix file override. Only used with 'artifact' source.
.PARAMETER GitHubRunner
    The runner label. Only used with 'artifact' source for cache path.
#>
function Resolve-DependencySymbols {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('nuget', 'artifact')]
        [string] $SymbolsSource = 'nuget',

        [Parameter(Mandatory = $true)]
        [string] $PackageCachePath,

        [Parameter(Mandatory = $true)]
        [string[]] $Folders,

        [Parameter(Mandatory = $false)]
        [string] $Country = 'w1',

        [Parameter(Mandatory = $false)]
        [string] $ArtifactUrl = '',

        [Parameter(Mandatory = $false)]
        [string] $VsixFile = '',

        [Parameter(Mandatory = $false)]
        [string] $GitHubRunner = ''
    )

    if ($SymbolsSource -eq 'nuget') {
        $alToolPath = Get-ALTool
        $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
        $workspaceFile = Join-Path (Get-Location) "tempRestore$datetimeStamp.code-workspace"
        New-WorkspaceFromFolders -Folders $Folders -WorkspaceFile $workspaceFile -AltoolPath $alToolPath
        try {
            Invoke-WorkspaceRestore -ALToolPath $alToolPath -WorkspaceFile $workspaceFile -PackageCachePath $PackageCachePath -Country $Country
        }
        finally {
            Remove-Item $workspaceFile -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        DownloadAndImportBcContainerHelper
        $cacheFolder = ""
        if ($GitHubRunner -like "windows-*" -or $GitHubRunner -like "ubuntu-*") {
            $cacheFolder = Join-Path $ENV:RUNNER_TEMP ".artifactcache"
        }
        $legacyCompilerFolder = New-BcCompilerFolder -artifactUrl $ArtifactUrl -vsixFile $VsixFile -containerName "legacy" -cacheFolder $cacheFolder
        Get-ChildItem -Path (Join-Path $legacyCompilerFolder "symbols") -Filter "*.app" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $PackageCachePath -Force
        }
    }
}

<#
.SYNOPSIS
    Downloads and installs assembly probing DLLs from BC platform artifacts.
.DESCRIPTION
    Downloads the Business Central platform artifacts and extracts the DLLs
    needed for assembly probing during compilation. This is only needed when
    AL code references .NET types via the DotNet data type.
.PARAMETER ArtifactUrl
    The Business Central artifact URL to download platform DLLs from.
.PARAMETER CompilerFolder
    The compiler folder where DLLs will be installed under a 'dlls' subfolder.
#>
function Install-AssemblyProbingDLLs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArtifactUrl,

        [Parameter(Mandatory = $true)]
        [string] $CompilerFolder
    )

    OutputColor "Downloading assembly probing DLLs from platform artifacts..." -Color Green

    $artifactPaths = Download-Artifacts -artifactUrl $ArtifactUrl -includePlatform
    $platformArtifactPath = $artifactPaths[1]

    $dllsPath = Join-Path $CompilerFolder "dlls"
    New-Item -Path $dllsPath -ItemType Directory -Force | Out-Null

    # Copy Service tier DLLs
    $serviceTierFolder = Join-Path $platformArtifactPath "ServiceTier\*\Microsoft Dynamics NAV\*\Service" -Resolve
    Copy-Item -Path $serviceTierFolder -Filter '*.dll' -Destination $dllsPath -Recurse
    # Remove folders not needed for compilation
    Remove-Item -Path (Join-Path $dllsPath 'Service\Management') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $dllsPath 'Service\WindowsServiceInstaller') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $dllsPath 'Service\SideServices') -Recurse -Force -ErrorAction SilentlyContinue

    # Copy OpenXML DLL
    New-Item -Path (Join-Path $dllsPath 'OpenXML') -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $dllsPath 'Service\DocumentFormat.OpenXml.dll') -Destination (Join-Path $dllsPath 'OpenXML') -Force -ErrorAction SilentlyContinue

    # Copy Test Assemblies
    $testAssembliesFolder = Join-Path $platformArtifactPath "Test Assemblies" -Resolve
    $testAssembliesDestination = Join-Path $dllsPath "Test Assemblies"
    New-Item -Path $testAssembliesDestination -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $testAssembliesFolder 'Newtonsoft.Json.dll') -Destination $testAssembliesDestination -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $testAssembliesFolder 'Microsoft.Dynamics.Framework.UI.Client.dll') -Destination $testAssembliesDestination -Force

    # Copy Mock Assemblies
    $mockAssembliesFolder = Join-Path $testAssembliesFolder "Mock Assemblies" -Resolve
    Copy-Item -Path $mockAssembliesFolder -Filter '*.dll' -Destination $dllsPath -Recurse

    OutputColor "Assembly probing DLLs installed to $dllsPath" -Color Green
}

<#
.SYNOPSIS
    Gets the list of code analyzers to use for compilation.
.DESCRIPTION
    Returns an array of code analyzer names based on the settings provided.
    Supports CodeCop, AppSourceCop, PTECop, and UICop.
.PARAMETER Settings
    Hashtable containing the build settings with analyzer flags.
.OUTPUTS
    Array of analyzer names to use for compilation.
#>
function Get-CodeAnalyzers {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings
    )

    $analyzers = @()

    if ($Settings.enableCodeCop) {
        $analyzers += "CodeCop"
    }
    if ($Settings.enableAppSourceCop) {
        $analyzers += "AppSourceCop"
    }
    if ($Settings.enablePerTenantExtensionCop) {
        $analyzers += "PTECop"
    }
    if ($Settings.enableUICop) {
        $analyzers += "UICop"
    }

    return $analyzers
}

<#
.SYNOPSIS
    Gets the list of custom code analyzers to use for compilation.
.DESCRIPTION
    Returns an array of custom code analyzer paths based on the settings provided.
    If the custom code cop is a URL, it will be downloaded to the compiler folder and the local path will be returned.
.PARAMETER Settings
    Hashtable containing the build settings with custom code cop paths or URLs.
.PARAMETER CompilerFolder
    The folder where the AL compiler tool is located, used for downloading custom analyzers if URLs are provided.
.OUTPUTS
    Array of custom analyzer paths to use for compilation.
#>
function Get-CustomAnalyzers {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings,

        [Parameter(Mandatory = $true)]
        [string] $CompilerFolder
    )

    $analyzers = @()
    if (-not $Settings.CustomCodeCops -or $Settings.CustomCodeCops.Count -eq 0) {
        return $analyzers
    }

    # Find the Analyzers directory - check both new (dotnet tool) and old (vsix) structures
    $analyzerDownloadDir = Join-Path $CompilerFolder 'analyzers'
    if (-not (Test-Path $analyzerDownloadDir)) {
        $legacyBinPath = Join-Path $CompilerFolder 'compiler/extension/bin'
        if (Test-Path (Join-Path $legacyBinPath 'Analyzers')) {
            $analyzerDownloadDir = Join-Path $legacyBinPath 'Analyzers'
        }
        else {
            New-Item -Path $analyzerDownloadDir -ItemType Directory -Force | Out-Null
        }
    }

    foreach ($customCodeCop in $Settings.CustomCodeCops) {
        if ($customCodeCop -like 'https://*') {
            $analyzerFileName = Join-Path $analyzerDownloadDir (Split-Path $customCodeCop -Leaf)
            try {
                Invoke-WebRequest -Uri $customCodeCop -OutFile $analyzerFileName -ErrorAction Stop
            } catch {
                throw "Failed to download custom analyzer from '$customCodeCop': $($_.Exception.Message)"
            }
            $analyzers += $analyzerFileName
        }
        else {
            $analyzers += $customCodeCop
        }
    }

    return $analyzers
}

<#
.SYNOPSIS
    Gets build metadata for the current build environment.
.DESCRIPTION
    Returns a hashtable with build metadata including source repository URL, commit SHA,
    build system identifier, and build URL.
.OUTPUTS
    Hashtable with SourceRepositoryUrl, SourceCommit, BuildBy, and BuildUrl properties.
#>
function Get-BuildMetadata {
    # Running in GitHub Actions
    return @{
        SourceRepositoryUrl = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY"
        SourceCommit        = $env:GITHUB_SHA
        BuildBy             = "AL-Go for GitHub"
        BuildUrl            = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    }
}

<#
    .SYNOPSIS
    Gets the path to the AL compiler tool (al.exe or al).
    .DESCRIPTION
    Returns the cached path to the AL compiler tool set by Install-ALCompiler.
    For legacy compiler folders (vsix-based), pass the CompilerFolder parameter.
    .OUTPUTS
    The full path to the AL compiler tool.
#>
function Get-ALTool {
    param(
        [Parameter(Mandatory = $false)]
        [string] $CompilerFolder = ''
    )

    if ($script:alTool -and (Test-Path $script:alTool)) {
        return $script:alTool
    }

    if (-not $CompilerFolder) {
        throw "AL tool not found. Call Install-ALCompiler first."
    }

    # Fall back to legacy vsix-based path (compiler/extension/bin/<platform>/)
    if ($IsLinux) {
        $platformFolder = Join-Path $CompilerFolder "compiler/extension/bin/linux"
        $alExe = Join-Path $platformFolder "altool"
        if (-not (Test-Path $alExe)) {
            $alExe = Join-Path $platformFolder "al"
        }
    }
    else {
        $platformFolder = Join-Path $CompilerFolder "compiler/extension/bin/win32"
        $alExe = Join-Path $platformFolder "altool.exe"
        if (-not (Test-Path $alExe)) {
            $alExe = Join-Path $platformFolder "al.exe"
        }
    }

    if (-not (Test-Path $alExe)) {
        throw "Could not find AL tool in the compiler folder: $CompilerFolder"
    }
    $script:alTool = $alExe
    return $script:alTool
}

<#
.SYNOPSIS
    Compiles AL apps in a workspace using the ALTool.
.DESCRIPTION
    Compiles one or more AL app folders using workspace compilation from the ALTool.
    Supports parallel compilation, code analyzers, preprocessor symbols, and compiler features.
    Before calling this function, ensure that:
    1. A compiler folder has been created
    2. External dependencies have been fetched into the compiler folder symbols folder
    3. Baseline packages have been downloaded and AppSourceCop baseline packages set up (if applicable)
.PARAMETER Folders
    Array of app folder paths to compile.
.PARAMETER CompilerFolder
    Path to the compiler folder containing the ALTool and symbols.
.PARAMETER PackageCachePath
    Path to the package cache folder. Defaults to the compiler folder's symbols subfolder.
.PARAMETER OutFolder
    Path to the output folder for compiled .app files. Defaults to PackageCachePath.
.PARAMETER LogDirectory
    Path to the directory for compilation log files.
.PARAMETER MaxCpuCount
    Maximum number of parallel compilation processes. Defaults to 1.
.PARAMETER AssemblyProbingPaths
    Array of assembly probing paths for the compiler.
.PARAMETER Analyzers
    Array of code analyzer names to enable (e.g., CodeCop, UICop).
.PARAMETER CustomAnalyzers
    Array of paths to custom code analyzer DLLs.
.PARAMETER PreprocessorSymbols
    Array of preprocessor symbols to define during compilation.
.PARAMETER Features
    Array of compiler features to enable (e.g., LcgTranslationFile, TranslationFile, GenerateCaptions).
.PARAMETER GenerateReportLayout
    Switch to enable report layout generation during compilation.
.PARAMETER Ruleset
    Path to a custom ruleset file for code analysis.
.PARAMETER SourceRepositoryUrl
    URL of the source repository for build metadata.
.PARAMETER SourceCommit
    Commit SHA for build metadata.
.PARAMETER ReportSuppressedDiagnostics
    Switch to include suppressed diagnostics in the build output.
.PARAMETER EnableExternalRulesets
    Switch to enable external rulesets for code analysis.
.PARAMETER AppType
    Type of apps being compiled: 'app' or 'testApp'.
.PARAMETER PreCompileApp
    Scriptblock to execute before compiling each app.
.PARAMETER PostCompileApp
    Scriptblock to execute after compiling each app.
#>
function Build-AppsInWorkspace {
    param(
        # Mandatory parameters
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,
        [Parameter(Mandatory = $true)]
        [string]$CompilerFolder,
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceFile,
        [Parameter(Mandatory = $false)]
        [string]$PackageCachePath,
        [Parameter(Mandatory = $false)]
        [string]$OutFolder,
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory,
        # Optional parameters
        [Parameter(Mandatory = $false)]
        [int]$MaxCpuCount = 1,
        # Optional compiler parameters
        [Parameter(Mandatory = $false)]
        [string[]]$AssemblyProbingPaths,
        [Parameter(Mandatory = $false)]
        [string[]]$Analyzers,
        [Parameter(Mandatory = $false)]
        [string[]]$CustomAnalyzers,
        [Parameter(Mandatory = $false)]
        [string[]]$PreprocessorSymbols,
        [Parameter(Mandatory = $false)]
        [string[]]$Features,
        [Parameter(Mandatory = $false)]
        [switch]$GenerateReportLayout,
        [Parameter(Mandatory = $false)]
        [string]$Ruleset,
        [Parameter(Mandatory = $false)]
        [string]$SourceRepositoryUrl,
        [Parameter(Mandatory = $false)]
        [string]$SourceCommit,
        [Parameter(Mandatory = $false)]
        [switch]$ReportSuppressedDiagnostics,
        [Parameter(Mandatory = $false)]
        [switch]$EnableExternalRulesets,
        [Parameter(Mandatory = $false)]
        [ValidateSet('app', 'testApp')]
        [string]$AppType,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PreCompileApp,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PostCompileApp
    )

    # Get the package cache path. Use the compiler folder symbols subfolder if not specified
    if (-not $PackageCachePath) {
        $PackageCachePath = Join-Path $CompilerFolder "symbols"
    }

    # Determine the final output folder
    if (-not $OutFolder) {
        $OutputFolder = $PackageCachePath
    } else {
        $OutputFolder = $OutFolder
    }

    # Validate MaxCpuCount
    $maxAvailableProcesses = [System.Environment]::ProcessorCount
    if ($MaxCpuCount -gt $maxAvailableProcesses) {
        OutputWarning "Specified MaxCpuCount $MaxCpuCount is greater than available processors $maxAvailableProcesses. Using $maxAvailableProcesses instead."
        $MaxProcesses = $maxAvailableProcesses
    } elseif ($MaxCpuCount -lt 0) {
        $MaxProcesses = $maxAvailableProcesses
    } else {
        $MaxProcesses = $MaxCpuCount
    }

    # Get AL tool path
    $alToolPath = Get-ALTool -CompilerFolder $CompilerFolder

    # Reuse provided workspace file or create a new one
    $createdWorkspaceFile = $false
    if (-not $WorkspaceFile) {
        $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
        $WorkspaceFile = Join-Path (Get-Location) "tempWorkspace$datetimeStamp.code-workspace"
        New-WorkspaceFromFolders -Folders $Folders -WorkspaceFile $WorkspaceFile -AltoolPath $alToolPath
        $createdWorkspaceFile = $true
    }

    $compilationParameters = @{
        ALToolPath = $alToolPath
        WorkspaceFile = $WorkspaceFile
        PackageCachePath = $PackageCachePath
        OutFolder = $OutputFolder
        LogDirectory = $LogDirectory
        AssemblyProbingPaths = $AssemblyProbingPaths
        Analyzers = $Analyzers
        CustomAnalyzers = $CustomAnalyzers
        PreprocessorSymbols = $PreprocessorSymbols
        Features = $Features
        GenerateReportLayout = $GenerateReportLayout
        Ruleset = $Ruleset
        SourceRepositoryUrl = $SourceRepositoryUrl
        SourceCommit = $SourceCommit
        ReportSuppressedDiagnostics = $ReportSuppressedDiagnostics
        EnableExternalRulesets = $EnableExternalRulesets
        MaxCpuCount = $MaxProcesses
    }

    # Pre-Compile Apps - Invoke script override before compilation
    if ($PreCompileApp) {
        OutputDebug "Invoking Pre-Compile App Script..."
        Invoke-Command -ScriptBlock $PreCompileApp -ArgumentList $AppType, ([ref] $compilationParameters)
    }

    # Compile apps
    $appFiles = CompileAppsInWorkspace @compilationParameters

    # Post-Compile Apps - Invoke script override after compilation
    if ($PostCompileApp) {
        OutputDebug "Invoking Post-Compile App Script..."
        Invoke-Command -ScriptBlock $PostCompileApp -ArgumentList $appFiles, $AppType, $compilationParameters
    }

    # Remove the workspace file only if we created it
    if ($createdWorkspaceFile) {
        Remove-Item $WorkspaceFile -Force -ErrorAction SilentlyContinue
    }

    return $appFiles
}

<#
    .SYNOPSIS
    Copies compiled app files from the package cache to the output folder, and returns the list of generated app file paths.
    .DESCRIPTION
    Compares the files in the package cache before and after compilation to determine which app files were generated or updated by the compilation process. Copies those files to the output folder and returns their paths.
    .PARAMETER PackageCachePath
    The folder where the AL compiler outputs compiled app files (package cache).
    .PARAMETER OutputFolder
    The folder where the generated app files should be copied to.
    .PARAMETER FilesBeforeCompile
    A hashtable of file paths and their last write times before compilation, used to determine which files were generated or updated by the compilation process.
    .OUTPUTS
    Array of file paths for the generated app files that were copied to the output folder.
#>
function Copy-CompiledAppsToOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageCachePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        [Parameter(Mandatory = $true)]
        [hashtable]$FilesBeforeCompile
    )

    $generatedAppFiles = @()

    if (-not (Test-Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $filesInPackageCache = Get-ChildItem -Path $PackageCachePath -File -Filter "*.app"
    OutputArray -Message "Files in package cache after compilation:" -Array $filesInPackageCache -Debug

    # Find new or modified files by comparing timestamps
    $outputFiles = $filesInPackageCache | Where-Object {
        -not $FilesBeforeCompile.ContainsKey($_.FullName) -or
        $_.LastWriteTimeUtc -gt $FilesBeforeCompile[$_.FullName]
    }

    OutputDebug -message "Copying generated app files from package cache '$PackageCachePath' to output folder '$OutputFolder'"
    foreach ($file in $outputFiles) {
        $destinationPath = Join-Path $OutputFolder $file.Name
        $generatedAppFiles += $destinationPath
        if ($PackageCachePath -ne $OutputFolder) {
            Copy-Item -Path $file.FullName -Destination $destinationPath -Force
        }
    }

    return $generatedAppFiles
}

function CompileAppsInWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ALToolPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile,

        [Parameter(Mandatory = $true)]
        [int]$MaxCpuCount,

        [Parameter(Mandatory = $false)]
        [string]$PackageCachePath,

        [Parameter(Mandatory = $false)]
        [string[]]$AssemblyProbingPaths,

        [Parameter(Mandatory = $false)]
        [string[]]$Analyzers,

        [Parameter(Mandatory = $false)]
        [string[]]$CustomAnalyzers,

        [Parameter(Mandatory = $false)]
        [string[]]$PreprocessorSymbols,

        [Parameter(Mandatory = $false)]
        [string[]]$Features,

        [Parameter(Mandatory = $false)]
        [switch]$GenerateReportLayout,

        [Parameter(Mandatory = $false)]
        [string]$Ruleset,

        [Parameter(Mandatory = $false)]
        [string]$SourceRepositoryUrl,

        [Parameter(Mandatory = $false)]
        [string]$SourceCommit,

        [Parameter(Mandatory = $false)]
        [switch]$ReportSuppressedDiagnostics,

        [Parameter(Mandatory = $false)]
        [switch]$EnableExternalRulesets,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Error', 'Normal', 'Verbose', 'Warning')]
        [string]$LogLevel = 'Warning',

        [Parameter(Mandatory = $false)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $false)]
        [string]$OutFolder
    )

    # Check if the workspace file exists
    if (-not (Test-Path $WorkspaceFile)) {
        throw "The specified workspace file '$WorkspaceFile' does not exist."
    }

    # Build the command arguments dynamically
    $arguments = @("workspace", "compile", $WorkspaceFile)

    # Get list of files in the package cache path with their timestamps
    # Since we are outputting to the package cache path first, we can compare the files before and after compilation to determine which files were generated or updated by the compilation process.
    $filesBeforeCompile = @{}
    if ($PackageCachePath -and (Test-Path $PackageCachePath)) {
        Get-ChildItem -Path $PackageCachePath -File -Filter "*.app" | ForEach-Object {
            $filesBeforeCompile[$_.FullName] = $_.LastWriteTimeUtc
        }
    }

    # Add optional parameters only if they are provided
    if ($MaxCpuCount -and $MaxCpuCount -ne [System.Environment]::ProcessorCount) {
        $arguments += "--maxcpucount"
        $arguments += $MaxCpuCount.ToString()
    }

    if ($PackageCachePath) {
        $arguments += "--packagecachepath"
        $arguments += $PackageCachePath

        # Always output to package cache path first so compiled apps can be used as dependencies for other apps.
        # Once compilation is complete the generated app files will be copied to the output folder.
        $arguments += "--outfolder"
        $arguments += $PackageCachePath
    }

    if ($AssemblyProbingPaths -and $AssemblyProbingPaths.Count -gt 0) {
        $arguments += "--assemblyprobingpaths"
        $arguments += $AssemblyProbingPaths
    }

    if ($Analyzers -and $Analyzers.Count -gt 0) {
        $arguments += "--analyzers"
        $arguments += ($Analyzers -join ",")
    }

    if ($CustomAnalyzers -and $CustomAnalyzers.Count -gt 0) {
        $arguments += "--customanalyzers"
        $arguments += ($CustomAnalyzers -join ",")
    }

    if ($PreprocessorSymbols -and $PreprocessorSymbols.Count -gt 0) {
        $arguments += "--define"
        $arguments += ($PreprocessorSymbols -join ";")
    }

    if ($Features -and $Features.Count -gt 0) {
        $arguments += "--features"
        $arguments += ($Features -join ",")
    }

    if ($GenerateReportLayout.IsPresent) {
        $arguments += "--generatereportlayout"
    }

    if ($Ruleset) {
        $arguments += "--ruleset"
        $arguments += $Ruleset
    }

    if ($SourceRepositoryUrl) {
        $arguments += "--sourcerepositoryurl"
        $arguments += $SourceRepositoryUrl
    }

    if ($SourceCommit) {
        $arguments += "--sourcecommit"
        $arguments += $SourceCommit
    }

    if ($ReportSuppressedDiagnostics.IsPresent) {
        OutputWarning "--reportsuppresseddiagnostics is not yet supported and will be ignored."
    }

    if ($EnableExternalRulesets.IsPresent) {
        OutputWarning "--enableexternalrulesets is not yet supported and will be ignored."
    }

    if ($LogLevel) {
        $arguments += "--loglevel"
        $arguments += $LogLevel
    }

    if ($LogDirectory) {
        $arguments += "--logdirectory"
        $arguments += $LogDirectory
    } else {
        $defaultLogDir = Join-Path $OutFolder "Logs"
        $arguments += "--logdirectory"
        $arguments += $defaultLogDir
    }

    $generatedAppFiles = @()
    $originalEncoding = [Console]::OutputEncoding
    try {
        OutputColor "Executing: $ALToolPath $($arguments -join ' ')" -Color Green

        # Temporarily set console encoding to UTF-8 to handle special characters in output
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        RunAndCheck $ALToolPath @arguments | Out-Host

        OutputColor -message "Compilation completed successfully." -Color Green
    } catch {
        OutputColor -Message "Error during compilation: $_" -Color Red
        throw $_
    } finally {
        # Restore original encoding
        [Console]::OutputEncoding = $originalEncoding
    }

    $generatedAppFiles = Copy-CompiledAppsToOutput -PackageCachePath $PackageCachePath -OutputFolder $OutFolder -FilesBeforeCompile $filesBeforeCompile

    OutputArray -Message "Generated app files:" -Array $generatedAppFiles -Debug
    return $generatedAppFiles
}

<#
.SYNOPSIS
    Gets the highest compatible .NET runtime version installed on the system.
.DESCRIPTION
    Uses 'dotnet --list-runtimes' to detect installed .NET runtimes. Returns the highest
    version that is within the supported major version range. Requires both Microsoft.NETCore.App
    and Microsoft.AspNetCore.App runtimes to be installed for a version to be considered.
.PARAMETER MinimumSupportedMajorVersion
    The minimum major version of .NET runtime to consider.
.PARAMETER MaximumSupportedMajorVersion
    The maximum major version of .NET runtime to consider.
.OUTPUTS
    System.Version of the highest compatible .NET runtime installed, or $null if none found.
#>
function Get-DotnetRuntimeVersionInstalled {
    param(
        [Parameter(Mandatory = $false)]
        [int] $MinimumSupportedMajorVersion = 6, # TODO: Find a better way to determine minimum supported version and maximum supported version
        [Parameter(Mandatory = $false)]
        [int] $MaximumSupportedMajorVersion = 8
    )

    try {
        $runtimeOutput = dotnet --list-runtimes

        if (-not $runtimeOutput) {
            OutputDebug -message "Could not detect .NET runtimes. 'dotnet --list-runtimes' returned no output."
            return $null
        }

        # Parse runtimes into a hashtable grouped by runtime name
        $runtimes = @{}
        $parsedRuntimes = $runtimeOutput | ConvertFrom-Csv -Delimiter ' ' -Header 'name', 'version'
        foreach ($runtime in $parsedRuntimes) {
            try {
                $version = [System.Version]$runtime.version
                if (-not $runtimes.ContainsKey($runtime.name)) {
                    $runtimes[$runtime.name] = @()
                }
                $runtimes[$runtime.name] += $version
            } catch {
                OutputDebug -message "Skipping runtime version '$($runtime.version)' that could not be parsed: $_"
            }
        }

        # Find versions where both NETCore.App and AspNetCore.App are installed
        $netCoreVersions = $runtimes['Microsoft.NETCore.App']
        $aspNetVersions = $runtimes['Microsoft.AspNetCore.App']

        if (-not $netCoreVersions -or -not $aspNetVersions) {
            OutputDebug -message "Required .NET runtimes not found. Need both Microsoft.NETCore.App and Microsoft.AspNetCore.App."
            return $null
        }

        # Find the highest version present in both, within the supported major version range
        $compatibleVersions = $netCoreVersions | Where-Object {
            $_.Major -ge $MinimumSupportedMajorVersion -and
            $_.Major -le $MaximumSupportedMajorVersion -and
            $aspNetVersions -contains $_
        } | Sort-Object -Descending

        if ($compatibleVersions) {
            return $compatibleVersions | Select-Object -First 1
        }

        return $null
    }
    catch {
        OutputDebug -message "Failed to detect .NET runtime version: $_"
        return $null
    }
}

<#

.SYNOPSIS
    Gets the assembly probing paths for the AL compiler.
.DESCRIPTION
    Constructs a list of assembly probing paths based on the compiler folder and the installed .NET runtimes.
    Includes paths for service assemblies, mock assemblies, OpenXML, and shared runtime folders.
.PARAMETER CompilerFolder
    The folder where the AL compiler tool is located.
.OUTPUTS
    Array of assembly probing paths.
#>
function Get-AssemblyProbingPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompilerFolder
    )
    OutputDebug "Determining assembly probing paths..."
    $probingPaths = @()

    $compilerFolderDllsPath = Join-Path $CompilerFolder "dlls"

    # If dlls/ folder does not exist, assembly probing is not configured
    if (-not (Test-Path $compilerFolderDllsPath)) {
        OutputDebug "No dlls folder found in compiler folder. Assembly probing paths will be empty."
        return $probingPaths
    }

    $compilerFolderSharedPath = Join-Path $compilerFolderDllsPath "shared"

    # Use Service and Mock Assemblies folders if they exist from the compiler folder
    $probingPaths += @((Join-Path $compilerFolderDllsPath "Service"),(Join-Path $compilerFolderDllsPath "Mock Assemblies"))

    # Use OpenXML and shared folder if they exist
    if (Test-Path $compilerFolderSharedPath) {
        $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), $compilerFolderSharedPath) + $probingPaths
    } elseif ($isLinux -or $isMacOS) {
        $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML")) + $probingPaths
    } else {
        $dotNetRuntimeVersion = (Get-DotnetRuntimeVersionInstalled)
        if ($dotNetRuntimeVersion) {
            $dotnetRoot = Split-Path (Get-Command dotnet).Source
            $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), (Join-Path $dotnetRoot "shared\Microsoft.NETCore.App\$dotNetRuntimeVersion"), (Join-Path $dotnetRoot "shared\Microsoft.AspNetCore.App\$dotNetRuntimeVersion")) + $probingPaths
        }
        else {
            $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML")) + $probingPaths
        }
    }

    OutputArray -Message "Probing Paths:" -Array $probingPaths

    return $probingPaths
}

<#
.SYNOPSIS
    Creates a workspace file from the specified folders.
.DESCRIPTION
    Uses the AL compiler tool to create a workspace file that includes all the specified folders.
.PARAMETER Folders
    An array of folder paths to include in the workspace.
.PARAMETER WorkspaceFile
    The path where the workspace file will be created.
.PARAMETER AltoolPath
    The full path to the AL compiler tool (al.exe or al).
#>
function New-WorkspaceFromFolders {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile,

        [Parameter(Mandatory = $true)]
        [string]$AltoolPath
    )
    $arguments = @("workspace", "create", $WorkspaceFile) + $Folders
    OutputColor "Executing: $AltoolPath $($arguments -join ' ')" -Color Green
    RunAndCheck $AltoolPath @arguments | Out-Null

    OutputDebug "Workspace created at $WorkspaceFile"
}

<#
.SYNOPSIS
    Updates the version property in app.json files within the specified folders.
.DESCRIPTION
    Finds all app.json files in the given folders and updates their version property based on the provided major/minor version, build number, and revision number. If only the revision number is provided, it will update just the revision part of the existing version.
.PARAMETER Folders
    An array of folder paths to search for app.json files.
.PARAMETER MajorMinorVersion
    The major and minor version to set in the app.json files (e.g., "1.2"). If not provided, the existing major and minor version will be retained.
.PARAMETER BuildNumber
    The build number to set in the app.json files. If not provided, the existing build number will be retained.
.PARAMETER RevisionNumber
    The revision number to set in the app.json files. If not provided, the existing revision number will be retained.
#>
function Update-AppJsonProperties {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,

        [Parameter(Mandatory = $false)]
        [string]$MajorMinorVersion = "",

        [Parameter(Mandatory = $false)]
        [int] $BuildNumber = 0,

        [Parameter(Mandatory = $false)]
        [int] $RevisionNumber = 0,

        [Parameter(Mandatory = $false)]
        [string]$BuildBy = "",

        [Parameter(Mandatory = $false)]
        [string]$BuildUrl = ""
    )

    foreach ($folder in $Folders) {
        $appJsonFiles = Get-ChildItem -Path $folder -Filter "app.json"
        foreach ($appJsonFile in $appJsonFiles) {
            $appJsonContent = Get-Content -Path $appJsonFile.FullName -Raw | ConvertFrom-Json

            if ($MajorMinorVersion) {
                # If MajorMinorVersion is provided, use it along with BuildNumber and RevisionNumber (or 0 if not provided) to construct the new version
                $version = [System.Version]"$($MajorMinorVersion).$($BuildNumber).$($RevisionNumber)"
            } else {
                # If MajorMinorVersion is not provided, retain the existing major and minor version from app.json and update build and revision numbers based on provided parameters (or retain existing if not provided)
                $currentAppJsonVersion = [System.Version]$appJsonContent.Version
                if ($BuildNumber -eq 0) {
       	            $version = [System.Version]::new($currentAppJsonVersion.Major, $currentAppJsonVersion.Minor, $currentAppJsonVersion.Build, $RevisionNumber)
                } else {
                    $version = [System.Version]::new($currentAppJsonVersion.Major, $currentAppJsonVersion.Minor, $BuildNumber, $RevisionNumber)
                }
            }

            OutputDebug "Updating app.json at $($appJsonFile.FullName) to version $version"
            $appJsonContent.version = "$version"

            # Stamp build metadata into app.json
            if ($BuildBy -or $BuildUrl) {
                $buildObject = @{}
                if ($BuildBy) { $buildObject.by = $BuildBy }
                if ($BuildUrl) { $buildObject.url = $BuildUrl }
                if ($appJsonContent.PSObject.Properties.Name -contains 'build') {
                    $appJsonContent.build = $buildObject
                } else {
                    $appJsonContent | Add-Member -MemberType NoteProperty -Name 'build' -Value $buildObject
                }
            }

            # Save the updated app.json file
            $appJsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $appJsonFile.FullName -Encoding UTF8
            OutputDebug "Updated app.json at $($appJsonFile.FullName)"
        }
    }
}

<#
.SYNOPSIS
    Converts AL compiler output lines to GitHub Actions workflow annotations.
.DESCRIPTION
    Parses AL compiler output and converts error/warning lines into GitHub Actions
    annotation format (::error, ::warning) with file, line, and column information.
    Optionally fails the build based on diagnostic severity.
.PARAMETER AlcOutput
    Array of output lines from the AL compiler.
.PARAMETER BasePath
    Base path to strip from file paths to create relative paths in annotations.
.PARAMETER FailOn
    Criteria for failing the build: 'none', 'error', 'warning', or 'newWarning'.
#>
function Write-CompilerDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]] $AlcOutput,

        [Parameter(Mandatory = $false)]
        [string] $BasePath = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('none','error','warning','newWarning')]
        [string] $FailOn = 'none'
    )

    if (-not $AlcOutput) { return }

    if ($BasePath) {
        $BasePath = "$($BasePath.TrimEnd('\'))\"
    }
    $hasError = $false
    $hasWarning = $false

    foreach ($line in $AlcOutput) {
        $newLine = $line
        switch -regex ($line) {
            # file(line,col): error CODE: message
            "^(.*)\((\d+),(\d+)\): error (\w{2,3}\d{4}): (.*)$" {
                $file = $Matches[1]
                if ($file -like "$($BasePath)*") { $file = ".\$($file.SubString($BasePath.Length))".Replace('\','/') }
                $newLine = "::error file=$($file),line=$($Matches[2]),col=$($Matches[3])::$($Matches[4]) $($Matches[5])"
                $hasError = $true
                break
            }
            # error CODE: message (no file)
            "^(.*)error (\w{2,3}\d{4}): (.*)$" {
                $newLine = "::error::$($Matches[2]) $($Matches[3])"
                $hasError = $true
                break
            }
            # file(line,col): warning CODE: message
            "^(.*)\((\d+),(\d+)\): warning (\w{2,3}\d{4}): (.*)$" {
                $file = $Matches[1]
                if ($file -like "$($BasePath)*") { $file = ".\$($file.SubString($BasePath.Length))".Replace('\','/') }
                $newLine = "::warning file=$($file),line=$($Matches[2]),col=$($Matches[3])::$($Matches[4]) $($Matches[5])"
                $hasWarning = $true
                break
            }
            # warning CODE: message (no file)
            "^warning (\w{2,3}\d{4}):(.*)$" {
                $newLine = "::warning::$($Matches[1]) $($Matches[2])"
                $hasWarning = $true
                break
            }
        }
        Write-Host $newLine
    }

    if ($FailOn -eq 'warning' -and $hasWarning) {
        Write-Host "::Error::Failing build as warnings were reported"
        $host.SetShouldExit(1)
    }
    elseif ($FailOn -eq 'error' -and $hasError) {
        Write-Host "::Error::Failing build as errors were reported"
        $host.SetShouldExit(1)
    }
}

<#
.SYNOPSIS
    Creates a consolidated build output file from individual log files.
.DESCRIPTION
    Collects all .log files from the specified build artifact folder, sanitizes their content,
    and appends them to a single build output file. Optionally displays the output in the console
    and can fail the build based on specified criteria.
.PARAMETER BuildArtifactFolder
    The folder containing individual build log files.
.PARAMETER BuildOutputPath
    The path where the consolidated build output file will be created.
.PARAMETER DisplayInConsole
    Switch to indicate whether the build output should be displayed in the console.
.PARAMETER FailOn
    Specifies the criteria for failing the build based on output severity. Options are 'none', 'error', 'warning', 'newWarning'.
.PARAMETER BasePath
    The base path for relative paths in the output. Defaults to the GitHub workspace path.
#>
function New-BuildOutputFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildArtifactFolder,
        [Parameter(Mandatory = $true)]
        [string]$BuildOutputPath,
        [Parameter(Mandatory = $false)]
        [switch]$DisplayInConsole,
        [Parameter(Mandatory = $false)]
        [ValidateSet('none','error','warning','newWarning')]
        [string]$FailOn,
        [Parameter(Mandatory = $false)]
        [string]$BasePath = (Get-BasePath)
    )
    # Create the file path for the build output
    New-Item -Path $BuildOutputPath -ItemType File -Force | Out-Null

    # Collect the log files and append their content to the build output file
    $logFiles = Get-ChildItem -Path $BuildArtifactFolder -Recurse -Filter "*.log" | Select-Object -ExpandProperty FullName
    OutputGroupStart -Message "Build Logs"
    try {
        foreach ($logFile in $logFiles) {
            $sanitizedLines = Get-Content -Path $logFile | ForEach-Object { $_ -replace '^\[OUT\]\s?', '' }
            Add-Content -Path $buildOutputPath -Value $sanitizedLines

            # Print build output to console as GitHub Actions annotations
            if ($DisplayInConsole) {
                Write-CompilerDiagnostics -AlcOutput $sanitizedLines -BasePath $BasePath -FailOn $FailOn
            }
        }
    } finally {
        OutputGroupEnd
    }

    return $buildOutputPath
}

Export-ModuleMember -Function Build-AppsInWorkspace
Export-ModuleMember -Function New-BuildOutputFile
Export-ModuleMember -Function Get-BuildMetadata
Export-ModuleMember -Function Get-CodeAnalyzers
Export-ModuleMember -Function Get-CustomAnalyzers
Export-ModuleMember -Function Get-AssemblyProbingPaths
Export-ModuleMember -Function Update-AppJsonProperties
Export-ModuleMember -Function Get-CompilerVersionConstraint
Export-ModuleMember -Function Install-ALCompiler
Export-ModuleMember -Function Invoke-WorkspaceRestore
Export-ModuleMember -Function Install-AssemblyProbingDLLs
Export-ModuleMember -Function Resolve-DependencySymbols
Export-ModuleMember -Function Get-ALTool
Export-ModuleMember -Function New-WorkspaceFromFolders
