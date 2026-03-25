Import-Module (Join-Path -Path $PSScriptRoot "./DebugLogHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../TelemetryHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../Github-Helper.psm1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

$script:alTool = $null

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

    # Analyzers/ directory exists in the compiler folder by default
    $binPath = Join-Path $CompilerFolder 'compiler/extension/bin'
    foreach ($customCodeCop in $Settings.CustomCodeCops) {
        if ($customCodeCop -like 'https://*') {
            $analyzerFileName = Join-Path $binPath "Analyzers/$(Split-Path $customCodeCop -Leaf)"
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
    Returns the full path to the AL compiler tool located in the specified compiler folder.
    .PARAMETER CompilerFolder
    The folder where the AL compiler tool is located.
    .OUTPUTS
    The full path to the AL compiler tool.
#>
function Get-ALTool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CompilerFolder
    )

    if ($script:alTool -and (Test-Path $script:alTool)) {
        return $script:alTool
    }

    # Select the platform-specific AL tool binary
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
.PARAMETER MajorMinorVersion
    Major.Minor version to stamp into the compiled apps.
.PARAMETER BuildNumber
    Build number to stamp into the compiled apps.
.PARAMETER RevisionNumber
    Revision number to stamp into the compiled apps.
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
        [string]$PackageCachePath,
        [Parameter(Mandatory = $false)]
        [string]$OutFolder,
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory,
        # Optional parameters
        [Parameter(Mandatory = $false)]
        [string]$MajorMinorVersion = "",
        [Parameter(Mandatory = $false)]
        [int] $BuildNumber = 0,
        [Parameter(Mandatory = $false)]
        [int] $RevisionNumber = 0,
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

    # Create workspace file in temp directory
    $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
    $workspaceFile = Join-Path (Get-Location) "tempWorkspace$datetimeStamp.code-workspace"
    New-WorkspaceFromFolders -Folders $Folders -WorkspaceFile $workspaceFile -AltoolPath $alToolPath

    $compilationParameters = @{
        ALToolPath = $alToolPath
        WorkspaceFile = $workspaceFile
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

    # Remove the workspace file again
    Remove-Item $workspaceFile -Force -ErrorAction SilentlyContinue

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
                # Skip versions that can't be parsed
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
    $compilerFolderSharedPath = Join-Path $compilerFolderDllsPath "shared"

    # Use Service and Mock Assemblies folders if they exist from the compiler folder
    if (Test-Path $compilerFolderDllsPath) {
        $probingPaths += @((Join-Path $compilerFolderDllsPath "Service"),(Join-Path $compilerFolderDllsPath "Mock Assemblies"))
    }

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

            # Print build output to console (aggregated), preserving line formatting
            if ($DisplayInConsole) {
                Convert-AlcOutputToAzureDevOps -basePath $BasePath -AlcOutput $sanitizedLines -gitHubActions -FailOn $FailOn
            }
        }
    } finally {
        OutputGroupEnd
    }

    return $buildOutputPath
}

<#
.SYNOPSIS
    Generates AppSourceCop.json files for app folders with baseline version information.
.DESCRIPTION
    For each app folder, creates an AppSourceCop.json file containing the previous version
    of the app as a baseline for breaking change detection. Also includes mandatory affixes,
    supported countries, and obsolete tag settings from the project settings.
.PARAMETER AppFolders
    Array of app folder paths to generate AppSourceCop.json for.
.PARAMETER PreviousApps
    Array of file paths to previous release .app files.
.PARAMETER CompilerFolder
    Path to the compiler folder containing the AL tool.
.PARAMETER Settings
    Hashtable containing the build settings with AppSourceCop configuration.
#>
function New-AppSourceCopJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $AppFolders,
        [Parameter(Mandatory = $true)]
        [string[]] $PreviousApps,
        [Parameter(Mandatory = $true)]
        [string] $CompilerFolder,
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings
    )

    # Extract version info from previous apps using the AL tool
    $previousAppVersions = @{}
    foreach ($appFile in $PreviousApps) {
        try {
            $alToolPath = Get-ALTool -CompilerFolder $CompilerFolder
            $appInfo = RunAndCheck $alToolPath GetPackageManifest $appFile | ConvertFrom-Json
            $key = "$($appInfo.Publisher)_$($appInfo.Name)"
            $previousAppVersions[$key] = $appInfo.Version.ToString()
        }
        catch {
            OutputWarning -message "Failed to read manifest from '$appFile': $($_.Exception.Message)"
        }
    }

    foreach ($folder in $AppFolders) {
        $appSourceCopJson = @{}
        $saveIt = $false

        if ($Settings.appSourceCopMandatoryAffixes -and $Settings.appSourceCopMandatoryAffixes.Count -gt 0) {
            $appSourceCopJson["mandatoryAffixes"] = @() + $Settings.appSourceCopMandatoryAffixes
            $saveIt = $true
        }

        if ($Settings.obsoleteTagMinAllowedMajorMinor) {
            $appSourceCopJson["obsoleteTagMinAllowedMajorMinor"] = $Settings.obsoleteTagMinAllowedMajorMinor
            $saveIt = $true
        }

        # Match previous app version by Publisher_Name
        $appJsonPath = Join-Path $folder "app.json"
        if (Test-Path $appJsonPath) {
            $appJson = Get-Content -Path $appJsonPath -Raw | ConvertFrom-Json
            $key = "$($appJson.Publisher)_$($appJson.Name)"
            if ($previousAppVersions.ContainsKey($key)) {
                $appSourceCopJson["Publisher"] = $appJson.Publisher
                $appSourceCopJson["Name"] = $appJson.Name
                $appSourceCopJson["Version"] = $previousAppVersions[$key]
                $saveIt = $true
            }
        }

        $appSourceCopJsonFile = Join-Path $folder "AppSourceCop.json"
        if ($saveIt) {
            Write-Host "Creating AppSourceCop.json for $folder"
            $appSourceCopJson | ConvertTo-Json -Depth 99 | Set-Content $appSourceCopJsonFile
        }
        else {
            if (Test-Path $appSourceCopJsonFile) {
                Remove-Item $appSourceCopJsonFile -Force
            }
        }
    }
}

Export-ModuleMember -Function Build-AppsInWorkspace
Export-ModuleMember -Function New-BuildOutputFile
Export-ModuleMember -Function Get-BuildMetadata
Export-ModuleMember -Function Get-CodeAnalyzers
Export-ModuleMember -Function Get-CustomAnalyzers
Export-ModuleMember -Function Get-AssemblyProbingPaths
Export-ModuleMember -Function Update-AppJsonProperties
Export-ModuleMember -Function Get-AppIdForAppFile
Export-ModuleMember -Function New-AppSourceCopJson
