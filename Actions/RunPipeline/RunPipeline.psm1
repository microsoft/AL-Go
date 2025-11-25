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

        $symbolsOnlyCount = 0
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
                    $symbolsOnlyCount++
                    OutputWarning -Message "App $appFileName is a symbols package and should not be published. The workflow may fail if you try to publish it."
                }
            } else {
                Write-Host "App file path for $app could not be resolved. Skipping symbols check."
            }
        }

        if ($symbolsOnlyCount -gt 0) {
            Trace-Warning -Message "$symbolsOnlyCount symbols-only package(s) detected in install apps. These packages should not be published."
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

<#
    .SYNOPSIS
    Downloads an app file from a URL to a specified download path.
    .DESCRIPTION
    Downloads an app file from a URL to a specified download path.
    It handles URL decoding and sanitizes the file name.
    .PARAMETER Url
    The URL of the app file to download.
    .PARAMETER DownloadPath
    The path where the app file should be downloaded.
    .RETURNS
    The path to the downloaded app file.
#>
function Get-AppFileFromUrl {
    Param(
        [string] $Url,
        [string] $DownloadPath
    )
    try {
        # Get the file name from the URL
        $urlWithoutQuery = $Url.Split('?')[0].TrimEnd('/')
        $rawFileName = [System.IO.Path]::GetFileName($urlWithoutQuery)
        $decodedFileName = [Uri]::UnescapeDataString($rawFileName)
        $decodedFileName = [System.IO.Path]::GetFileName($decodedFileName)

        # Sanitize file name by removing invalid characters
        $sanitizedFileName = $decodedFileName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
        $sanitizedFileName = $sanitizedFileName.Trim()

        # Get the final app file path
        $appFile = Join-Path $DownloadPath $sanitizedFileName
        Invoke-WebRequest -Method GET -UseBasicParsing -Uri $Url -OutFile $appFile -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
    }
    catch {
        throw "Could not download app from URL: $($url). Error was: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Test-InstallApps, Get-AppFileFromUrl
