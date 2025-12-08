$script:alTool = "C:\Users\aholstrup\Documents\Platform-ModernDev\out\Release\altool\net8.0\altool.exe"

<#
Before this script: 
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
        [string]$OutFolder,
        # Optional parameters
        [System.Version]$BuildVersion,
        # Optional compiler parameters
        [Parameter(Mandatory = $false)]
        [string[]]$Analyzers,
        [Parameter(Mandatory = $false)]
        [string[]]$Features,
        [Parameter(Mandatory = $false)]
        [switch]$GenerateReportLayout,
        [Parameter(Mandatory = $false)]
        [string[]]$Define,
        [Parameter(Mandatory = $false)]
        [string]$Ruleset,
        [Parameter(Mandatory = $false)]
        [string]$SourceRepositoryUrl,
        [Parameter(Mandatory = $false)]
        [string]$SourceCommit,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PreCompileApp,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PostCompileApp
    )

    # Get asembly probing paths
    $assemblyProbingPaths = Get-AssemblyProbingPaths -CompilerFolder $CompilerFolder

    # Get the package cache path
    $PackageCachePath = Join-Path $CompilerFolder "symbols"

    # Update the app jsons with version number (and other properties) from the app manifest files
    Update-AppJsonProperties -Folders $Folders -BuildVersion $BuildVersion -OutputFolder $PackageCachePath

    # Create workspace file from AL-Go folders
    $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
    $workspaceFile = Join-Path $PSScriptRoot "tempWorkspace$datetimeStamp.code-workspace"
    New-WorkspaceFromFolders -Folders $Folders -WorkspaceFile $workspaceFile

    $compilationParameters = @{
        WorkspaceFile = $workspaceFile
        PackageCachePath = $PackageCachePath
        OutFolder = $OutFolder
        AssemblyProbingPaths = $assemblyProbingPaths
        Analyzers = $Analyzers
        Features = $Features
        GenerateReportLayout = $GenerateReportLayout
        Define = $Define
        Ruleset = $Ruleset
        SourceRepositoryUrl = $SourceRepositoryUrl
        SourceCommit = $SourceCommit
    }

    # Pre-Compile Apps - Invoke script override before compilation
    if ($PreCompileApp) {
        Write-Host "Invoking Pre-Compile App Script..."
        Invoke-Command -ScriptBlock $PreCompileApp -ArgumentList ([ref] $compilationParameters)
    }

    # Compile apps
    $appFiles = CompileAppsInWorkspace @compilationParameters

    # Post-Compile Apps - Invoke sccript override after compilation
    if ($PostCompileApp) {
        Write-Host "Invoking Post-Compile App Script..."
        Invoke-Command -ScriptBlock $PostCompileApp -ArgumentList $appFiles, $compilationParams
    }

    # Clean up 
    Remove-Item $workspaceFile -Force -ErrorAction SilentlyContinue

    return $appFiles
}

function CompileAppsInWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxCpuCount = [System.Environment]::ProcessorCount,
        
        [Parameter(Mandatory = $false)]
        [string]$PackageCachePath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$AssemblyProbingPaths,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Analyzers,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Features,    
        
        [Parameter(Mandatory = $false)]
        [switch]$GenerateReportLayout,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Define,
        
        [Parameter(Mandatory = $false)]
        [string]$Ruleset,
        
        [Parameter(Mandatory = $false)]
        [string]$SourceRepositoryUrl,
        
        [Parameter(Mandatory = $false)]
        [string]$SourceCommit,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Error', 'Normal', 'Verbose', 'Warning')]
        [string]$LogLevel = 'Normal',
        
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory = $false)]
        [string]$OutFolder
    )

    # Build the command arguments dynamically
    $arguments = @("workspace", "compile", $WorkspaceFile)

    # Get list of files in the package cache path
    $filesInPackageCache = @()
    if ($PackageCachePath -and (Test-Path $PackageCachePath)) {
        $filesInPackageCache = Get-ChildItem -Path $PackageCachePath -File | Select-Object -ExpandProperty FullName
    }

    # Determine the final output folder
    if (-not $OutFolder) {
        $OutputFolder = $PackageCachePath
    } else {
        $OutputFolder = $OutFolder
    }

    # Check if the workspace file exists
    if (-not (Test-Path $WorkspaceFile)) {
        throw "The specified workspace file '$WorkspaceFile' does not exist."
    }

    # Add optional parameters only if they are provided
    if ($MaxCpuCount -and $MaxCpuCount -ne [System.Environment]::ProcessorCount) {
        $arguments += "--maxcpucount"
        $arguments += $MaxCpuCount.ToString()
    }

    if ($PackageCachePath) {
        $arguments += "--packagecachepath"
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

    if ($Features -and $Features.Count -gt 0) {
        $arguments += "--features"
        $arguments += ($Features -join ",")
    }

    if ($GenerateReportLayout.IsPresent) {
        $arguments += "--generatereportlayout"
    }

    if ($Define -and $Define.Count -gt 0) {
        $arguments += "--define"
        $arguments += ($Define -join ";")
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

    $arguments += "--outfolder"
    $arguments += $PackageCachePath

    $generatedAppFiles = @()
    
    try {
        Write-Host "Executing: $script:alTool $($arguments -join ' ')" -ForegroundColor Green
        & $script:alTool @arguments | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "AL compilation failed with exit code $LASTEXITCODE"
        }
    } catch {
        throw $_
    } finally {
        # if package cache path and output folder are the same then no need to copy files
        # Copy the output files from the package cache to the output folder 
        Write-Host "Copying generated app files to output folder..."
        if (Test-Path $PackageCachePath) {
            if (-not (Test-Path $OutputFolder)) {
                New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            }
            Write-Host "Copying generated app files from package cache '$PackageCachePath' to output folder '$OutputFolder'"
            $files = Get-ChildItem -Path $PackageCachePath -File -Filter "*.app"
            Write-Host "Found $($files.Count) app files in package cache."
            Write-Host "$($files | ForEach-Object { $_.FullName } | Out-String)"
            $outputFiles = Get-ChildItem -Path $PackageCachePath -File -Filter "*.app" | Where-Object { $filesInPackageCache -notcontains $_.FullName }

            foreach ($file in $outputFiles) {
                Write-Host "Copying generated app file $($file.FullName) to $OutputFolder"
                $destinationPath = Join-Path $OutputFolder $file.Name
                $generatedAppFiles += $destinationPath
                if ($OutputFolder -eq $PackageCachePath) {
                    continue
                }
                Copy-Item -Path $file.FullName -Destination $destinationPath -Force -Verbose
            }
        }
    }

    Write-Host "Generated app files: $($generatedAppFiles | Out-String)"

    return $generatedAppFiles
}

function Get-AssemblyProbingPaths() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompilerFolder
    )
    $probingPaths = @()
    $dotNetRuntimeVersionInstalled = [System.Version] "8.0.22" # TODO
    $platformversion = [System.Version] "28.0.0.0" # TODO

    $compilerFolderDllsPath = Join-Path $CompilerFolder "dlls"
    $compilerFolderSharedPath = Join-Path $compilerFolderDllsPath "shared"
    
    
    if (Test-Path $compilerFolderDllsPath) {
        $probingPaths += @((Join-Path $compilerFolderDllsPath "Service"),(Join-Path $compilerFolderDllsPath "Mock Assemblies"))
    }

    if (Test-Path $compilerFolderSharedPath) {l
        $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), $compilerFolderSharedPath) + $probingPaths
    }
    elseif ($isLinux -or $isMacOS) {
        $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML")) + $probingPaths
    }
    elseif ($platformversion.Major -ge 22) {
        if ($dotNetRuntimeVersionInstalled -ge [System.Version]$bcContainerHelperConfig.MinimumDotNetRuntimeVersionStr) {
            $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), "C:\Program Files\dotnet\shared\Microsoft.NETCore.App\$dotNetRuntimeVersionInstalled", "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$dotNetRuntimeVersionInstalled") + $probingPaths
        }
        else {
            $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML")) + $probingPaths
        }
    }
    else {
        $probingPaths = @((Join-Path $compilerFolderDllsPath "OpenXML"), 'C:\Windows\Microsoft.NET\Assembly') + $probingPaths
    }



    return $probingPaths
}

function New-WorkspaceFromFolders() {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,
        
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceFile
    )
    $arguments = @("workspace", "create", $WorkspaceFile) + $Folders
    try {
        Write-Host "Executing: $script:alTool $($arguments -join ' ')" -ForegroundColor Green
        & $script:alTool @arguments | Out-Null
    } catch {
        throw $_
    }

    Write-Host "Workspace created at $WorkspaceFile"
}

function Get-PackageCacheFolder() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompilerFolder
    )
    $symbolsFolder = Join-Path $CompilerFolder "symbols"
    if (Test-Path $symbolsFolder) {
        return $symbolsFolder
    } else {
        throw "The specified compiler folder '$CompilerFolder' does not contain a 'symbols' subfolder."
    }
}

function Update-AppJsonProperties() {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Folders,
        
        [Parameter(Mandatory = $false)]
        [System.Version]$BuildVersion,

        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    foreach ($folder in $Folders) {
        $appJsonFiles = Get-ChildItem -Path $folder -Filter "app.json"
        foreach ($appJsonFile in $appJsonFiles) {
            $appJsonContent = Get-Content -Path $appJsonFile.FullName -Raw | ConvertFrom-Json

            if ($BuildVersion) {
                $appJsonContent.version = $BuildVersion.ToString()
            }

            # Add other properties to update as needed

            # Save the updated app.json file
            $appJsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $appJsonFile.FullName -Encoding UTF8
            Write-Host "Updated app.json at $($appJsonFile.FullName)"

            # Generate app file name
            $appFileName = "$($appJsonContent.Publisher)_$($appJsonContent.Name)_$($appJsonContent.Version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''

            # Delete existing app file in output folder if it exists
            $existingAppFilePath = Join-Path $OutputFolder $appFileName
            if (Test-Path $existingAppFilePath) {
                Remove-Item -Path $existingAppFilePath -Force
                Write-Host "Deleted existing app file at $existingAppFilePath"
            }
        }
    }
}

Export-ModuleMember -Function *-*