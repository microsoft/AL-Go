Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Projects to deliver (default is all)", Mandatory = $false)]
    [string] $projects = "*",
    [Parameter(HelpMessage = "Delivery target (AppSource or Storage)", Mandatory = $true)]
    [string] $deliveryTarget,
    [Parameter(HelpMessage = "The artifacts to deliver or a folder in which the artifacts have been downloaded", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of delivery (CD or Release)", Mandatory = $false)]
    [ValidateSet('CD', 'Release')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "Types of artifacts to deliver (Apps,Dependencies,TestApps)", Mandatory = $false)]
    [string] $atypes = "Apps,Dependencies,TestApps",
    [Parameter(HelpMessage = "Promote AppSource App to Go Live?", Mandatory = $false)]
    [bool] $goLive
)

function ConnectAzStorageAccount {
    Param(
        [PSCustomObject] $storageAccountCredentials
    )

    $azStorageContext = $null
    if ($storageAccountCredentials.PSObject.Properties.Name -eq 'sastoken') {
        try {
            Write-Host "Creating AzStorageContext based on StorageAccountName and sastoken"
            $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccountCredentials.StorageAccountName -SasToken $storageAccountCredentials.sastoken
        }
        catch {
            throw "Unable to create AzStorageContext based on StorageAccountName and sastoken. Error was: $($_.Exception.Message)"
        }
    }
    elseif ($storageAccountCredentials.PSObject.Properties.Name -eq 'StorageAccountKey') {
        try {
            Write-Host "Creating AzStorageContext based on StorageAccountName and StorageAccountKey"
            $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccountCredentials.StorageAccountName -StorageAccountKey $storageAccountCredentials.StorageAccountKey
        }
        catch {
            throw "Unable to create AzStorageContext based on StorageAccountName and StorageAccountKey. Error was: $($_.Exception.Message)"
        }
    }
    elseif (($storageAccountCredentials.PSObject.Properties.Name -eq 'clientID') -and ($storageAccountCredentials.PSObject.Properties.Name -eq 'tenantID')) {
        try {
            InstallAzModuleIfNeeded -name 'Az.Accounts'
            ConnectAz -azureCredentials $storageAccountCredentials
            Write-Host "Creating AzStorageContext based on StorageAccountName and managed identity/app registration"
            $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccountCredentials.StorageAccountName -UseConnectedAccount
        }
        catch {
            throw "Unable to create AzStorageContext based on StorageAccountName and managed identity. Error was: $($_.Exception.Message)"
        }
    }
    else {
        throw "Insufficient information in StorageContext secret. See https://aka.ms/algosettings#storagecontext for details"
    }
    return $azStorageContext
}

. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$refname = "$ENV:GITHUB_REF_NAME".Replace('/', '_')

$artifacts = $artifacts.Replace('/', ([System.IO.Path]::DirectorySeparatorChar)).Replace('\', ([System.IO.Path]::DirectorySeparatorChar))

$baseFolder = $ENV:GITHUB_WORKSPACE
$settings = ReadSettings -baseFolder $baseFolder
$projectList = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $settings.projects -selectProjects $projects)
if ($deliveryTarget -eq "AppSource") {
    $atypes = "Apps,Dependencies"
}
Write-Host "Artifacts $artifacts"
Write-Host "Projects:"
$projectList | Out-Host

$secrets = $env:Secrets | ConvertFrom-Json
foreach ($thisProject in $projectList) {
    # $project should be the project part of the artifact name generated from the build
    if ($thisProject -and ($thisProject -ne '.')) {
        $project = $thisProject.Replace('\', '_').Replace('/', '_')
    }
    else {
        $project = $settings.repoName
    }
    # projectName is the project name stripped for special characters
    $projectName = $project -replace "[^a-z0-9]", "-"
    Write-Host "ProjectName '$projectName'"

    if ($artifacts -like "$($baseFolder)*") {
        $artifactsFolder = $artifacts
    }
    else {
        $artifactsFolder = Join-Path $baseFolder ".artifacts"
        $artifactsFolderCreated = $false
        if (!(Test-Path $artifactsFolder)) {
            New-Item $artifactsFolder -ItemType Directory | Out-Null
            $artifactsFolderCreated = $true
        }
        if ($artifacts -eq '.artifacts') {
            # Artifacts from this build have been downloaded
        }
        elseif ($artifacts -eq "current" -or $artifacts -eq "prerelease" -or $artifacts -eq "draft") {
            # project is the project name as used in release asset names
            $project = [Uri]::EscapeDataString($project.Replace(' ', '.')).Replace('%', '')

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
            foreach ($mask in $atypes.Split(',')) {
                $artifactFile = DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask $mask
                Write-Host "'$artifactFile'"
                if (!$artifactFile -or !(Test-Path $artifactFile)) {
                    if ($mask -eq 'Apps') {
                        throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
                    }
                }
                else {
                    if ($artifactFile -notlike '*.zip') {
                        throw "Downloaded artifact is not a .zip file"
                    }
                    Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0, $artifactFile.Length - 4))
                    Remove-Item $artifactFile -Force
                }
            }
        }
        else {
            $atypes.Split(',') | ForEach-Object {
                $atype = $_
                $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask $atype -projects $project -version $artifacts -branch $ENV:GITHUB_REF_NAME
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
                        Expand-Archive -Path $artifactFile -DestinationPath ($artifactFile.SubString(0, $artifactFile.Length - 4))
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
    }

    Write-Host "Project '$project'"
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
            "Project"         = $thisProject
            "ProjectName"     = $projectName
            "type"            = $type
            "Context"         = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($deliveryTarget)Context"))
            "RepoSettings"    = $settings
            "ProjectSettings" = $projectSettings
        }

        #Calculate the folders per artifact type
        'Apps', 'TestApps', 'Dependencies' | ForEach-Object {
            $artifactType = $_
            $singleArtifactFilter = "$project-$refname-$artifactType-*.*.*.*";

            # Get the folder holding the artifacts from the standard build
            $artifactFolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder $singleArtifactFilter) -Directory)

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
    elseif ($deliveryTarget -eq 'GitHubPackages' -or $deliveryTarget -eq 'NuGet') {
        $preReleaseTag = ''
        try {
            $nuGetAccount = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($deliveryTarget)Context")) | ConvertFrom-Json | ConvertTo-HashTable
            if ($deliveryTarget -eq 'NuGet' -and $type -eq 'CD') {
                # When doing continuous delivery to NuGet, we always use the preview tag
                # When doing a release, we do not add a preview tag
                $preReleaseTag = 'preview'
            }
            $nuGetServerUrl = $nuGetAccount.ServerUrl
            Write-Host $nuGetAccount.ServerUrl
            $nuGetToken = $nuGetAccount.Token
            Write-Host "$($deliveryTarget)Context secret OK"
        }
        catch {
            throw "$($deliveryTarget)Context secret is malformed. Needs to be formatted as Json, containing serverUrl and token as a minimum."
        }
        'Apps','TestApps' | ForEach-Object {
            $folder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($_)-*.*.*.*") | Where-Object { $_.PSIsContainer })
            if ($folder.Count -gt 1) {
                $folder | Out-Host
                throw "Internal error - multiple $_ folders located"
            }
            elseif ($folder.Count -eq 1) {
                Get-Item -Path (Join-Path $folder[0] "*.app") | ForEach-Object {
                    $parameters = @{
                        "gitHubRepository" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
                        "preReleaseTag"    = $preReleaseTag
                        "appFile"          = $_.FullName
                    }
                    $package = New-BcNuGetPackage @parameters
                    Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
                }
            }
        }
    }
    elseif ($deliveryTarget -eq "Storage") {
        InstallAzModuleIfNeeded -name 'Az.Storage'
        try {
            $storageAccountCredentials = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.storageContext)) | ConvertFrom-Json
            $storageAccountCredentials.StorageAccountName | Out-Null
            $storageContainerName = $storageAccountCredentials.ContainerName.ToLowerInvariant().replace('{project}', $projectName).replace('{branch}', $refname).ToLowerInvariant()
            $storageBlobName = $storageAccountCredentials.BlobName.ToLowerInvariant()
        }
        catch {
            throw "StorageContext secret is malformed. Needs to be formatted as Json, containing StorageAccountName, containerName, blobName.`nError was: $($_.Exception.Message)"
        }
        $azStorageContext = ConnectAzStorageAccount -storageAccountCredentials $storageAccountCredentials
        Write-Host "Storage Container Name is $storageContainerName"
        Write-Host "Storage Blob Name is $storageBlobName"

        $containerExists = $true
        try {
            Get-AzStorageContainer -Context $azStorageContext -name $storageContainerName | Out-Null
        }
        catch {
            $containerExists = $false
        }

        if (-not $containerExists -and $settings.Contains('DeliverToStorage') -and $settings."DeliverToStorage".Contains('CreateContainerIfNotExist') -and $settings."DeliverToStorage"."CreateContainerIfNotExist" -eq $true) {
            Write-Host "Container $storageContainerName does not exist. Creating..."
            New-AzStorageContainer -Context $azStorageContext -Name $storageContainerName | Out-Null
        }

        Write-Host "Delivering to $storageContainerName in $($storageAccountCredentials.StorageAccountName)"
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
                $version = $artfolder.SubString($artfolder.IndexOf("-$refname-$atype-") + "-$refname-$atype-".Length)
                Write-Host $artfolder
                $versions = @("$version-preview", "preview")
                if ($type -eq "Release") {
                    $versions += @($version, "latest")
                }
                $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::newguid().ToString()).zip"
                try {
                    Write-Host "Compressing"
                    Compress-Archive -Path (Join-Path $artfolder '*') -DestinationPath $tempFile -Force
                    $versions | ForEach-Object {
                        $version = $_
                        $blob = $storageBlobName.replace('{project}', $projectName).replace('{branch}', $refname).replace('{version}', $version).replace('{type}', $atype).ToLowerInvariant()
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
        # Use old settings and issue warnings
        'continuousDelivery', 'mainAppFolder', 'productId' | ForEach-Object {
            if ($projectSettings.Keys -contains "AppSource$_") {
                OutputWarning "Using AppSource$_ in $thisProject/.AL-Go/settings.json is deprecated. Use deliverToAppSource.$_ instead. If both values are defined, the value in AppSource$_ is used (even if it is deprecated)."
                $projectSettings.deliverToAppSource."$_" = $projectSettings."AppSource$_"
            }
        }
        # if type is Release, we only get here with the projects that needs to be delivered to AppSource
        # if type is CD, we get here for all projects, but should only deliver to AppSource if AppSourceContinuousDelivery is set to true
        if ($type -eq 'Release' -or $projectSettings.deliverToAppSource.continuousDelivery) {
            # AppSource submission requires the Az.Storage module
            InstallAzModuleIfNeeded -name 'Az.Storage'
            $appSourceContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.appSourceContext)) | ConvertFrom-Json | ConvertTo-HashTable
            if (!$appSourceContext) {
                throw "appSourceContext secret is missing"
            }
            $authContext = New-BcAuthContext @appSourceContext

            if ($projectSettings.deliverToAppSource.MainAppFolder) {
                $AppSourceMainAppFolder = $projectSettings.deliverToAppSource.MainAppFolder
            }
            else {
                try {
                    $AppSourceMainAppFolder = $projectSettings.appFolders[0]
                }
                catch {
                    throw "Unable to determine main App folder"
                }
            }
            if (!$projectSettings.deliverToAppSource.ProductId) {
                throw "deliverToAppSource.ProductId needs to be specified in $thisProject/.AL-Go/settings.json in order to deliver to AppSource"
            }
            Write-Host "AppSource MainAppFolder $AppSourceMainAppFolder"

            $mainAppJson = Get-Content -Path (Join-Path $baseFolder "$thisProject/$AppSourceMainAppFolder/app.json") -Encoding UTF8 | ConvertFrom-Json
            $mainAppFileName = ("$($mainAppJson.Publisher)_$($mainAppJson.Name)_".Split([System.IO.Path]::GetInvalidFileNameChars()) -join '') + "*.*.*.*.app"
            $artfolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-Apps-*.*.*.*") | Where-Object { $_.PSIsContainer })
            if ($artFolder.Count -eq 0) {
                throw "Internal error - unable to locate apps folder"
            }
            if ($artFolder.Count -gt 1) {
                $artFolder | Out-Host
                throw "Internal error - multiple apps folders located"
            }
            $artfolder = $artfolder[0].FullName
            $appFile = Get-ChildItem -path $artFolder | Where-Object { $_.name -like $mainAppFileName } | ForEach-Object { $_.FullName }
            $libraryAppFiles = @(Get-ChildItem -path $artFolder | Where-Object { $_.name -notlike $mainAppFileName } | ForEach-Object { $_.FullName })

            $appSourceIncludeDependencies = $projectSettings.deliverToAppSource.includeDependencies
            if ($appSourceIncludeDependencies -and $appSourceIncludeDependencies.count -gt 0) {
                $depfolder = @(Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-Dependencies-*.*.*.*") | Where-Object { $_.PSIsContainer })
                if ($depFolder.Count -eq 0) {
                    throw "Unable to locate dependencies. You need to set generateDependencyArtifact to true in $thisProject/.AL-Go/settings.json in order to deliver dependencies to AppSource"
                }
                if ($depFolder.Count -gt 1) {
                    $depFolder | Out-Host
                    throw "Internal error - multiple dependencies folders located"
                }
                $depfolder = $depfolder[0].FullName
                $libraryAppFiles += @(Get-ChildItem -path $depFolder | Where-Object {
                    $name = $_.name
                    $appSourceIncludeDependencies | Where-Object { $name -like $_ }
                } | ForEach-Object { $_.FullName })
            }

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
            $status = New-AppSourceSubmission -authContext $authContext -productId $projectSettings.deliverToAppSource.productId -appFile $appFile -libraryAppFiles $libraryAppFiles -doNotWait -autoPromote:$goLive -Force
            if ($goLive) {
                if ($status.state -ne 'Published' -or ($status.substate -ne 'ReadyToPublish' -and $status.substate -ne 'InStore')) {
                    throw "AppSource submission failed. Status is $($status.state)/$($status.substate)"
                }
            }
        }
    }
    else {
        throw "Internal error, no handler for $deliveryTarget"
    }

    if ($artifactsFolderCreated) {
        Remove-Item $artifactsFolder -Recurse -Force
    }
}
