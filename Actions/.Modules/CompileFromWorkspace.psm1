$script:alTool = $null
Import-Module (Join-Path -Path $PSScriptRoot "./DebugLogHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../TelemetryHelper.psm1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "../Github-Helper.psm1" -Resolve)

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

    if ($Settings.CustomCodeCops -and $Settings.CustomCodeCops.Count -gt 0) {
        OutputWarning -message "Custom code cops are not yet supported. The following custom code cops will be ignored: $($CustomCodeCops -join ', ')"
    }

    return $analyzers
}

<#
.SYNOPSIS
    Gets build metadata for the current build environment.
.DESCRIPTION
    Returns a hashtable with build metadata including source repository URL, commit SHA,
    build system identifier, and build URL. When running locally (outside of GitHub Actions),
    provides sensible defaults.
.OUTPUTS
    Hashtable with SourceRepositoryUrl, SourceCommit, BuildBy, and BuildUrl properties.
#>
function Get-BuildMetadata {
    $isLocalBuild = -not $env:GITHUB_ACTIONS

    if ($isLocalBuild) {
        # Running locally - use git to get repository info if available
        $sourceRepositoryUrl = "local"
        $sourceCommit = "unknown"
        
        try {
            $sourceRepositoryUrl = git config --get remote.origin.url
            $sourceCommit = git rev-parse HEAD
        } catch {
            OutputWarning -message "Git repository information could not be retrieved. Using default local values."
        }

        return @{
            SourceRepositoryUrl = $sourceRepositoryUrl
            SourceCommit        = $sourceCommit
            BuildBy             = "AL-Go for GitHub (local)"
            BuildUrl            = "N/A"
        }
    } else {
        # Running in GitHub Actions
        return @{
            SourceRepositoryUrl = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY"
            SourceCommit        = $env:GITHUB_SHA
            BuildBy             = "AL-Go for GitHub"
            BuildUrl            = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
        }
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
        $CompilerFolder
    )

    if ($script:alTool -and (Test-Path $script:alTool)) {
        return $script:alTool
    }

    # Load the AL tool from the downloaded package
    $alExe = Get-ChildItem -Path $CompilerFolder -Recurse -Filter "al*" | Where-Object { $_.Name -eq "al" -or $_.Name -eq "altool.exe" } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $alExe) {
        throw "Could not find al.exe in the development tools package."
    }
    $script:alTool = $alExe
    return $script:alTool
}

<#
Before this script
1. Create a compiler folder
2. Fetch external dependencies into the compiler folder symbols folder
3. Download baseline packages and set up AppSourceCop baseline packages
#>
function Build-AppsInWorkspace() {
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
        [string]$BuildBy,
        [Parameter(Mandatory = $false)]
        [string]$BuildUrl,
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

    # Get the package cache path
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
    if ($MaxCpuCount -gt [System.Environment]::ProcessorCount) {
        Write-Host "Specified MaxCpuCount $MaxCpuCount is greater than available processors $([System.Environment]::ProcessorCount). Using $([System.Environment]::ProcessorCount) instead."
        $MaxProcesses = [System.Environment]::ProcessorCount
    } elseif ($MaxCpuCount -lt 0) {
        $MaxProcesses = [System.Environment]::ProcessorCount
    } else {
        $MaxProcesses = $MaxCpuCount
    }

    # Get AL tool path
    $alToolPath = Get-ALTool -CompilerFolder $CompilerFolder

    # Create workspace file from AL-Go folders
    $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
    $workspaceFile = Join-Path $PSScriptRoot "tempWorkspace$datetimeStamp.code-workspace"
    New-WorkspaceFromFolders -Folders $Folders -WorkspaceFile $workspaceFile -AltoolPath $alToolPath

    $compilationParameters = @{
        ALToolPath = $alToolPath
        WorkspaceFile = $workspaceFile
        PackageCachePath = $PackageCachePath
        OutFolder = $OutputFolder
        AssemblyProbingPaths = $AssemblyProbingPaths
        Analyzers = $Analyzers
        PreprocessorSymbols = $PreprocessorSymbols
        Features = $Features
        GenerateReportLayout = $GenerateReportLayout
        Ruleset = $Ruleset
        SourceRepositoryUrl = $SourceRepositoryUrl
        SourceCommit = $SourceCommit
        BuildBy = $BuildBy
        BuildUrl = $BuildUrl
        ReportSuppressedDiagnostics = $ReportSuppressedDiagnostics
        EnableExternalRulesets = $EnableExternalRulesets
        MaxCpuCount = $MaxProcesses
    }

    # Pre-Compile Apps - Invoke script override before compilation
    if ($PreCompileApp) {
        Write-Host "Invoking Pre-Compile App Script..."
        Invoke-Command -ScriptBlock $PreCompileApp -ArgumentList $AppType, ([ref] $compilationParameters)
    }

    # Compile apps
    $appFiles = CompileAppsInWorkspace @compilationParameters

    # Post-Compile Apps - Invoke sccript override after compilation
    if ($PostCompileApp) {
        Write-Host "Invoking Post-Compile App Script..."
        Invoke-Command -ScriptBlock $PostCompileApp -ArgumentList $appFiles, $AppType, $compilationParameters
    }

    # Clean up 
    Remove-Item $workspaceFile -Force -ErrorAction SilentlyContinue

    return $appFiles
}

function CompileAppsInWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ALToolPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxCpuCount = 1,
        
        [Parameter(Mandatory = $false)]
        [string]$PackageCachePath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$AssemblyProbingPaths,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Analyzers,

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
        [string]$BuildBy,

        [Parameter(Mandatory = $false)]
        [string]$BuildUrl,

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

    Write-Host "Assembly probing paths: $AssemblyProbingPaths"

    # Check if the workspace file exists
    if (-not (Test-Path $WorkspaceFile)) {
        throw "The specified workspace file '$WorkspaceFile' does not exist."
    }

    # Build the command arguments dynamically
    $arguments = @("workspace", "compile", $WorkspaceFile)

    # Get list of files in the package cache path with their timestamps
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

    if ($BuildBy) {
        $env:BUILD_BY = $BuildBy
    }

    if ($BuildUrl) {
        $env:BUILD_URL = $BuildUrl
    }

    if ($ReportSuppressedDiagnostics.IsPresent) {
        OutputWarning "--reportsuppresseddiagnostics is not yet supported and will be ignored."
    }

    if ($EnableExternalRulesets.IsPresent) {
        OutputWarning "--enableexternalrulesets is not yet supported and will be ignored."
    }

    if ($LogLevel -and $LogLevel -ne 'Normal') {
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
        Write-Host "Executing: $ALToolPath $($arguments -join ' ')" -ForegroundColor Green
        
        # Temporarily set console encoding to UTF-8 to handle special characters in output
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        & $ALToolPath @arguments | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "Compilation failed with exit code $LASTEXITCODE"
        }
        OutputDebug -message "Compilation completed successfully."
    } catch {
        OutputColor -Message "Error during compilation: $_" -Color Red
        throw $_
    } finally {
        # Restore original encoding
        [Console]::OutputEncoding = $originalEncoding
        $outputFiles = @()

        # if package cache path and output folder are the same then no need to copy files
        # Copy the output files from the package cache to the output folder 
        OutputDebug -message "Copying generated app files to output folder..."
        if ((Test-Path $PackageCachePath) -and ($PackageCachePath -ne $OutputFolder)) {
            if (-not (Test-Path $OutputFolder)) {
                New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            }
            $filesInPackageCache = Get-ChildItem -Path $PackageCachePath -File -Filter "*.app"
            OutputArray -Message "Files in package cache after compilation:" -Array $filesInPackageCache -Debug
            # Find new or modified files by comparing timestamps
            $outputFiles = Get-ChildItem -Path $PackageCachePath -File -Filter "*.app" | Where-Object { 
                -not $filesBeforeCompile.ContainsKey($_.FullName) -or 
                $_.LastWriteTimeUtc -gt $filesBeforeCompile[$_.FullName]
            }
        }

        OutputDebug -message "Copying generated app files from package cache '$PackageCachePath' to output folder '$OutputFolder'"
        foreach ($file in $outputFiles) {
            $destinationPath = Join-Path $OutputFolder $file.Name
            $generatedAppFiles += $destinationPath
            if ($OutputFolder -eq $PackageCachePath) {
                continue
            }
            Copy-Item -Path $file.FullName -Destination $destinationPath -Force
        }
    }

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
# TODO: Find a better way to determine minimum supported version and maximum supported version
function Get-DotnetRuntimeVersionInstalled {
    param(
        [Parameter(Mandatory = $false)]
        [int] $MinimumSupportedMajorVersion = 6,
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
        foreach ($line in $runtimeOutput) {
            # Format: "Microsoft.NETCore.App 8.0.1 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]"
            if ($line -match '^(Microsoft\.\w+\.App)\s+(\d+\.\d+\.\d+)') {
                $runtimeName = $matches[1]
                $versionStr = $matches[2]
                
                try {
                    $version = [System.Version]$versionStr
                    if (-not $runtimes.ContainsKey($runtimeName)) {
                        $runtimes[$runtimeName] = @()
                    }
                    $runtimes[$runtimeName] += $version
                } catch {
                    # Skip versions that can't be parsed
                }
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
.PARAMETER MinimumDotNetVersion
    The minimum major version of .NET runtime to consider. Default is 6.
.PARAMETER MaximumDotNetVersion
    The maximum major version of .NET runtime to consider. Default is 8.
.OUTPUTS
    Array of assembly probing paths.
#>
function Get-AssemblyProbingPaths() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompilerFolder,
        [Parameter(Mandatory = $false)]
        [int]$MinimumDotNetVersion = 6,
        [Parameter(Mandatory = $false)]
        [int]$MaximumDotNetVersion = 8
    )
    Write-Host "Determining assembly probing paths..."
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
        $dotNetRuntimeVersion = (Get-DotnetRuntimeVersionInstalled -MinimumSupportedMajorVersion $MinimumDotNetVersion -MaximumSupportedMajorVersion $MaximumDotNetVersion)
        if ($dotNetRuntimeVersion) {
            $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), "C:\Program Files\dotnet\shared\Microsoft.NETCore.App\$dotNetRuntimeVersion", "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$dotNetRuntimeVersion") + $probingPaths
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
function New-WorkspaceFromFolders() {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,
        
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile,

        [Parameter(Mandatory = $true)]
        [string]$AltoolPath
    )
    $arguments = @("workspace", "create", $WorkspaceFile) + $Folders
    try {
        Write-Host "Executing: $AltoolPath $($arguments -join ' ')" -ForegroundColor Green
        & $AltoolPath @arguments | Out-Null
    } catch {
        throw $_
    }

    Write-Host "Workspace created at $WorkspaceFile"
}

function Update-AppJsonProperties() {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,

        [Parameter(Mandatory = $false)]
        [string]$MajorMinorVersion = "",

        [Parameter(Mandatory = $false)]
        [int] $BuildNumber = 0,

        [Parameter(Mandatory = $false)]
        [int] $RevisionNumber = 0
    )

    # TODO for future PR: Update implementation here to support Directory.App.Props.json

    foreach ($folder in $Folders) {
        $appJsonFiles = Get-ChildItem -Path $folder -Filter "app.json"
        foreach ($appJsonFile in $appJsonFiles) {
            $appJsonContent = Get-Content -Path $appJsonFile.FullName -Raw | ConvertFrom-Json

            if ($MajorMinorVersion) {
                $version = [System.Version]"$($MajorMinorVersion).$($BuildNumber).$($RevisionNumber)"
            } else {
                $currentAppJsonVersion = [System.Version]$appJsonContent.Version
                if ($BuildNumber -eq 0) {
       	            $version = [System.Version]::new($currentAppJsonVersion.Major, $currentAppJsonVersion.Minor, $currentAppJsonVersion.Build, $RevisionNumber)
                } else {
                    $version = [System.Version]::new($currentAppJsonVersion.Major, $currentAppJsonVersion.Minor, $BuildNumber, $RevisionNumber)
                }
            }

            OutputDebug "Updating app.json at $($appJsonFile.FullName) to version $version"
            $appJsonContent.version = "$version"

            # Add other properties to update as needed

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
    foreach ($logFile in $logFiles) {
        $sanitizedLines = Get-Content -Path $logFile | ForEach-Object { $_ -replace '^\[OUT\]\s?', '' }
        Add-Content -Path $buildOutputPath -Value $sanitizedLines

        # Print build output to console (aggregated), preserving line formatting
        if ($DisplayInConsole) {
            Convert-AlcOutputToAzureDevOps -basePath $BasePath -AlcOutput $sanitizedLines -gitHubActions -FailOn $FailOn
        }
    }

    return $buildOutputPath
}

<#
.SYNOPSIS
    Gets script overrides for pre-compile and post-compile actions.
.DESCRIPTION
    Checks for the existence of PreCompileApp.ps1 and PostCompileApp.ps1 scripts in the specified
    AL-Go folder and returns their script blocks if found.
.PARAMETER ALGoFolderName
    The folder where the AL-Go scripts are located.
.OUTPUTS
    Hashtable with PreCompileApp and PostCompileApp script blocks.
#>
function Get-ScriptOverrides() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ALGoFolderName
    )
    $precompileOverride = $null
    $postCompileOverride = $null
    foreach ($override in @("PreCompileApp", "PostCompileApp")) {
        $scriptPath = Join-Path $ALGoFolderName "$override.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $override ($scriptPath)"
            Trace-Information -Message "Using override for $override"
            if ($override -eq "PreCompileApp") {
                $precompileOverride = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
            else {
                $postCompileOverride = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }

    return @{
        PreCompileApp = $precompileOverride
        PostCompileApp = $postCompileOverride
    }
}

Export-ModuleMember -Function Build-AppsInWorkspace
Export-ModuleMember -Function New-BuildOutputFile
Export-ModuleMember -Function Get-BasePath
Export-ModuleMember -Function Get-BuildMetadata
Export-ModuleMember -Function Get-CodeAnalyzers
Export-ModuleMember -Function Get-AssemblyProbingPaths
Export-ModuleMember -Function Get-ScriptOverrides
Export-ModuleMember -Function Update-AppJsonProperties