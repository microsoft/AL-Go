Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

function LoadDLL {
    Param(
        [string] $path
    )
    $bytes = [System.IO.File]::ReadAllBytes($path)
    [System.Reflection.Assembly]::Load($bytes) | Out-Null
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
    .PARAMETER RunnerTempFolder
    The temporary folder used by the runner (default is $ENV:RUNNER_TEMP).
#>
function Test-InstallApps() {
    Param(
        [string[]] $AllInstallApps,
        [string] $ProjectPath,
        [string] $RunnerTempFolder = $ENV:RUNNER_TEMP
    )
    try {
        # Create folder in temp directory with a unique name
        $tempFolder = Join-Path $RunnerTempFolder "DevelopmentTools-$(Get-Random)"

        # Download the Microsoft.Dynamics.BusinessCentral.Development.Tools package
        $version = GetPackageVersion -PackageName "Microsoft.Dynamics.BusinessCentral.Development.Tools"
        dotnet tool install "Microsoft.Dynamics.BusinessCentral.Development.Tools" --version $version --tool-path $tempFolder | Out-Host

        # Load the DLL from the temp folder
        $codeanalysisdll = Get-ChildItem -Path $tempFolder -Recurse | Where-Object { $_.FullName -like "*Microsoft.Dynamics.Nav.CodeAnalysis.dll" } | Select-Object -Last 1
        LoadDLL -path $codeanalysisdll.FullName

        foreach ($app in $allInstallApps) {
            $appFile = Join-Path $ProjectPath $app -Resolve -ErrorAction SilentlyContinue
            if ($appFile) {
                Write-Host "Analyzing app file $appFile"
                $appFileName = $appFile.BaseName
                $package = [Microsoft.Dynamics.Nav.CodeAnalysis.Packaging.NavAppPackageReader]::Create([System.IO.File]::OpenRead($appFile), $true)
                if ((($null -eq $package.ReadSourceCodeFilePaths()) -or ("" -eq $package.ReadSourceCodeFilePaths())) -and (-not $package.IsRuntimePackage)) {
                    # If package is not a runtime package and has no source code files, it is likely a symbols package
                    # Symbols packages are not meant to be published to a container
                    OutputWarning -message "App $appFileName is a symbols package and should not be published. The workflow may fail if you try to publish it."
                }
            }
        }
    }
    catch {
        Trace-Information -Message "Something went wrong while analyzing install apps. Error was: $($_.Exception.Message)"
    }

}

Export-ModuleMember -Function Test-InstallApps
