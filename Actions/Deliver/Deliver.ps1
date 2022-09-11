Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Projects to deliver (default is all)", Mandatory = $false)]
    [string] $projects = "*",
    [Parameter(HelpMessage = "Delivery target (AppSource or Storage)", Mandatory = $true)]
    [ValidateSet('AppSource','Storage')]
    [string] $deliveryTarget,
    [Parameter(HelpMessage = "Artifacts to deliver", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of delivery (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "Types of artifacts to deliver (Apps,Dependencies,TestApps)", Mandatory = $false)]
    [string] $atypes = "Apps,Dependencies,TestApps",
    [Parameter(HelpMessage = "Promote AppSource App to Go Live? (Y/N)", Mandatory = $false)]
    [bool] $goLive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0081' -parentTelemetryScopeJson $parentTelemetryScopeJson

    if ($projects -eq '') { $projects = "*" }

    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $env:GITHUB_WORKFLOW
    if ($settings.Projects) {
        $projectList = $settings.projects | Where-Object { $_ -like $projects }
    }
    else {
        $projectList = @(Get-ChildItem -Path $ENV:GITHUB_WORKSPACE -Directory -Recurse -Depth 2 | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object { $_.FullName.Substring("$ENV:GITHUB_WORKSPACE".length+1) })
        if (Test-Path (Join-Path $ENV:GITHUB_WORKSPACE ".AL-Go") -PathType Container) {
            $projectList += @(".")
        }
    }
    $projectArr = $projects.Split(',')
    $projectList = @($projectList | Where-Object { $project = $_; if ($projectArr | Where-Object { $project -like $_ }) { $project } })

    if ($projectList.Count -eq 0) {
        throw "No projects matches the pattern '$projects'"
    }
    if ($deliveryTarget -eq "AppSource") {
        $atypes = "Apps,Dependencies"        
    }
    Write-Host "Projects:"
    $projectList | Out-Host

    if ("$env:deliveryContext" -eq "") {
        throw "$($deliveryTarget)Context is not defined, cannot deliver to $deliveryTarget"
    }

    $key = "$($deliveryTarget)Context"
    Write-Host "Using $key"
    Set-Variable -Name $key -Value $env:deliveryContext

    $projectList | ForEach-Object {
        $thisProject = $_
        if ($thisProject -and ($thisProject -ne '.')) {
            $project = $thisProject
        }
        else {
            $project = $env:RepoName
        }
        $projectName = $project -replace "[^a-z0-9]", "-"
        Write-Host "Project '$project'"
        $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE "artifacts"

        if ($artifacts -like "$($ENV:GITHUB_WORKSPACE)*") {
            # artifacts already present
        }
        elseif ($artifacts -eq "current" -or $artifacts -eq "prerelease" -or $artifacts -eq "draft") {
            # latest released version
            $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
            if ($artifacts -eq "current") {
                $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
            }
            elseif ($artifacts -eq "prerelease") {
                $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
            }
            elseif ($artifacts -eq "draft") {
                $release = $releases | Select-Object -First 1
            }
            if (!($release)) {
                throw "Unable to locate $artifacts release"
            }
            New-Item $baseFolder -ItemType Directory | Out-Null
            $artifactFile = DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $baseFolder -mask "Apps"
            Write-Host "'$artifactFile'"
            if (!$artifactFile -or !(Test-Path $artifactFile)) {
                throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
            }
            if ($artifactFile -notlike '*.zip') {
                throw "Downloaded artifact is not a .zip file"
            }
            Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0,$artifactFile.Length-4))
            Remove-Item $artifactFile -Force
        }
        else {
            New-Item $baseFolder -ItemType Directory | Out-Null
            $atypes.Split(',') | ForEach-Object {
                $atype = $_
                $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $atype -projects $project -Version $artifacts -branch "main"
                if ($allArtifacts) {
                    $allArtifacts | ForEach-Object {
                        $artifactFile = DownloadArtifact -token $token -artifact $_ -path $baseFolder
                        Write-Host $artifactFile
                        if (!(Test-Path $artifactFile)) {
                            throw "Unable to download artifact $($_.name)"
                        }
                        if ($artifactFile -notlike '*.zip') {
                            throw "Downloaded artifact is not a .zip file"
                        }
                        Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0,$artifactFile.Length-4))
                        Remove-Item $artifactFile -Force
                    }
                }
                else {
                    if ($atype -eq "Apps") {
                        throw "ERROR: Could not find any $atype artifacts for projects $projects, version $artifacts"
                    }
                    else {
                        Write-Host "WARNING: Could not find any $atype artifacts for projects $projects, version $artifacts"
                    }
                }
            }
        }

        if ($deliveryTarget -eq "Storage") {
            try {
                if (get-command New-AzureStorageContext -ErrorAction SilentlyContinue) {
                    Write-Host "Using Azure.Storage PowerShell module"
                }
                else {
                    if (!(get-command New-AzStorageContext -ErrorAction SilentlyContinue)) {
                        OutputError -message "When delivering to storage account, the build agent needs to have either the Azure.Storage or the Az.Storage PowerShell module installed."
                        exit
                    }
                    Write-Host "Using Az.Storage PowerShell module"
                    Set-Alias -Name New-AzureStorageContext -Value New-AzStorageContext
                    Set-Alias -Name Get-AzureStorageContainer -Value Get-AzStorageContainer
                    Set-Alias -Name Set-AzureStorageBlobContent -Value Set-AzStorageBlobContent
                }
                $storageAccount = $storageContext | ConvertFrom-Json | ConvertTo-HashTable
                if ($storageAccount.ContainsKey('sastoken')) {
                    $azStorageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -SasToken $storageAccount.sastoken
                }
                else {
                    $azStorageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageAccount.StorageAccountKey
                }
                Write-Host "Storage Context OK"
            }
            catch {
                throw "StorageContext secret is malformed. Needs to be formatted as Json, containing StorageAccountName, containerName, blobName and sastoken or storageAccountKey, which points to an existing container in a storage account."
            }

            $storageContainerName =  $storageAccount.ContainerName.ToLowerInvariant().replace('{project}',$projectName).ToLowerInvariant()
            $storageBlobName = $storageAccount.BlobName.ToLowerInvariant()
            Write-Host "Storage Container Name is $storageContainerName"
            Write-Host "Storage Blob Name is $storageBlobName"
            Get-AzureStorageContainer -Context $azStorageContext -name $storageContainerName | Out-Null
            Write-Host "Delivering to $storageContainerName in $($storageAccount.StorageAccountName)"
            $atypes.Split(',') | ForEach-Object {
                $atype = $_
                $artfolder = @(Get-ChildItem -Path (Join-Path $baseFolder "$project-*-$atype-*") -Directory)
                if ($artFolder.Count -eq 0) {
                    if ($atype -eq "Apps") {
                        throw "Error - unable to locate apps"
                    }
                    else {
                        Write-Host "WARNING: Unable to locate $atype"
                    }
                }
                elseif ($artFolder.Count -gt 1) {
                    $artFolder | Out-Host
                    throw "Internal error - multiple $atype folders located"
                }
                else {
                    $artfolder = $artfolder[0].FullName
                    $version = $artfolder.SubString($artfolder.IndexOf("-$atype-")+"-$atype-".Length)
                    Write-Host $artfolder
                    $versions = @("$version-preview","preview")
                    if ($type -eq "Publish") {
                        $versions += @($version,"latest")
                    }
                    $tempFile = Join-Path $ENV:TEMP "$([Guid]::newguid().ToString()).zip"
                    try {
                        Write-Host "Compressing"
                        Compress-Archive -Path (Join-Path $artfolder '*') -DestinationPath $tempFile -Force
                        $versions | ForEach-Object {
                            $version = $_
                            $blob = $storageBlobName.replace('{project}',$projectName).replace('{version}',$version).replace('{type}',$atype).ToLowerInvariant()
                            Write-Host "Delivering $blob"
                            Set-AzureStorageBlobContent -Context $azStorageContext -Container $storageContainerName -File $tempFile -blob $blob -Force | Out-Null
                        }
                    }
                    finally {
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        elseif ($deliveryTarget -eq "AppSource") {
            $appSourceContextHt = $appSourceContext | ConvertFrom-Json | ConvertTo-HashTable
            $authContext = New-BcAuthContext @appSourceContextHt

            $projectSettings = Get-Content -Path (Join-Path $ENV:GITHUB_WORKSPACE "$thisProject\.AL-Go\settings.json") | ConvertFrom-Json | ConvertTo-HashTable -Recurse
            if ($projectSettings.ContainsKey("AppSourceMainAppFolder")) {
                $AppSourceMainAppFolder = $projectSettings.AppSourceMainAppFolder
            }
            else {
                try {
                    $AppSourceMainAppFolder = $projectSettings.appFolders[0]
                }
                catch {
                    throw "Unable to determine main App folder"
                }
            }
            if (-not $projectSettings.ContainsKey('AppSourceProductId')) {
                throw "AppSourceProductId needs to be specified in $thisProject\.AL-Go\settings.json in order to deliver to AppSource"
            }
            Write-Host "AppSource MainAppFolder $AppSourceMainAppFolder"

            $mainAppJson = Get-Content -Path (Join-Path $ENV:GITHUB_WORKSPACE "$AppSourceMainAppFolder\app.json") | ConvertFrom-Json
            $mainAppVersion = [Version]$mainAppJson.Version
            $mainAppFileName = ("$($mainAppJson.Publisher)_$($mainAppJson.Name)_".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '') + "*.*.*.*.app"
            $artfolder = @(Get-ChildItem -Path (Join-Path $baseFolder "*-Apps-*") -Directory)
            if ($artFolder.Count -eq 0) {
                throw "Internal error - unable to locate apps"
            }
            if ($artFolder.Count -gt 1) {
                $artFolder | Out-Host
                throw "Internal error - multiple apps located"
            }
            $artfolder = $artfolder[0].FullName
            $appFile = Get-ChildItem -path $artFolder | Where-Object { $_.name -like $mainAppFileName } | ForEach-Object { $_.FullName }
            $libraryAppFiles = @(Get-ChildItem -path $artFolder | Where-Object { $_.name -notlike $mainAppFileName } | ForEach-Object { $_.FullName })
            Write-Host "Main App File:"
            Write-Host "- $([System.IO.Path]::GetFileName($appFile))"
            Write-Host "Library App Files:"
            if ($libraryAppFiles.Count -eq 0) {
                Write-Host "- None"
            }
            else {
                $libraryAppFiles | ForEach-Object { Write-Host "- $([System.IO.Path]::GetFileName($_))" }
            }
            if (-not $appFile) {
                throw "Unable to locate main app file ($mainAppFileName doesn't exist)"
            }
            Write-Host "Submitting to AppSource"
            New-AppSourceSubmission -authContext $authContext -productId $projectSettings.AppSourceProductId -appFile $appFile -libraryAppFiles $libraryAppFiles -doNotWait -autoPromote:$goLive -Force
        }
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Deliver action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
