Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Projects to deliver (default is all)", Mandatory = $false)]
    [string] $projects = "*",
    [Parameter(HelpMessage = "Delivery target (AppSource or Storage)", Mandatory = $true)]
    [string] $deliveryTarget,
    [Parameter(HelpMessage = "Artifacts to deliver", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of delivery (CD or Release)", Mandatory = $false)]
    [ValidateSet('CD','Release')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "Types of artifacts to deliver (Apps,Dependencies,TestApps)", Mandatory = $false)]
    [string] $atypes = "Apps,Dependencies,TestApps",
    [Parameter(HelpMessage = "Promote AppSource App to Go Live? (Y/N)", Mandatory = $false)]
    [bool] $goLive
)

$telemetryScope = $null

function EnsureAzStorageModule() {
    if (get-command New-AzStorageContext -ErrorAction SilentlyContinue) {
        Write-Host "Using Az.Storage PowerShell module"
    }
    else {
        $azureStorageModule = Get-Module -name 'Azure.Storage' -ListAvailable | Select-Object -First 1
        if ($azureStorageModule) {
            Write-Host "Azure.Storage Module is available in version $($azureStorageModule.Version)"
            Write-Host "Using Azure.Storage version $($azureStorageModule.Version)"
            Import-Module  'Azure.Storage' -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
            Set-Alias -Name New-AzStorageContext -Value New-AzureStorageContext -Scope Script
            Set-Alias -Name Get-AzStorageContainer -Value Get-AzureStorageContainer -Scope Script
            Set-Alias -Name Set-AzStorageBlobContent -Value Set-AzureStorageBlobContent -Scope Script
        }
        else {
            Write-Host "Installing and importing Az.Storage."
            Install-Module 'Az.Storage' -Force
            Import-Module  'Az.Storage' -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
        }
    }
}

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "../TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0081' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')

    if ($projects -eq '') { $projects = "*" }
    if ($projects.StartsWith('[')) {
        $projects = ($projects | ConvertFrom-Json) -join ","
    }

    $artifacts = $artifacts.Replace('/',([System.IO.Path]::DirectorySeparatorChar)).Replace('\',([System.IO.Path]::DirectorySeparatorChar))

    $baseFolder = $ENV:GITHUB_WORKSPACE
    $settings = ReadSettings -baseFolder $baseFolder
    if ($settings.projects) {
        $projectList = $settings.projects | Where-Object { $_ -like $projects }
    }
    else {
        $projectList = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })
        if (Test-Path (Join-Path $baseFolder ".AL-Go") -PathType Container) {
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
    Write-Host "Artifacts $artifacts"
    Write-Host "Projects:"
    $projectList | Out-Host

    $secrets = $env:Secrets | ConvertFrom-Json
    foreach($thisProject in $projectList) {
        # $project should be the project part of the artifact name generated from the build
        if ($thisProject -and ($thisProject -ne '.')) {
            $project = $thisProject.Replace('\','_').Replace('/','_')
        }
        else {
            $project = $settings.repoName
        }
        # projectName is the project name stripped for special characters
        $projectName = $project -replace "[^a-z0-9]", "-"
        Write-Host "Project '$project'"
        $artifactsFolder = Join-Path $baseFolder ".artifacts"
        $artifactsFolderCreated = $false

        if ($artifacts -eq '.artifacts') {
            # Base folder is set
        }
        elseif ($artifacts -like "$($baseFolder)*") {
            $artifactsFolder = $artifacts
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
            New-Item $artifactsFolder -ItemType Directory | Out-Null
            $artifactsFolderCreated = $true
            $artifactFile = DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Apps"
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
            New-Item $artifactsFolder -ItemType Directory | Out-Null
            $artifactsFolderCreated = $true
            $atypes.Split(',') | ForEach-Object {
                $atype = $_
                $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $atype -projects $project -Version $artifacts -branch $refname
                if ($allArtifacts) {
                    $allArtifacts | ForEach-Object {
                        $artifactFile = DownloadArtifact -token $token -artifact $_ -path $artifactsFolder
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

        Write-Host "Artifacts:"
        Get-ChildItem -Path $artifactsFolder | ForEach-Object {
            Write-Host "- $($_.Name)"
        }

        # Check if there is a custom script to run for the delivery target
        $customScript = Join-Path $baseFolder ".github/DeliverTo$deliveryTarget.ps1"

        if (Test-Path $customScript -PathType Leaf) {
            Write-Host "Found custom script $customScript for delivery target $deliveryTarget"

            $projectSettings = ReadSettings -baseFolder $baseFolder -project $thisProject
            $projectSettings = AnalyzeRepo -settings $projectSettings -baseFolder $baseFolder -project $thisProject -doNotCheckArtifactSetting -doNotIssueWarnings
            $parameters = @{
                "Project" = $thisProject
                "ProjectName" = $projectName
                "type" = $type
                "Context" = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($deliveryTarget)Context"))
                "RepoSettings" = $settings
                "ProjectSettings" = $projectSettings
            }
            #Calculate the folders per artifact type

            #Calculate the folders per artifact type
            'Apps', 'TestApps', 'Dependencies' | ForEach-Object {
                $artifactType = $_
                $singleArtifactFilter = "$project-$refname-$artifactType-*.*.*.*";

                # Get the folder holding the artifacts from the standard build
                $artifactFolder =  @(Get-ChildItem -Path (Join-Path $artifactsFolder $singleArtifactFilter) -Directory)

                # Verify that there is an apps folder
                if ($artifactFolder.Count -eq 0 -and $artifactType -eq "Apps") {
                    throw "Internal error - unable to locate apps folder"
                }

                # Verify that there is only at most one artifact folder for the standard build
                if ($artifactFolder.Count -gt 1) {
                    $artifactFolder | Out-Host
                    throw "Internal error - multiple $artifactType folders located"
                }

                # Add the artifact folder to the parameters
                if ($artifactFolder.Count -ne 0) {
                    $parameters[$artifactType.ToLowerInvariant() + "Folder"] = $artifactFolder[0].FullName
                }

                # Get the folders holding the artifacts from all build modes
                $multipleArtifactFilter = "$project-$refname-*$artifactType-*.*.*.*";
                $artifactFolders = @(Get-ChildItem -Path (Join-Path $artifactsFolder $multipleArtifactFilter) -Directory)
                if ($artifactFolders.Count -gt 0) {
                    $parameters[$artifactType.ToLowerInvariant() + "Folders"] = $artifactFolders.FullName
                }
            }

            Write-Host "Calling custom script: $customScript"
            . $customScript -parameters $parameters
        }
        elseif ($deliveryTarget -eq "GitHubPackages") {
            $githubPackagesCredential = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.githubPackagesContext)) | ConvertFrom-Json
            'Apps' | ForEach-Object {
                $folder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($_)-*.*.*.*") | Where-Object { $_.PSIsContainer })
                if ($folder.Count -gt 1) {
                    $folder | Out-Host
                    throw "Internal error - multiple $_ folders located"
                }
                elseif ($folder.Count -eq 1) {
                    Get-Item -Path (Join-Path $folder[0] "*.app") | ForEach-Object {
                        $parameters = @{
                            "gitHubRepository" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
                            "includeNuGetDependencies" = $true
                            "dependencyIdTemplate" = "AL-Go-{id}"
                            "packageId" = "AL-Go-{id}"
                        }
                        $parameters.appFiles = $_.FullName
                        $package = New-BcNuGetPackage @parameters
                        Push-BcNuGetPackage -nuGetServerUrl $gitHubPackagesCredential.serverUrl -nuGetToken $gitHubPackagesCredential.token -bcNuGetPackage $package
                    }
                }
            }
        }
        elseif ($deliveryTarget -eq "NuGet") {
            try {
                $nuGetAccount = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.nuGetContext)) | ConvertFrom-Json | ConvertTo-HashTable
                $nuGetServerUrl = $nuGetAccount.ServerUrl
                $nuGetToken = $nuGetAccount.Token
                Write-Host "NuGetContext secret OK"
            }
            catch {
                throw "NuGetContext secret is malformed. Needs to be formatted as Json, containing serverUrl and token as a minimum."
            }
            $appsfolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-Apps-*.*.*.*") | Where-Object { $_.PSIsContainer })
            if ($appsFolder.Count -eq 0) {
                throw "Internal error - unable to locate apps folder"
            }
            elseif ($appsFolder.Count -gt 1) {
                $appsFolder | Out-Host
                throw "Internal error - multiple apps folders located"
            }
            $testAppsFolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-TestApps-*.*.*.*") | Where-Object { $_.PSIsContainer })
            if ($testAppsFolder.Count -gt 1) {
                $testAppsFolder | Out-Host
                throw "Internal error - multiple testApps folders located"
            }
            $dependenciesFolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-Dependencies-*.*.*.*") | Where-Object { $_.PSIsContainer })
            if ($dependenciesFolder.Count -gt 1) {
                $dependenciesFolder | Out-Host
                throw "Internal error - multiple dependencies folders located"
            }

            $parameters = @{
                "gitHubRepository" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
            }
            $parameters.appFiles = @(Get-Item -Path (Join-Path $appsFolder[0] "*.app") | ForEach-Object { $_.FullName })
            if ($testAppsFolder.Count -gt 0) {
                $parameters.testAppFiles = @(Get-Item -Path (Join-Path $testAppsFolder[0] "*.app") | ForEach-Object { $_.FullName })
            }
            if ($dependenciesFolder.Count -gt 0) {
                $parameters.dependencyAppFiles = @(Get-Item -Path (Join-Path $dependenciesFolder[0] "*.app") | ForEach-Object { $_.FullName })
            }
            if ($nuGetAccount.Keys -contains 'PackageName') {
                $parameters.packageId = $nuGetAccount.PackageName.replace('{project}',$projectName).replace('{owner}',$ENV:GITHUB_REPOSITORY_OWNER).replace('{repo}',$settings.repoName)
            }
            else {
                if ($thisProject -and ($thisProject -eq '.')) {
                    $parameters.packageId = "$($ENV:GITHUB_REPOSITORY_OWNER)-$($settings.repoName)"
                }
                else {
                    $parameters.packageId = "$($ENV:GITHUB_REPOSITORY_OWNER)-$($settings.repoName)-$ProjectName"
                }
            }
            if ($type -eq 'CD') {
                $parameters.packageId += "-preview"
            }
            $parameters.packageVersion = [System.Version]$appsFolder[0].Name.SubString($appsFolder[0].Name.IndexOf("-Apps-")+6)
            if ($nuGetAccount.Keys -contains 'PackageTitle') {
                $parameters.packageTitle = $nuGetAccount.PackageTitle
            }
            else {
                 $parameters.packageTitle = $parameters.packageId
            }
            if ($nuGetAccount.Keys -contains 'PackageDescription') {
                $parameters.packageDescription = $nuGetAccount.PackageDescription
            }
            else {
                $parameters.packageDescription = $parameters.packageTitle
            }
            if ($nuGetAccount.Keys -contains 'PackageAuthors') {
                $parameters.packageAuthors = $nuGetAccount.PackageAuthors
            }
            else {
                $parameters.packageAuthors = $actor
            }
            $package = New-BcNuGetPackage @parameters
            Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
        }
        elseif ($deliveryTarget -eq "Storage") {
            EnsureAzStorageModule
            try {
                $storageAccount = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.storageContext)) | ConvertFrom-Json | ConvertTo-HashTable
                # Check that containerName and blobName are present
                $storageAccount.containerName | Out-Null
                $storageAccount.blobName | Out-Null
            }
            catch {
                throw "StorageContext secret is malformed. Needs to be formatted as Json, containing StorageAccountName, containerName, blobName and sastoken or storageAccountKey.`nError was: $($_.Exception.Message)"
            }
            if ($storageAccount.Keys -contains 'sastoken') {
                try {
                    $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -SasToken $storageAccount.sastoken
                }
                catch {
                    throw "Unable to create AzStorageContext based on StorageAccountName and sastoken.`nError was: $($_.Exception.Message)"
                }
            }
            else {
                try {
                    $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageAccount.StorageAccountKey
                }
                catch {
                    throw "Unable to create AzStorageContext based on StorageAccountName and StorageAccountKey.`nError was: $($_.Exception.Message)"
                }
            }

            $storageContainerName =  $storageAccount.ContainerName.ToLowerInvariant().replace('{project}',$projectName).replace('{branch}',$refname).ToLowerInvariant()
            $storageBlobName = $storageAccount.BlobName.ToLowerInvariant()
            Write-Host "Storage Container Name is $storageContainerName"
            Write-Host "Storage Blob Name is $storageBlobName"
            Get-AzStorageContainer -Context $azStorageContext -name $storageContainerName | Out-Null
            Write-Host "Delivering to $storageContainerName in $($storageAccount.StorageAccountName)"
            $atypes.Split(',') | ForEach-Object {
                $atype = $_
                Write-Host "Looking for: $project-$refname-$atype-*.*.*.*"
                $artfolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$atype-*.*.*.*") | Where-Object { $_.PSIsContainer })
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
                    $version = $artfolder.SubString($artfolder.IndexOf("-$refname-$atype-")+"-$refname-$atype-".Length)
                    Write-Host $artfolder
                    $versions = @("$version-preview","preview")
                    if ($type -eq "Release") {
                        $versions += @($version,"latest")
                    }
                    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::newguid().ToString()).zip"
                    try {
                        Write-Host "Compressing"
                        Compress-Archive -Path (Join-Path $artfolder '*') -DestinationPath $tempFile -Force
                        $versions | ForEach-Object {
                            $version = $_
                            $blob = $storageBlobName.replace('{project}',$projectName).replace('{branch}',$refname).replace('{version}',$version).replace('{type}',$atype).ToLowerInvariant()
                            Write-Host "Delivering $blob"
                            Set-AzStorageBlobContent -Context $azStorageContext -Container $storageContainerName -File $tempFile -blob $blob -Force | Out-Null
                        }
                    }
                    finally {
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        elseif ($deliveryTarget -eq "AppSource") {
            $projectSettings = ReadSettings -baseFolder $baseFolder -project $thisProject
            $projectSettings = AnalyzeRepo -settings $projectSettings -baseFolder $baseFolder -project $thisProject -doNotCheckArtifactSetting -doNotIssueWarnings
            # if type is Release, we only get here with the projects that needs to be delivered to AppSource
            # if type is CD, we get here for all projects, but should only deliver to AppSource if AppSourceContinuousDelivery is set to true
            if ($type -eq 'Release' -or ($projectSettings.Keys -contains 'AppSourceContinuousDelivery' -and $projectSettings.AppSourceContinuousDelivery)) {
                EnsureAzStorageModule
                $appSourceContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.appSourceContext)) | ConvertFrom-Json | ConvertTo-HashTable
                if (!$appSourceContext) {
                    throw "appSourceContext secret is missing"
                }
                $authContext = New-BcAuthContext @appSourceContext

                if ($projectSettings.Keys -contains "AppSourceMainAppFolder") {
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
                if ($projectSettings.Keys -notcontains 'AppSourceProductId') {
                    throw "AppSourceProductId needs to be specified in $thisProject/.AL-Go/settings.json in order to deliver to AppSource"
                }
                Write-Host "AppSource MainAppFolder $AppSourceMainAppFolder"

                $mainAppJson = Get-Content -Path (Join-Path $baseFolder "$thisProject/$AppSourceMainAppFolder/app.json") -Encoding UTF8 | ConvertFrom-Json
                $mainAppFileName = ("$($mainAppJson.Publisher)_$($mainAppJson.Name)_".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '') + "*.*.*.*.app"
                $artfolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-Apps-*.*.*.*") | Where-Object { $_.PSIsContainer })
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
        else {
            throw "Internal error, no handler for $deliveryTarget"
        }

        if ($artifactsFolderCreated) {
            Remove-Item $artifactsFolder -Recurse -Force
        }
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
