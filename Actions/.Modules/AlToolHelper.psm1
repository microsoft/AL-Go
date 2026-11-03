<#
.SYNOPSIS
    Provides shared AlTool installation and native process invocation for AL-Go actions.
#>

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

$alToolPackageId = "Microsoft.Dynamics.BusinessCentral.Development.Tools"

<#
.SYNOPSIS
    Invokes a native executable and returns its output streams and exit code.
.DESCRIPTION
    Keeps stdout separate from native stderr and restores the caller's error preference immediately
    after invocation. Windows PowerShell 5 stderr can include PowerShell formatting metadata.
    Command resolution and invocation failures remain terminating.
.PARAMETER FilePath
    The native executable name or full path.
.PARAMETER ArgumentList
    Arguments passed to the native executable.
.OUTPUTS
    [pscustomobject] with StandardOutput, StandardError, combined Output, and ExitCode properties.
#>
function Invoke-AlNativeCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [string[]] $ArgumentList = @()
    )

    $nativeCommand = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $standardErrorPath = Join-Path ([System.IO.Path]::GetTempPath()) "altool-stderr-$([Guid]::NewGuid().ToString('N')).txt"
    $originalErrorActionPreference = $ErrorActionPreference
    $nativeErrorPreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $originalNativeErrorPreference = if ($nativeErrorPreference) { $nativeErrorPreference.Value } else { $null }
    try {
        try {
            $ErrorActionPreference = "Continue"
            if ($nativeErrorPreference) {
                $PSNativeCommandUseErrorActionPreference = $false
            }
            $standardOutput = & $nativeCommand.Source @ArgumentList 2> $standardErrorPath
            [int] $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $originalErrorActionPreference
            if ($nativeErrorPreference) {
                $PSNativeCommandUseErrorActionPreference = $originalNativeErrorPreference
            }
        }

        [string[]] $standardOutputLines = @($standardOutput | ForEach-Object { "$_" })
        if (Test-Path -LiteralPath $standardErrorPath) {
            [string[]] $standardErrorLines = @(Get-Content -LiteralPath $standardErrorPath | ForEach-Object { "$_" })
        }
        else {
            [string[]] $standardErrorLines = @()
        }

        return [PSCustomObject]@{
            StandardOutput = $standardOutputLines
            StandardError  = $standardErrorLines
            Output         = [string[]] (@($standardOutputLines) + @($standardErrorLines))
            ExitCode       = $exitCode
        }
    }
    finally {
        Remove-Item -LiteralPath $standardErrorPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Verifies that an AlTool executable can report its version.
.PARAMETER AlToolPath
    Full path to the AlTool executable.
.OUTPUTS
    [string] The verified executable path.
#>
function Confirm-AlToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $AlToolPath
    )

    $versionResult = Invoke-AlNativeCommand -FilePath $AlToolPath -ArgumentList @("--version")
    if ($versionResult.ExitCode -ne 0) {
        throw "Failed to run 'al --version'. The command exited with code $($versionResult.ExitCode). Output: $($versionResult.Output -join [Environment]::NewLine)"
    }
    if ($versionResult.StandardOutput.Count -eq 0) {
        throw "Failed to run 'al --version'. The command returned no output."
    }
    Write-Host "Using al CLI version: $($versionResult.StandardOutput[0])"
    return $AlToolPath
}

<#
.SYNOPSIS
    Returns the deterministic directory used to install AlTool.
.DESCRIPTION
    Repository, run, and attempt IDs avoid stale installations when a self-hosted runner cannot
    clean RUNNER_TEMP. Local runs share one installation in the system temporary directory.
.OUTPUTS
    [string] The full installation directory path.
#>
function Get-AlToolInstallDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        $installationIdentity = "$($env:GITHUB_REPOSITORY_ID)-$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
        return [System.IO.Path]::GetFullPath(
            (Join-Path (Join-Path $env:RUNNER_TEMP "AL-Go-AlTool") $installationIdentity)
        )
    }
    return [System.IO.Path]::GetFullPath(
        (Join-Path ([System.IO.Path]::GetTempPath()) "AL-Go-AlTool")
    )
}

<#
.SYNOPSIS
    Returns the platform-specific AlTool executable name.
.PARAMETER Platform
    Operating system platform. Defaults to the current platform.
.OUTPUTS
    [string] al.exe on Windows, otherwise al.
#>
function Get-AlToolExecutableName {
    param(
        [System.PlatformID] $Platform = [Environment]::OSVersion.Platform
    )

    if ($Platform -eq [System.PlatformID]::Win32NT) {
        return "al.exe"
    }
    return "al"
}

<#
.SYNOPSIS
    Resolves the AlTool executable, installing the prerelease dotnet tool when needed.
.DESCRIPTION
    Reuses a valid path from AlToolPath or the deterministic run-scoped tool directory. Otherwise,
    installs the prerelease package into that directory with dotnet tool install --tool-path.
    Newly resolved paths are stored in the current process and GITHUB_ENV for later action steps.
.PARAMETER BcVersion
    BC release used for compilation. BC 28/29 use tool majors 17/18; BC 30 onwards uses
    the BC major. Selects the latest package in that release family, including prereleases,
    without assuming NuGet minor/build numbers match BC artifact minor/build numbers.
.PARAMETER UseTemporaryAlTool
    Explicitly override the published compiler with the temporary workspace-restore branch build.
.OUTPUTS
    [string] The full path to the AlTool executable.
#>
function GetAlToolPath {
    param(
        [version] $BcVersion,
        [switch] $UseTemporaryAlTool
    )

    $toolMajor = if ($BcVersion) {
        if ($BcVersion.Major -lt 28) {
            throw "Workspace compilation requires Business Central 28 or later."
        }
        if ($BcVersion.Major -lt 30) { $BcVersion.Major - 11 } else { $BcVersion.Major }
    } else { 0 }

    if (-not [string]::IsNullOrWhiteSpace($env:AlToolPath) -and
        (Test-Path -LiteralPath $env:AlToolPath -PathType Leaf)) {
        if ($toolMajor -and $env:ALGoAlToolMajor -ne "$toolMajor") {
            throw "The job already selected an ALTool for a different BC release. Run each BC release in a separate job."
        }
        return Confirm-AlToolPath -AlToolPath ([System.IO.Path]::GetFullPath($env:AlToolPath))
    }

    if (-not [string]::IsNullOrWhiteSpace($env:AlToolPath)) {
        Remove-Item Env:\AlToolPath -ErrorAction SilentlyContinue
    }

    $toolDirectory = Get-AlToolInstallDirectory
    if ($toolMajor) {
        $toolDirectory = Join-Path $toolDirectory "$toolMajor"
        Write-Host "Selecting ALTool release family $toolMajor for Business Central $BcVersion."
    }
    if ($UseTemporaryAlTool) {
        $toolDirectory = Join-Path $toolDirectory "workspace-restore-preview"
    }
    $alToolPath = Join-Path $toolDirectory (Get-AlToolExecutableName)
    if (-not (Test-Path -LiteralPath $alToolPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $toolDirectory) {
            Write-Host "Removing incomplete AlTool installation from '$toolDirectory'."
            Remove-Item -LiteralPath $toolDirectory -Recurse -Force
        }
        New-Item -Path $toolDirectory -ItemType Directory -Force | Out-Null

        if ($UseTemporaryAlTool) {
            Install-TemporaryAlTool -ToolDirectory $toolDirectory
        }
        else {
            $versionArguments = if ($toolMajor) { @("--version", "$toolMajor.*-*") } else { @("--prerelease") }
            Write-Host "Installing '$alToolPackageId' $($versionArguments -join ' ') into '$toolDirectory'..."
            $installResult = Invoke-AlNativeCommand -FilePath "dotnet" -ArgumentList (
                @("tool", "install", $alToolPackageId) + $versionArguments + @("--tool-path", $toolDirectory)
            )
            $installResult.Output | ForEach-Object { Write-Host $_ }
            if ($installResult.ExitCode -ne 0) {
                throw "Failed to install '$alToolPackageId' into '$toolDirectory'. dotnet tool install exited with code $($installResult.ExitCode). Output: $($installResult.Output -join [Environment]::NewLine)"
            }
        }
    }

    if (-not (Test-Path -LiteralPath $alToolPath -PathType Leaf)) {
        throw "The AlTool installation command completed, but the expected executable '$alToolPath' does not exist."
    }

    $alToolPath = Confirm-AlToolPath -AlToolPath ([System.IO.Path]::GetFullPath($alToolPath))

    $env:AlToolPath = $alToolPath
    $env:ALGoAlToolMajor = "$toolMajor"
    if ($env:GITHUB_ENV) {
        Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "AlToolPath=$alToolPath"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "ALGoAlToolMajor=$toolMajor"
    }
    return $alToolPath
}

<#
.SYNOPSIS
    Installs the temporary workspace-restore branch build for explicit preview testing.
.PARAMETER ToolDirectory
    Destination for the runtime-only bundle. Requires the .NET 10 SDK/runtimes.
#>
function Install-TemporaryAlTool {
    param([Parameter(Mandatory = $true)][string] $ToolDirectory)

    Write-Host "::Warning::Using the temporary BC 30 workspace-restore branch build instead of the BC-selected published compiler."
    $archive = Join-Path $ToolDirectory "altool.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Aholstrup1-PersonalOrg/bcsamples-bingmaps.appsource/releases/download/workspace-restore-preview/altool-workspace-restore-v2.zip" -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne '7488028EFDC14546B143C1AD4C7E831CD941B66DDEE9BE1DA1EB3D2CE5057D78') {
        throw "The temporary ALTool download does not match the approved branch-build bundle."
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $ToolDirectory -Force
    Remove-Item -LiteralPath $archive -Force
    $executable = Join-Path $ToolDirectory (Get-AlToolExecutableName)
    if ([Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        Copy-Item -LiteralPath (Join-Path $ToolDirectory "altool.exe") -Destination $executable
    }
    else {
        Set-Content -LiteralPath $executable -Encoding ASCII -Value "#!/bin/sh`nexec dotnet `"`$(dirname `"`$0`")/altool.dll`" `"`$@`""
        $result = Invoke-AlNativeCommand -FilePath "chmod" -ArgumentList @("+x", $executable)
        if ($result.ExitCode -ne 0) { throw "Failed to make the temporary ALTool executable: $($result.Output -join ' ')" }
    }
}

Export-ModuleMember -Function GetAlToolPath, Invoke-AlNativeCommand
