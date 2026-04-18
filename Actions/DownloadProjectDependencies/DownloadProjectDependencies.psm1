Import-Module -Name (Join-Path $PSScriptRoot '../Github-Helper.psm1')
. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
    Tests if a file is a ZIP archive by checking for the "PK" magic bytes.
    .PARAMETER Path
    The path to the file to test.
    .OUTPUTS
    $true if the file is a ZIP archive, $false otherwise.
#>
function Test-IsZipFile {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $Path
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.zip') {
        return $true
    }
    if ($extension -eq '.app') {
        # Don't treat .app files as zips. These should not be extracted.
        return $false
    }
    # Check for ZIP magic bytes "PK" (0x50 0x4B)
    # This handles the case where the file does not have a .zip extension but is still a ZIP archive (like .nupkg)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $bytes = @(Get-Content -Path $Path -AsByteStream -TotalCount 2 -ErrorAction SilentlyContinue)
    } else {
        $bytes = @(Get-Content -Path $Path -Encoding Byte -TotalCount 2 -ErrorAction SilentlyContinue)
    }
    if ($bytes -and $bytes.Count -eq 2) {
        return ([char]$bytes[0] -eq 'P') -and ([char]$bytes[1] -eq 'K')
    }
    return $false
}

<#
    .SYNOPSIS
    Extracts .app files from a ZIP archive to the destination path.
    .PARAMETER ZipFile
    The path to the ZIP file.
    .PARAMETER DestinationPath
    The path where .app files should be extracted to.
    .PARAMETER MaxDepth
    Maximum nesting depth for recursive ZIP extraction. Default is 3.
    .OUTPUTS
    An array of paths to the extracted .app files.
#>
function Expand-ZipFileToAppFiles {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $ZipFile,
        [Parameter(Mandatory=$true)]
        [string] $DestinationPath,
        [int] $MaxDepth = 3
    )
    if ($MaxDepth -le 0) {
        OutputWarning -message "Maximum ZIP nesting depth reached for: $([System.IO.Path]::GetFileName($ZipFile)). Skipping further extraction."
        return @()
    }
    $fileName = [System.IO.Path]::GetFileName($ZipFile)
    OutputDebug -message "Expanding zip file to extract .app files: $ZipFile"

    # If file doesn't have .zip extension, copy to temp with .zip extension for Expand-Archive
    $zipToExtract = $ZipFile
    $tempZipCreated = $false
    if ([System.IO.Path]::GetExtension($ZipFile).ToLowerInvariant() -ne '.zip') {
        $newZipFileName = "$([System.IO.Path]::GetFileName($ZipFile))_$(Get-Date -Format 'HHmmssfff').zip"
        $zipToExtract = Join-Path (GetTemporaryPath) $newZipFileName
        Copy-Item -Path $ZipFile -Destination $zipToExtract
        $tempZipCreated = $true
    }

    try {
        # Extract to runner temp folder
        $extractFileName = "$([System.IO.Path]::GetFileNameWithoutExtension($fileName))_$(Get-Date -Format 'HHmmssfff')"
        $extractPath = Join-Path (GetTemporaryPath) $extractFileName
        Expand-Archive -Path $zipToExtract -DestinationPath $extractPath -Force

        # Find all files in the extracted folder and process them
        $appFiles = @()
        foreach ($file in (Get-ChildItem -Path $extractPath -Recurse -File)) {
            $extension = [System.IO.Path]::GetExtension($file.FullName).ToLowerInvariant()

            if ($extension -eq '.app') {
                $destFile = Join-Path $DestinationPath $file.Name
                Copy-Item -Path $file.FullName -Destination $destFile -Force
                $appFiles += $destFile
            }
            elseif (Test-IsZipFile -Path $file.FullName) {
                # Recursively extract nested ZIP files
                $appFiles += Expand-ZipFileToAppFiles -ZipFile $file.FullName -DestinationPath $DestinationPath -MaxDepth ($MaxDepth - 1)
            }
        }

        if ($appFiles.Count -eq 0) {
            OutputWarning -message "No .app files found in zip archive: $fileName"
        } else {
            OutputDebug -message "Found $($appFiles.Count) .app file(s) in zip archive"
        }
        return $appFiles
    }
    finally {
        # Clean up the extracted folder
        if (Test-Path -Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        # Clean up the temp zip file if we created one
        if ($tempZipCreated) {
            Remove-Item -Path $zipToExtract -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
    .SYNOPSIS
    Resolves a local path to an array of .app file paths.
    .DESCRIPTION
    Handles local files and folders:
    - If path is an .app file: returns it
    - If path is a folder: recursively finds all .app files
    - If path contains wildcards: resolves them to matching files
    - If path is a ZIP file (by extension or magic bytes): extracts and returns .app files
    .PARAMETER Path
    The local file or folder path.
    .PARAMETER DestinationPath
    The path where extracted .app files should be placed (for ZIP files).
    .OUTPUTS
    An array of paths to .app files.
#>
function Get-AppFilesFromLocalPath {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $Path,
        [Parameter(Mandatory=$true)]
        [string] $DestinationPath
    )

    # Ensure the destination directory exists
    if (-not (Test-Path -Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    # Get all matching items (works for folders, wildcards, and single files)
    $matchedItems = @(Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue)

    if ($matchedItems.Count -eq 0) {
        OutputWarning -message "No files found at local path: $Path"
        return @()
    }

    # Process each matched file
    $appFiles = @()
    foreach ($item in $matchedItems) {
        $extension = [System.IO.Path]::GetExtension($item.FullName).ToLowerInvariant()

        if ($extension -eq '.app') {
            $destFile = Join-Path $DestinationPath $item.Name
            if ($item.FullName -ne $destFile) {
                Copy-Item -Path $item.FullName -Destination $destFile -Force
            } else {
                # This can happen if the user specifies a local path that is the same as AL-Go uses for storing dependencies
                OutputDebug -message "Source and destination are the same for .app file: $destFile. Skipping copy."
            }
            $appFiles += $destFile
        } elseif (Test-IsZipFile -Path $item.FullName) {
            $appFiles += Expand-ZipFileToAppFiles -ZipFile $item.FullName -DestinationPath $DestinationPath
        } else {
            OutputWarning -message "Unknown file type for local path: $($item.FullName). Skipping."
        }
    }
    return $appFiles
}

<#
    .SYNOPSIS
    Downloads a file from a URL to a specified download path.
    .DESCRIPTION
    Downloads a file from a URL to a specified download path.
    It handles URL decoding and sanitizes the file name.
    If the downloaded file is a zip file, it extracts the .app files from it.
    .PARAMETER Url
    The URL of the file to download.
    .PARAMETER CleanUrl
    The original URL for error reporting.
    .PARAMETER DownloadPath
    The path where the file should be downloaded.
    .OUTPUTS
    An array of paths to the downloaded/extracted .app files.
#>
function Get-AppFilesFromUrl {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $Url,
        [Parameter(Mandatory=$true)]
        [string] $CleanUrl,
        [Parameter(Mandatory=$true)]
        [string] $DownloadPath
    )

    # Ensure the download directory exists
    if (-not (Test-Path -Path $DownloadPath)) {
        New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
    }

    # Get the file name from the URL
    $urlWithoutQuery = $Url.Split('?')[0].TrimEnd('/')
    $rawFileName = [System.IO.Path]::GetFileName($urlWithoutQuery)
    $decodedFileName = [Uri]::UnescapeDataString($rawFileName)
    $decodedFileName = [System.IO.Path]::GetFileName($decodedFileName)

    # Sanitize file name by removing invalid characters
    $sanitizedFileName = $decodedFileName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $sanitizedFileName = $sanitizedFileName.Trim()

    if ([string]::IsNullOrWhiteSpace($sanitizedFileName)) {
        # Assume the file is an .app file if no valid name could be determined
        $sanitizedFileName = "$([Guid]::NewGuid().ToString()).app"
    }

    # Get the final file path
    $downloadedFile = Join-Path $DownloadPath $sanitizedFileName
    if (Test-Path -LiteralPath $downloadedFile) {
        OutputWarning -message "Overwriting existing file '$sanitizedFileName'. Multiple dependencies may resolve to the same filename."
    }

    # Download with retry logic
    try {
        Invoke-CommandWithRetry -ScriptBlock {
            Invoke-WebRequest -Method GET -UseBasicParsing -Uri $Url -OutFile $downloadedFile | Out-Null
        } -RetryCount 3 -FirstDelay 5 -MaxWaitBetweenRetries 10
        OutputDebug -message "Downloaded file to path: $downloadedFile"
    } catch {
        throw "Failed to download file from inaccessible URL: $CleanUrl. Error was: $($_.Exception.Message)"
    }

    # Check if the downloaded file is a zip file (by extension or magic bytes)
    if (Test-IsZipFile -Path $downloadedFile) {
        $appFiles = Expand-ZipFileToAppFiles -ZipFile $downloadedFile -DestinationPath $DownloadPath
        Remove-Item -Path $downloadedFile -Force -ErrorAction SilentlyContinue
        return $appFiles
    }

    return @($downloadedFile)
}

<#
    .SYNOPSIS
    Downloads dependencies from URLs specified in installApps and installTestApps settings.
    .DESCRIPTION
    Reads the installApps and installTestApps arrays from the repository settings.
    For each entry that is a URL (starts with http:// or https://):
    - Resolves any secret placeholders in the format ${{ secretName }} by looking up the secret value
    - Downloads the app file to the specified destination path
    For entries that are local paths:
    - Resolves folders to their contained .app files
    - Extracts .app files from ZIP archives
    .PARAMETER DestinationPath
    The path where the app files should be downloaded.
    .OUTPUTS
    A hashtable with Apps and TestApps arrays containing the resolved local file paths.
#>
function Get-DependenciesFromInstallApps {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $DestinationPath
    )

    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable

    # ENV:Secrets is not set when running Pull_Request trigger
    if ($env:Secrets) {
        $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $secrets = @{}
    }

    # Initialize the install hashtable
    $install = @{
        "Apps" = @($settings.installApps)
        "TestApps" = @($settings.installTestApps)
    }

    # Check if the installApps and installTestApps settings are empty
    if (($settings.installApps.Count -eq 0) -and ($settings.installTestApps.Count -eq 0)) {
        Write-Host "No installApps or installTestApps settings found."
        return $install
    }

    # Replace secret names in install.apps and install.testApps and download files from URLs
    foreach($list in @('Apps','TestApps')) {

        $updatedListOfFiles = @()
        foreach($appFile in $install."$list") {
            if ([string]::IsNullOrWhiteSpace($appFile)) {
                continue
            }
            Write-Host "Processing install$($list) entry: $appFile"

            # If the app file is not a URL, resolve local path.
            if ($appFile -notlike 'http*://*') {
                $updatedListOfFiles += Get-AppFilesFromLocalPath -Path $appFile -DestinationPath $DestinationPath
            } else {
                # Else, check for secrets in the URL and replace them. Only match on the first occurrence of the pattern ${{ secretName }}
                $appFileUrl = $appFile
                $pattern = '.*(\$\{\{\s*([^}]+?)\s*\}\}).*'
                if ($appFile -match $pattern) {
                    $secretName = $matches[2]
                    if (-not $secrets.ContainsKey($secretName) -or [string]::IsNullOrEmpty($secrets."$secretName")) {
                        throw "Setting: install$($list) references unknown secret '$secretName' in URL: $appFile"
                    }
                    $appFileUrl = $appFileUrl.Replace($matches[1],[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName")))
                }

                # Download the file (may return multiple .app files if it's a zip)
                $appFiles = Get-AppFilesFromUrl -Url $appFileUrl -CleanUrl $appFile -DownloadPath $DestinationPath

                $updatedListOfFiles += $appFiles
            }
        }

        # Update the install hashtable with the resolved file paths
        $install."$list" = $updatedListOfFiles
    }

    return $install
}

<#
    .SYNOPSIS
    Downloads runtime app packages from NuGet feeds based on app.json dependencies.
    .DESCRIPTION
    Reads app.json files from the project's app and test folders, creates a temporary
    workspace file, then uses 'altool workspace restore' to download dependency .app
    files (runtime packages) from the specified NuGet feed.

    This is used to get Microsoft first-party app dependencies (like Base Application,
    System Application, etc.) as runtime packages from the MSAppsV2 feed.
    .PARAMETER ProjectFolder
    The root folder of the project containing app folders.
    .PARAMETER AppFolders
    Array of app folder names to include in the workspace.
    .PARAMETER TestFolders
    Array of test folder names to include in the workspace.
    .PARAMETER DestinationPath
    The folder where downloaded .app files will be placed.
    .PARAMETER Country
    The country/region code for symbol resolution (e.g. 'us', 'dk'). Defaults to 'us'.
    .PARAMETER CompilerFolder
    Path to the compiler folder containing the AL tool. If not provided, the compiler
    will be installed from NuGet.
    .PARAMETER NuGetFeed
    The NuGet feed URL to use for downloading runtime packages.
    .OUTPUTS
    An array of paths to downloaded .app files.
#>
function Get-RuntimePackagesFromNuGet {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $ProjectFolder,

        [Parameter(Mandatory = $true)]
        [string[]] $AppFolders,

        [Parameter(Mandatory = $false)]
        [string[]] $TestFolders = @(),

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath,

        [Parameter(Mandatory = $false)]
        [string] $Country = 'us',

        [Parameter(Mandatory = $false)]
        [string] $CompilerFolder = '',

        [Parameter(Mandatory = $false)]
        [string] $NuGetFeed = 'https://dynamicssmb2.pkgs.visualstudio.com/_packaging/MSAppsV2/nuget/v3/index.json'
    )

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "../.Modules/CompileFromWorkspace.psm1" -Resolve) -DisableNameChecking

    $allFolders = @($AppFolders) + @($TestFolders) | Where-Object { $_ }
    if ($allFolders.Count -eq 0) {
        Write-Host "No app folders specified - skipping NuGet runtime package download"
        return @()
    }

    # If no compiler folder provided, install a temporary one
    $tempCompiler = $false
    if (-not $CompilerFolder -or -not (Test-Path $CompilerFolder)) {
        $CompilerFolder = Join-Path (GetTemporaryPath) "nuget-restore-compiler"
        $artifact = $env:artifact
        Install-ALCompiler -CompilerFolder $CompilerFolder -ArtifactUrl $artifact
        $tempCompiler = $true
    }

    try {
        $alToolPath = Get-ALTool -CompilerFolder $CompilerFolder
        $packageCachePath = Join-Path $CompilerFolder "symbols"
        if (-not (Test-Path $packageCachePath)) {
            New-Item -Path $packageCachePath -ItemType Directory -Force | Out-Null
        }

        # Create a temporary workspace file
        $datetimeStamp = Get-Date -Format "yyyyMMddHHmmss"
        $workspaceFile = Join-Path $ProjectFolder "tempRestore$datetimeStamp.code-workspace"

        Push-Location $ProjectFolder
        try {
            New-WorkspaceFromFolders -Folders $allFolders -WorkspaceFile $workspaceFile -AltoolPath $alToolPath

            # Set the NuGet config to only use the specified feed
            $nugetConfigPath = Join-Path $ProjectFolder "nuget.config"
            $nugetConfigCreated = $false
            if (-not (Test-Path $nugetConfigPath)) {
                @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <packageSources>
        <clear />
        <add key="MSAppsV2" value="$NuGetFeed" />
    </packageSources>
</configuration>
"@ | Set-Content -Path $nugetConfigPath -Encoding UTF8
                $nugetConfigCreated = $true
            }

            try {
                # Run workspace restore to download runtime packages
                Invoke-WorkspaceRestore -ALToolPath $alToolPath -WorkspaceFile $workspaceFile -PackageCachePath $packageCachePath -Country $Country
            }
            finally {
                if ($nugetConfigCreated -and (Test-Path $nugetConfigPath)) {
                    Remove-Item -Path $nugetConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        finally {
            Pop-Location
            if (Test-Path $workspaceFile) {
                Remove-Item -Path $workspaceFile -Force -ErrorAction SilentlyContinue
            }
        }

        # Copy downloaded .app files to destination
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }

        $downloadedApps = @()
        Get-ChildItem -Path $packageCachePath -Filter "*.app" -File | ForEach-Object {
            $destFile = Join-Path $DestinationPath $_.Name
            Copy-Item -Path $_.FullName -Destination $destFile -Force
            $downloadedApps += $destFile
            Write-Host "Downloaded runtime package: $($_.Name)"
        }

        return $downloadedApps
    }
    finally {
        if ($tempCompiler -and (Test-Path $CompilerFolder)) {
            Remove-Item -Path $CompilerFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Get-AppFilesFromUrl, Get-AppFilesFromLocalPath, Get-DependenciesFromInstallApps, Get-RuntimePackagesFromNuGet
