Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
    Installs the AL tool.
    .DESCRIPTION
    Installs the AL tool from the Microsoft.Dynamics.BusinessCentral.Development.Tools package.
    .RETURNS
    The path to the al.exe tool.
#>
function Install-ALTool {
    $alToolFolder = Install-DotNetTool -PackageName "Microsoft.Dynamics.BusinessCentral.Development.Tools"
    # Load the AL tool from the downloaded package
    $alExe = Get-ChildItem -Path $alToolFolder -Filter "al*" | Where-Object { $_.Name -eq "al" -or $_.Name -eq "al.exe" } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $alExe) {
        throw "Could not find al.exe in the development tools package."
    }
    return $alExe
}

<#
    .SYNOPSIS
    Analyzes the install apps to check if they are symbols packages.
    .DESCRIPTION
    Analyzes the install apps to check if they are symbols packages.
    If an app is a symbols package, it outputs a warning message.
    .PARAMETER AllInstallApps
    The list of all install apps to analyze.
    .PARAMETER ProjectPath
    The path to the project where the apps are located.
#>
function Test-InstallApps() {
    Param(
        [string[]] $AllInstallApps,
        [string] $ProjectPath
    )

    if ($AllInstallApps.Count -eq 0) {
        Write-Host "No install apps to analyze."
        return
    }

    try {
        # Install the AL tool and get the path to al.exe
        $alExe = Install-ALTool

        foreach ($app in $AllInstallApps) {
            if (Test-Path -Path $app) {
                $appFilePath = (Get-Item -Path $app).FullName
            } else {
                $appFilePath = Join-Path $ProjectPath $app -Resolve -ErrorAction SilentlyContinue
            }

            if ($appFilePath) {
                $appFile = Get-Item -Path $appFilePath
                $appFileName = $appFile.Name
                Write-Host "Analyzing app file $appFileName"
                if (IsSymbolsOnlyPackage -AppFilePath $appFile -AlExePath $alExe) {
                    # If package is not a runtime package and has no source code files, it is a symbols package
                    # Symbols packages are not meant to be published to a BC Environment
                    OutputWarning -Message "App $appFileName is a symbols package and should not be published. The workflow may fail if you try to publish it."
                }
            } else {
                Write-Host "App file path for $app could not be resolved. Skipping symbols check."
            }
        }
    }
    catch {
        Trace-Warning -Message "Something went wrong while analyzing install apps."
        OutputDebug -message "Error: $_"
    }
}

function IsSymbolsOnlyPackage {
    param(
        [string] $AppFilePath,
        [string] $AlExePath
    )
    . $AlExePath IsSymbolOnly $AppFilePath | Out-Null
    return $LASTEXITCODE -eq 0
}

Export-ModuleMember -Function Test-InstallApps
