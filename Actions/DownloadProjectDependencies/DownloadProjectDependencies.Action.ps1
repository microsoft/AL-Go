Param(
    [Parameter(HelpMessage = "The project for which to download dependencies", Mandatory = $true)]
    [string] $project,
    [string] $baseFolder,
    [string] $buildMode = 'Default',
    [string] $projectDependenciesJson,
    [string] $baselineWorkflowRunID = '0',
    [string] $destinationPath,
    [string] $token
)

<#
    .SYNOPSIS
    Downloads a file from a URL to a specified download path.
    .DESCRIPTION
    Downloads a file from a URL to a specified download path.
    It handles URL decoding and sanitizes the file name.
    If the downloaded file is a zip file, it extracts the .app files from it.
    .PARAMETER Url
    The URL of the file to download.
    .PARAMETER DownloadPath
    The path where the file should be downloaded.
    .OUTPUTS
    An array of paths to the downloaded/extracted .app files.
#>
function Get-AppFilesFromUrl {
    Param(
        [string] $Url,
        [string] $DownloadPath
    )
    # Get the file name from the URL
    $urlWithoutQuery = $Url.Split('?')[0].TrimEnd('/')
    $rawFileName = [System.IO.Path]::GetFileName($urlWithoutQuery)
    $decodedFileName = [Uri]::UnescapeDataString($rawFileName)
    $decodedFileName = [System.IO.Path]::GetFileName($decodedFileName)

    # Sanitize file name by removing invalid characters
    $sanitizedFileName = $decodedFileName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $sanitizedFileName = $sanitizedFileName.Trim()

    if ([string]::IsNullOrWhiteSpace($sanitizedFileName)) {
        $sanitizedFileName = "$([Guid]::NewGuid().ToString()).app"
    }

    # Get the final file path
    $downloadedFile = Join-Path $DownloadPath $sanitizedFileName
    if (Test-Path -LiteralPath $downloadedFile) {
        OutputDebug -message "Overwriting existing file '$sanitizedFileName'. Multiple dependencies may resolve to the same filename."
    }

    # Download with retry logic
    Invoke-CommandWithRetry -ScriptBlock {
        Invoke-WebRequest -Method GET -UseBasicParsing -Uri $Url -OutFile $downloadedFile | Out-Null
    } -RetryCount 3 -FirstDelay 5 -MaxWaitBetweenRetries 10

    # Check if the downloaded file is a zip file
    $extension = [System.IO.Path]::GetExtension($downloadedFile).ToLowerInvariant()
    if ($extension -eq '.zip') {
        Write-Host "Extracting .app files from zip archive: $sanitizedFileName"
        
        # Extract to runner temp folder
        $extractPath = Join-Path $env:RUNNER_TEMP ([System.IO.Path]::GetFileNameWithoutExtension($sanitizedFileName))
        Expand-Archive -Path $downloadedFile -DestinationPath $extractPath -Force
        Remove-Item -Path $downloadedFile -Force

        # Find all .app files in the extracted folder and copy them to the download path
        $appFiles = @()
        foreach ($appFile in @(Get-ChildItem -Path $extractPath -Filter '*.app' -Recurse)) {
            $destFile = Join-Path $DownloadPath $appFile.Name
            Copy-Item -Path $appFile.FullName -Destination $destFile -Force
            $appFiles += $destFile
        }
        
        # Clean up the extracted folder
        Remove-Item -Path $extractPath -Recurse -Force

        if ($appFiles.Count -eq 0) {
            throw "Zip archive '$sanitizedFileName' does not contain any .app files"
        }
        Write-Host "Found $($appFiles.Count) .app file(s) in zip archive"
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
    For entries that are not URLs (local paths), they are returned as-is.
    .PARAMETER DestinationPath
    The path where the app files should be downloaded.
    .OUTPUTS
    A hashtable with Apps and TestApps arrays containing the resolved local file paths.
#>
function DownloadDependenciesFromInstallApps {
    Param(
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
        $install."$list" = @($install."$list" | ForEach-Object {
            $appFile = $_

            # If the app file is not a URL, return it as is
            if ($appFile -notlike 'http*://*') {
                Write-Host "install$($list) contains a local path: $appFile"
                return $appFile
            }

            # Else, check for secrets in the URL and replace them
            $appFileUrl = $appFile
            $pattern = '.*(\$\{\{\s*([^}]+?)\s*\}\}).*'
            if ($appFile -match $pattern) {
                $secretName = $matches[2]
                if (-not $secrets.ContainsKey($secretName)) {
                    throw "Setting: install$($list) references unknown secret '$secretName' in URL: $appFile"
                }
                $appFileUrl = $appFileUrl.Replace($matches[1],[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName")))
            }

            # Download the file (may return multiple .app files if it's a zip)
            try {
                Write-Host "Downloading from URL: $appFile"
                $appFiles = Get-AppFilesFromUrl -Url $appFileUrl -DownloadPath $DestinationPath
            } catch {
                throw "Setting: install$($list) contains an inaccessible URL: $appFile. Error was: $($_.Exception.Message)"
            }

            return $appFiles
        })
    }

    return $install
}

function DownloadDependenciesFromProbingPaths {
    param(
        $baseFolder,
        $project,
        $destinationPath,
        $token
    )

    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
    $settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project
    if ($settings.ContainsKey('appDependencyProbingPaths') -and $settings.appDependencyProbingPaths) {
        return GetDependencies -probingPathsJson $settings.appDependencyProbingPaths -saveToPath $destinationPath | Where-Object { $_ }
    }
}

function DownloadDependenciesFromCurrentBuild {
    param(
        $baseFolder,
        $project,
        $projectDependencies,
        $buildMode,
        $baselineWorkflowRunID,
        $destinationPath,
        $token
    )

    Write-Host "Downloading dependencies for project '$project'"

    $dependencyProjects = @()
    if ($projectDependencies.Keys -contains $project) {
        $dependencyProjects = @($projectDependencies."$project")
    }

    Write-Host "Dependency projects: $($dependencyProjects -join ', ')"

    # For each dependency project, calculate the corresponding probing path
    $dependeciesProbingPaths = @()
    foreach($dependencyProject in $dependencyProjects) {
        Write-Host "Reading settings for project '$dependencyProject'"
        $dependencyProjectSettings = ReadSettings -baseFolder $baseFolder -project $dependencyProject

        $dependencyBuildMode = $buildMode
        if ($dependencyBuildMode -ne 'Default' -and !($dependencyProjectSettings.buildModes -contains $dependencyBuildMode)) {
            # Download the default build mode if the specified build mode is not supported for the dependency project
            Write-Host "Build mode '$dependencyBuildMode' is not supported for project '$dependencyProject'. Using the default build mode."
            $dependencyBuildMode = 'Default';
        }

        $headBranch = $ENV:GITHUB_HEAD_REF
        # $ENV:GITHUB_HEAD_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
        if (!$headBranch) {
            $headBranch = $ENV:GITHUB_REF_NAME
        }

        $baseBranch = $ENV:GITHUB_BASE_REF
        # $ENV:GITHUB_BASE_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
        if (!$baseBranch) {
            $baseBranch = $ENV:GITHUB_REF_NAME
        }

        $dependeciesProbingPaths += @(@{
            "release_status"  = "thisBuild"
            "version"         = "latest"
            "buildMode"       = $dependencyBuildMode
            "projects"        = $dependencyProject
            "repo"            = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
            "branch"          = $headBranch
            "baseBranch"      = $baseBranch
            "baselineWorkflowID" = $baselineWorkflowRunID
            "authTokenSecret" = $token
        })
    }

    # For each probing path, download the dependencies
    $downloadedDependencies = @()
    foreach($probingPath in $dependeciesProbingPaths) {
        $buildMode = $probingPath.buildMode
        $project = $probingPath.projects
        $branch = $probingPath.branch
        $baseBranch = $probingPath.baseBranch
        $baselineWorkflowRunID = $probingPath.baselineWorkflowID

        Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Branch: $branch, Base Branch: $baseBranch, Baseline Workflow ID: $baselineWorkflowRunID"
        GetDependencies -probingPathsJson $probingPath -saveToPath $destinationPath | Where-Object { $_ } | ForEach-Object {
            $dependencyFileName = [System.IO.Path]::GetFileName($_.Trim('()'))
            if ($downloadedDependencies | Where-Object { [System.IO.Path]::GetFileName($_.Trim('()')) -eq $dependencyFileName }) {
                Write-Host "Dependency app '$dependencyFileName' already downloaded"
            }
            else {
                Write-Host "Dependency app '$dependencyFileName' downloaded"
                $downloadedDependencies += $_
            }
        }
    }

    return $downloadedDependencies
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Downloading dependencies for project '$project'. BuildMode: $buildMode, Base Folder: $baseFolder, Destination Path: $destinationPath"

$downloadedDependencies = @()

Write-Host "::group::Downloading project dependencies from current build"
$projectDependencies = $projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
$downloadedDependencies += DownloadDependenciesFromCurrentBuild -baseFolder $baseFolder -project $project -projectDependencies $projectDependencies -buildMode $buildMode -baselineWorkflowRunID $baselineWorkflowRunID -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading project dependencies from probing paths"
$downloadedDependencies += DownloadDependenciesFromProbingPaths -baseFolder $baseFolder -project $project -destinationPath $destinationPath -token $token
Write-Host "::endgroup::"

Write-Host "::group::Downloading dependencies from settings (installApps and installTestApps)"
$settingsDependencies = DownloadDependenciesFromInstallApps -DestinationPath $destinationPath
Write-Host "::endgroup::"

$downloadedApps = @()
$downloadedTestApps = @()

# Split the downloaded dependencies into apps and test apps
$downloadedDependencies | ForEach-Object {
    # naming convention: app, (testapp)
    if ($_.startswith('(')) {
        $downloadedTestApps += $_
    }
    else {
        $downloadedApps += $_
    }
}

# Add dependencies from settings
$downloadedApps += $settingsDependencies.Apps
$downloadedTestApps += $settingsDependencies.TestApps

OutputMessageAndArray -message "Downloaded dependencies (Apps)" -arrayOfStrings $downloadedApps
OutputMessageAndArray -message "Downloaded dependencies (Test Apps)" -arrayOfStrings $downloadedTestApps

# Write the downloaded apps and test apps to temporary JSON files and set them as GitHub Action outputs
$tempPath = NewTemporaryFolder
$downloadedAppsJson = Join-Path $tempPath "DownloadedApps.json"
$downloadedTestAppsJson = Join-Path $tempPath "DownloadedTestApps.json"
ConvertTo-Json $downloadedApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $downloadedAppsJson
ConvertTo-Json $downloadedTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $downloadedTestAppsJson

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedApps=$downloadedAppsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DownloadedTestApps=$downloadedTestAppsJson"
