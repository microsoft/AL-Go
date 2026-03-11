# Module initialization: DLL loading, WCF dependency installation, type loading.
# Extracted from ALTestRunnerInternal.psm1.
# This script is dot-sourced once during module import.

function Install-WcfDependencies {
    <#
    .SYNOPSIS
    Downloads and extracts NuGet packages required for .NET Core/5+/6+ environments.
    These are needed because Microsoft.Dynamics.Framework.UI.Client.dll depends on types
    that are not included in modern .NET runtimes (only in full .NET Framework).
    #>
    param(
        [string]$TargetPath = $PSScriptRoot
    )

    $requiredPackages = @(
        @{ Name = "System.ServiceModel.Primitives"; Version = "6.0.0" },
        @{ Name = "System.ServiceModel.Http"; Version = "6.0.0" },
        @{ Name = "System.Private.ServiceModel"; Version = "4.10.3" },
        @{ Name = "System.Threading.Tasks.Extensions"; Version = "4.5.4" },
        @{ Name = "System.Runtime.CompilerServices.Unsafe"; Version = "6.0.0" }
    )

    $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) "BcClientPackages_$([Guid]::NewGuid().ToString().Substring(0,8))"
    
    try {
        foreach ($package in $requiredPackages) {
            $packageName = $package.Name
            $packageVersion = $package.Version
            $expectedDll = Join-Path $TargetPath "$packageName.dll"
            
            # Skip if already exists
            if (Test-Path $expectedDll) {
                Write-Host "Dependency $packageName already exists"
                continue
            }

            Write-Host "Downloading dependency: $packageName v$packageVersion"
            
            $nugetUrl = "https://www.nuget.org/api/v2/package/$packageName/$packageVersion"
            $packageZip = Join-Path $tempFolder "$packageName.zip"
            $packageExtract = Join-Path $tempFolder $packageName

            if (-not (Test-Path $tempFolder)) {
                New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
            }

            # Download the package
            Invoke-WebRequest -Uri $nugetUrl -OutFile $packageZip -UseBasicParsing

            # Extract
            Expand-Archive -Path $packageZip -DestinationPath $packageExtract -Force

            # Find the appropriate DLL (prefer net6.0, then netstandard2.0)
            $dllPath = $null
            $searchPaths = @(
                (Join-Path $packageExtract "lib\net6.0\$packageName.dll"),
                (Join-Path $packageExtract "lib\netstandard2.1\$packageName.dll"),
                (Join-Path $packageExtract "lib\netstandard2.0\$packageName.dll"),
                (Join-Path $packageExtract "lib\netcoreapp3.1\$packageName.dll")
            )
            
            foreach ($searchPath in $searchPaths) {
                if (Test-Path $searchPath) {
                    $dllPath = $searchPath
                    break
                }
            }

            if ($dllPath -and (Test-Path $dllPath)) {
                Copy-Item -Path $dllPath -Destination $TargetPath -Force
                Write-Host "Installed $packageName to $TargetPath"
            } else {
                Write-Warning "Could not find DLL for $packageName in package"
            }
        }
    }
    finally {
        # Cleanup temp folder
        if (Test-Path $tempFolder) {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if(!$script:TypesLoaded)
{
    # Load order matters - dependencies must be loaded before the client DLL
    # See: https://github.com/microsoft/navcontainerhelper/blob/main/AppHandling/PsTestFunctions.ps1
    # Fix for issue with Microsoft.Internal.AntiSSRF.dll v2.2+: https://github.com/microsoft/navcontainerhelper/pull/4063
    
    # Check if we're running on .NET Core/5+/6+ (PowerShell 7+) vs .NET Framework (Windows PowerShell 5.1)
    $isNetCore = $PSVersionTable.PSVersion.Major -ge 6
    
    # Always ensure System.Threading.Tasks.Extensions is available - AntiSSRF.dll v2.2+ needs it
    # regardless of .NET Framework or .NET Core
    $threadingExtDll = Join-Path $PSScriptRoot "System.Threading.Tasks.Extensions.dll"
    if (-not (Test-Path $threadingExtDll)) {
        Write-Host "Downloading System.Threading.Tasks.Extensions dependency..."
        $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) "ThreadingExt_$([Guid]::NewGuid().ToString().Substring(0,8))"
        try {
            New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
            $nugetUrl = "https://www.nuget.org/api/v2/package/System.Threading.Tasks.Extensions/4.5.4"
            $packageZip = Join-Path $tempFolder "package.zip"
            Invoke-WebRequest -Uri $nugetUrl -OutFile $packageZip -UseBasicParsing
            Expand-Archive -Path $packageZip -DestinationPath $tempFolder -Force
            # Use netstandard2.0 version for broadest compatibility
            $sourceDll = Join-Path $tempFolder "lib\netstandard2.0\System.Threading.Tasks.Extensions.dll"
            if (Test-Path $sourceDll) {
                Copy-Item -Path $sourceDll -Destination $PSScriptRoot -Force
                Write-Host "Installed System.Threading.Tasks.Extensions"
            }
        }
        finally {
            if (Test-Path $tempFolder) {
                Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    if ($isNetCore) {
        # On .NET Core/5+/6+, we need to install WCF packages as they're not included by default
        Write-Host "Running on .NET Core/.NET 5+, ensuring WCF dependencies are installed..."
        Install-WcfDependencies -TargetPath $PSScriptRoot
        
        # Load WCF dependencies first (order matters)
        $dependencyDlls = @(
            "System.Runtime.CompilerServices.Unsafe.dll",
            "System.Threading.Tasks.Extensions.dll",
            "System.Private.ServiceModel.dll",
            "System.ServiceModel.Primitives.dll", 
            "System.ServiceModel.Http.dll"
        )
        foreach ($dll in $dependencyDlls) {
            $dllPath = Join-Path $PSScriptRoot $dll
            if (Test-Path $dllPath) {
                try {
                    Add-Type -Path $dllPath -ErrorAction SilentlyContinue
                } catch {
                    # Ignore errors for already loaded assemblies
                }
            }
        }
    }
    
    # Now load the BC client dependencies in the correct order
    # Wrap in try/catch to get detailed LoaderExceptions if it fails
    try {
        Add-Type -Path "$PSScriptRoot\NewtonSoft.Json.dll"
        
        # Microsoft.Internal.AntiSSRF.dll v2.2+ requires System.Threading.Tasks.Extensions
        # Use AssemblyResolve event handler to help the runtime find it
        # See: https://github.com/microsoft/navcontainerhelper/pull/4063
        $antiSSRFdll = Join-Path $PSScriptRoot "Microsoft.Internal.AntiSSRF.dll"
        $threadingExtDll = Join-Path $PSScriptRoot "System.Threading.Tasks.Extensions.dll"
        
        if ((Test-Path $antiSSRFdll) -and (Test-Path $threadingExtDll)) {
            $Threading = [Reflection.Assembly]::LoadFile($threadingExtDll)
            $onAssemblyResolve = [System.ResolveEventHandler] {
                param($sender, $e)
                if ($e.Name -like "System.Threading.Tasks.Extensions, Version=*, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51") {
                    return $Threading
                }
                return $null
            }
            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
            try {
                Add-Type -Path $antiSSRFdll
            }
            finally {
                [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
            }
        }
        elseif (Test-Path $antiSSRFdll) {
            # Fall back to simple Add-Type if threading extensions not available
            Add-Type -Path $antiSSRFdll
        }
        
        Add-Type -Path "$PSScriptRoot\Microsoft.Dynamics.Framework.UI.Client.dll"
    }
    catch [System.Reflection.ReflectionTypeLoadException] {
        Write-Host "ReflectionTypeLoadException occurred while loading DLLs:"
        Write-Host "Exception Message: $($_.Exception.Message)"
        Write-Host "LoaderExceptions:"
        foreach ($loaderException in $_.Exception.LoaderExceptions) {
            if ($loaderException) {
                Write-Host "  - $($loaderException.Message)"
            }
        }
        throw
    }
    catch {
        Write-Host "Error loading DLLs: $($_.Exception.Message)"
        Write-Host "Exception Type: $($_.Exception.GetType().FullName)"
        if ($_.Exception.InnerException) {
            Write-Host "Inner Exception: $($_.Exception.InnerException.Message)"
        }
        throw
    }
    
    $clientContextScriptPath = Join-Path $PSScriptRoot "ClientContext.ps1"
    . "$clientContextScriptPath"
}

$script:TypesLoaded = $true
$script:ActiveDirectoryDllsLoaded = $false
