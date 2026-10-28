. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
        Get the head ref from a PR
    .PARAMETER repository
        Repository to search in
    .PARAMETER prId
        The PR Id
    .PARAMETER token
        The GitHub token running the action
#>
function GetHeadRefFromPRId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $prId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $pullsURI = "https://api.github.com/repos/$repository/pulls/$prId"
    Write-Host "- $pullsURI"
    $pr = (InvokeWebRequest -Headers $headers -Uri $pullsURI).Content | ConvertFrom-Json

    return $pr.head.ref
}

<#
    .SYNOPSIS
        Get apps and dependencies from artifacts
    .PARAMETER token
        The GitHub token running the action
    .PARAMETER artifactsFolder
        The folder where artifacts are stored
    .PARAMETER deploymentSettings
        Deployment settings for the action
    .PARAMETER artifactsVersion
        Version of the artifacts to use (optional) - This is only used for PR deployments and should take the form of PR_X
#>
function GetAppsAndDependenciesFromArtifacts {
    Param(
        [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $artifactsFolder,
        [Parameter(Mandatory = $true)]
        [hashtable] $deploymentSettings,
        [Parameter(Mandatory = $false)]
        [string] $artifactsVersion = ''
    )
    OutputDebugFunctionCall
    OutputGroupStart -Message "GetAppsAndDependenciesFromArtifacts"
    $apps = @()
    $dependencies = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
    $TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"

    # Determine buildMode prefix for artifact names based on settings
    $buildModePrefix = 'default'
    if ($deploymentSettings.Keys -contains "buildMode") {
        $buildModePrefix = $deploymentSettings.buildMode
    }

    # If buildMode is not defined or is 'default', set it to empty string
    if ($null -eq $buildModePrefix -or $buildModePrefix -eq 'default') {
        $buildModePrefix = ''
    }

    if (Test-Path $artifactsFolder -PathType Container) {
        $deploymentSettings.Projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_').Replace('/','_')
            $artifactVersionFilter = '*.*.*.*'
            $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
            # Artifacts from PRs are named differently - project-ref-Apps-PRx-date
            if ($artifactsVersion -like "PR_*") {
                $prId = $artifactsVersion.SubString(3)
                $intId = 0
                if (!([Int]::TryParse($prId, [ref] $intId))) {
                    OutputGroupEnd
                    throw "Invalid PR id: $prId"
                }
                $artifactVersionFilter = "PR$prId-*"
                $refname = (GetHeadRefFromPRId -repository $ENV:GITHUB_REPOSITORY -prId $prId -token $token).Replace('/','_')
            }
            Write-Host "project '$project'"

            $allApps = @()
            OutputDebug -message "projectApps filter: $project-$refname-$($buildModePrefix)Apps-$artifactVersionFilter"
            $projectApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildModePrefix)Apps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            $projectTestApps = @()
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment) {
                Write-Host "Including test apps for deployment"
                OutputDebug -message "projectTestApps filter: $project-$refname-$($buildModePrefix)TestApps-$artifactVersionFilter"
                $projectTestApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildModePrefix)TestApps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            }
            if ($deploymentSettings.excludeAppIds) {
                Write-Host "Excluding apps with ids $($deploymentSettings.excludeAppIds) from deployment"
            }
            if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
                OutputDebug -message "projectDependencies filter: $project-$refname-$($buildModePrefix)Dependencies-$artifactVersionFilter/*.app"
                $dependencies += @((Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($buildModePrefix)Dependencies-$artifactVersionFilter/*.app")) | ForEach-Object { $_.FullName } )
            }
            if (!($projectApps)) {
                if ($project -ne '*') {
                    OutputGroupEnd
                    throw "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildModePrefix)Apps-<version>."
                }
            }
            else {
                $allApps += $projectApps
            }
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment -and !($projectTestApps)) {
                if ($project -ne '*') {
                    OutputWarning -message "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildModePrefix)TestApps-<version>."
                }
            }
            else {
                $allApps += $projectTestApps
            }
            # Go through all .app files and exclude any with ids in the excludeAppIds list
            # Also exclude apps with direct dependencies on Tests-TestLibraries
            if ($allApps) {
                foreach($folder in $allApps) {
                    foreach($app in (Get-ChildItem -Path $folder -Filter "*.app")) {
                        Write-Host "Processing app: $($app.Name)"
                        $appJson = Get-AppJsonFromAppFile -appFile $app.FullName
                        if ($appJson.id -notin $deploymentSettings.excludeAppIds) {
                            # If app should be included, verify that it does not depend on Tests-TestLibraries
                            $unknownDependenciesForApp = @()
                            Sort-AppFilesByDependencies -appFiles @($app.FullName) -unknownDependencies ([ref]$unknownDependenciesForApp) -WarningAction SilentlyContinue | Out-Null
                            $unknownDependenciesForApp | ForEach-Object {
                                if ($_.Split(':')[0] -eq $TestsTestLibrariesAppId) {
                                    OutputWarning -message "Test-TestLibraries can't be installed - skipping app $($app.Name)"
                                    continue
                                }
                            }

                            $apps += $app.FullName
                            Write-Host "App $($app.Name) with id $($appJson.id) included in deployment"
                        }
                        else {
                            Write-Host "App $($app.Name) with id $($appJson.id) excluded from deployment"
                        }
                    }
                }
            }
        }
    }
    else {
        OutputGroupEnd
        throw "Artifact $artifactsFolder was not found. Make sure that the artifact files exist and files are not corrupted."
    }
    OutputGroupEnd
    return $apps, $dependencies
}

<#
    .SYNOPSIS
        Check if an app needs to be installed or upgraded based on the app.json and the installed version.
    .PARAMETER appJson
        The app.json object of the app to check.
    .PARAMETER installedApp
        The installed app object to compare against.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function CheckIfAppNeedsInstallOrUpgrade {
    Param(
        [PSCustomObject] $appJson,
        $installedApp,
        [string] $installMode
    )
    OutputDebugFunctionCall

    $needsInstall = $false
    $needsUpgrade = $false
    if ($installedApp) {
        $dependencyVersion = [version]::new($appJson.Version)
        $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)
        if ($dependencyVersion -gt $installedVersion) {
            $msg = "Dependency app $($appJson.name) is already installed in version $installedVersion, which is lower than $dependencyVersion."
            if ($installMode -eq 'upgrade') {
                Write-Host "$msg Needs upgrade."
                $needsUpgrade = $true
            }
            else {
                OutputWarning -message "$msg Set DependencyInstallMode to 'upgrade' or 'forceUpgrade' to upgrade dependencies."
            }
        }
        elseif ($dependencyVersion -lt $installedVersion) {
            Write-Host "Dependency app $($appJson.name) is already installed in version $installedVersion, which is higher than $dependencyVersion, used in app.json."
        }
        else {
            Write-Host "Dependency app $($appJson.name) is already installed in version $installedVersion."
        }
    }
    else {
        Write-Host "Dependency app $($appJson.name) is not installed."
        $needsInstall = ($installMode -ne 'ignore')
    }
    return $needsInstall, $needsUpgrade
}

<#
    .SYNOPSIS
        Check installed apps against the provided app files and emit warnings if the installed version is higher than the version in the app file.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to check installed apps in.
    .PARAMETER appFiles
        The list of app files to check against installed apps.
#>
function CheckInstalledApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $appFiles
    )
    OutputDebugFunctionCall

    $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
    foreach($appFile in $appFiles) {
        # Get AppJson (works for full .app files, symbol files and also runtime packages)
        $appJson = Get-AppJsonFromAppFile -appFile $appFile
        $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }

        # Check if the version of the installed app is lower than the version in the app file
        if ($installedApp) {
            $currentVersion = [version]::new($appJson.Version)
            $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)

            if ($currentVersion -lt $installedVersion) {
                OutputWarning -message "App $($appJson.name) is already installed in version $installedVersion, which is higher than $currentVersion, used in app.json. In order to install version $currentVersion, the higher version must be uninstalled first."
            }
        }
    }
}

<#
    .SYNOPSIS
        Resolve the target BC version from its installed Application extension.
    .PARAMETER extensions
        Extensions returned by the read-only environment API.
    .PARAMETER environment
        Target environment name, used in failure diagnostics.
#>
function GetPTEApplicationVersion {
    Param(
        [object[]] $extensions,
        [string] $environment
    )

    $applications = @($extensions | Where-Object { $_.displayName -eq 'Application' -and $_.isInstalled })
    $version = $null
    if ($applications.Count -eq 1) {
        $application = $applications[0] | ConvertTo-HashTable -recurse
        $parts = @('versionMajor', 'versionMinor', 'versionBuild', 'versionRevision' | ForEach-Object {
            if ($application.ContainsKey($_)) { [string]$application[$_] }
        })
        if ($parts.Count -eq 4 -and [version]::TryParse(($parts -join '.'), [ref]$version)) {
            return $version
        }
    }
    throw "Could not determine the Business Central version in environment $environment from a unique installed Application extension."
}

<#
    .SYNOPSIS
        Upload a PTE for immediate installation through Admin Center API v2.29.
    .DESCRIPTION
        Sends multipart bytes on PowerShell 5 and 7 and disposes HTTP content and streams.
        Upload errors are never retried because the service might already have accepted the package.
    .PARAMETER bcAuthContext
        Authentication context to renew before uploading.
    .PARAMETER uri
        Admin Center pteInstall URL for the target environment.
    .PARAMETER appFile
        App package to upload.
    .PARAMETER syncMode
        Admin Center schema sync mode, Add or ForceSync.
#>
function InvokePTEUpload {
    Param(
        [hashtable] $bcAuthContext,
        [string] $uri,
        [string] $appFile,
        [ValidateSet('Add', 'ForceSync')]
        [string] $syncMode
    )

    $authContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
    if (!$authContext -or !$authContext['AccessToken']) {
        throw "Authentication failed before PTE upload."
    }
    Write-Host "::add-mask::$($authContext.AccessToken)"
    $headers = @{ Authorization = "Bearer $($authContext.AccessToken)" }
    Add-Type -AssemblyName System.Net.Http
    $multipart = $null
    $fileStream = $null
    $fileContent = $null
    try {
        $multipart = [System.Net.Http.MultipartFormDataContent]::new()
        $fileStream = [System.IO.File]::OpenRead($appFile)
        $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $multipart.Add($fileContent, 'extensionFile', [System.IO.Path]::GetFileName($appFile))
        $fields = @{
            deploymentSchedule = 'Immediate'
            syncMode = $syncMode
            acceptIsvEula = 'true'
            installOrUpdateNeededDependencies = 'false'
        }
        foreach ($field in $fields.Keys) {
            $multipart.Add([System.Net.Http.StringContent]::new($fields[$field]), $field)
        }
        # Invoke-RestMethod supports a byte body on both Windows PowerShell and PowerShell Core.
        $bytes = $multipart.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bytes `
            -ContentType $multipart.Headers.ContentType.ToString() -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
    }
    catch {
        $details = $_.Exception.Message
        if ($_.ErrorDetails) { $details += " $($_.ErrorDetails.Message)" }
        throw "PTE upload failed for $([System.IO.Path]::GetFileName($appFile)): $details. The upload will not be replayed."
    }
    finally {
        if ($multipart) { $multipart.Dispose() }
        if ($fileContent) { $fileContent.Dispose() }
        if ($fileStream) { $fileStream.Dispose() }
    }
}

<#
    .SYNOPSIS
        Wait for the exact Admin Center PTE operation to complete successfully.
    .DESCRIPTION
        Polls only the returned app and operation IDs. An accepted or scheduled immediate install
        is not success. Only transient status-read errors are retried, never the upload.
    .PARAMETER bcAuthContext
        Authentication context to renew for each status request.
    .PARAMETER appsUri
        Admin Center apps URL for the target environment.
    .PARAMETER operation
        Upload response containing the operation id, appId and status.
    .PARAMETER appId
        Expected app ID from the package.
    .PARAMETER timeoutSeconds
        Maximum elapsed polling time. Defaults to 30 minutes.
    .PARAMETER maxStatusRequests
        Maximum number of status requests. Defaults to 360.
    .PARAMETER pollIntervalSeconds
        Delay between status requests. Defaults to five seconds.
#>
function WaitPTEOperation {
    Param(
        [hashtable] $bcAuthContext,
        [string] $appsUri,
        $operation,
        [string] $appId,
        [ValidateRange(1, 1800)]
        [int] $timeoutSeconds = 1800,
        [ValidateRange(1, 360)]
        [int] $maxStatusRequests = 360,
        [ValidateRange(0, 5)]
        [int] $pollIntervalSeconds = 5
    )

    $operation = $operation | ConvertTo-HashTable -recurse
    if ($operation -isnot [hashtable] -or !$operation['id'] -or $operation['appId'] -ne $appId) {
        throw "PTE upload returned missing or mismatched app/operation details for app $appId. The upload will not be replayed."
    }
    $operationId = [string]$operation['id']
    $operationUri = "$appsUri/$([Uri]::EscapeDataString($appId))/operations/$([Uri]::EscapeDataString($operationId))"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $transientErrors = 0
    $requests = 0
    while ($true) {
        if ($operation -isnot [hashtable] -or $operation['id'] -ne $operationId -or
            ($operation.ContainsKey('appId') -and $operation['appId'] -ne $appId)) {
            throw "Missing or mismatched PTE operation $operationId for app $appId."
        }
        $status = [string]$operation['status']
        Write-Host "PTE operation $operationId for app ${appId}: $status"
        switch ($status) {
            'succeeded' { return }
            'scheduled' {}
            'running' {}
            default {
                throw "PTE operation $operationId for app $appId did not succeed. Response: $($operation | ConvertTo-Json -Depth 20 -Compress)"
            }
        }
        if ($requests -ge $maxStatusRequests -or $timer.Elapsed.TotalSeconds -ge $timeoutSeconds) {
            break
        }
        Start-Sleep -Seconds $pollIntervalSeconds
        if ($timer.Elapsed.TotalSeconds -ge $timeoutSeconds) { break }
        # Renew outside the retry catch so authentication errors always fail immediately.
        $bcAuthContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        if (!$bcAuthContext -or !$bcAuthContext['AccessToken']) {
            throw "Authentication failed while reading PTE operation $operationId for app $appId."
        }
        Write-Host "::add-mask::$($bcAuthContext.AccessToken)"
        $headers = @{ Authorization = "Bearer $($bcAuthContext.AccessToken)" }
        $requests++
        try {
            $requestTimeout = [int][Math]::Max(1, [Math]::Min(30, [Math]::Ceiling($timeoutSeconds - $timer.Elapsed.TotalSeconds)))
            $operation = Invoke-RestMethod -Headers $headers -Method Get -Uri $operationUri `
                -UseBasicParsing -TimeoutSec $requestTimeout -ErrorAction Stop
            $operation = $operation | ConvertTo-HashTable -recurse
            $transientErrors = 0
        }
        catch {
            $statusCode = 0
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            $transient = $statusCode -in 408,429,500,502,503,504 -or
                (!$statusCode -and ($_.Exception -is [System.Net.WebException] -or
                    $_.Exception -is [System.Net.Http.HttpRequestException] -or $_.Exception -is [System.TimeoutException]))
            $details = $_.Exception.Message
            if ($_.ErrorDetails) { $details += " $($_.ErrorDetails.Message)" }
            if (!$transient -or ++$transientErrors -gt 5) {
                throw "Unable to read PTE operation $operationId for app ${appId}: $details"
            }
            OutputWarning -message "Transient error reading PTE operation ${operationId}: $details. Retrying the status request."
        }
    }
    throw "Timed out waiting for PTE operation $operationId for app $appId after $timeoutSeconds seconds or $maxStatusRequests status requests. The upload will not be replayed."
}

<#
    .SYNOPSIS
        Publish primary apps or PTE dependencies using the target BC version.
    .DESCRIPTION
        Below BC 29, delegates publishing to the released BcContainerHelper Automation implementation.
        On BC 29 and later, AL-Go installs packages immediately using Admin Center API v2.29 with
        no legacy fallback. Existing helper utilities expand packages, exclude runtime packages and
        order dependencies. Same or newer installed versions are skipped.
    .PARAMETER bcAuthContext
        Business Central authentication context.
    .PARAMETER environment
        Target Business Central environment name.
    .PARAMETER appFiles
        App packages or archives to publish.
    .PARAMETER schemaSyncMode
        Existing helper-compatible sync mode: Add or Force (mapped to ForceSync for Admin Center).
    .PARAMETER applicationFamily
        Admin Center application family. Defaults to BusinessCentral; not a workflow setting.
#>
function PublishPTEApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $appFiles,
        [ValidateSet('Add', 'Force')]
        [string] $schemaSyncMode = 'Add',
        [string] $applicationFamily = 'BusinessCentral'
    )

    $extensions = @(Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment)
    $applicationVersion = GetPTEApplicationVersion -extensions $extensions -environment $environment
    if ($applicationVersion -lt [version]'29.0.0.0') {
        Write-Host "Target BC $applicationVersion - publishing PTEs using BcContainerHelper Automation API"
        Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles -SchemaSyncMode $schemaSyncMode
        return
    }
    Write-Host "Target BC $applicationVersion - publishing PTEs using AL-Go Admin Center API v2.29"
    $appsUri = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/admin/v2.29/applications/$([Uri]::EscapeDataString($applicationFamily))/environments/$([Uri]::EscapeDataString($environment))/apps"
    $tempPath = NewTemporaryFolder
    try {
        $copiedApps = @(Copy-AppFilesToFolder -appFiles $appFiles -folder $tempPath)
        $sortedApps = @(Sort-AppFilesByDependencies -appFiles $copiedApps -excludeRuntimePackages)
        foreach ($appFile in $sortedApps) {
            $appJson = Get-AppJsonFromAppFile -appFile $appFile
            $appVersion = [version]$appJson.version
            $installedVersions = @($extensions | Where-Object { $_.id -eq $appJson.id -and $_.isInstalled } |
                ForEach-Object { [version]::new($_.versionMajor, $_.versionMinor, $_.versionBuild, $_.versionRevision) })
            if (@($installedVersions | Where-Object { $_ -ge $appVersion }).Count -gt 0) {
                Write-Host "App $($appJson.name) v$appVersion or newer is already installed"
                continue
            }
            $syncMode = if ($schemaSyncMode -eq 'Force') { 'ForceSync' } else { 'Add' }
            $operation = InvokePTEUpload -bcAuthContext $bcAuthContext -uri "$appsUri/pteInstall" -appFile $appFile -syncMode $syncMode
            WaitPTEOperation -bcAuthContext $bcAuthContext -appsUri $appsUri -operation $operation -appId $appJson.id
            $extensions += @{
                id = $appJson.id
                displayName = $appJson.name
                isInstalled = $true
                versionMajor = $appVersion.Major
                versionMinor = $appVersion.Minor
                versionBuild = $appVersion.Build
                versionRevision = $appVersion.Revision
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -Recurse
    }
}

<#
    .SYNOPSIS
        Unpublish old, uninstalled versions of the deployed apps from a Business Central environment.
    .DESCRIPTION
        After a new version of a Per Tenant Extension is installed, previous versions remain published (but uninstalled)
        and clutter Extension Management. This function unpublishes those old versions using the automation API v2.0
        Microsoft.NAV.unpublish action. Only versions that are not installed AND older than a currently installed version
        of the same app (matched by app id) are unpublished. This is only supported for PTE deployments on BC 25.4
        through 28. On BC 29 and later, Business Central manages old-version cleanup in the background.
        Explicit unpublish is not supported, so AL-Go skips its cleanup with a warning. Background cleanup may
        be delayed; its timing and retained versions are not guaranteed. Read-only Automation API calls determine
        the installed Application version.
        The function is non-fatal: any failure is reported as a warning and never fails the deployment.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to unpublish old app versions from.
    .PARAMETER appFiles
        The list of deployed app files. Only the app id is read from these files to identify which apps to clean up;
        for each such app, published versions are compared against the version currently installed in the environment
        (not the deployed artifact version), and uninstalled versions older than the installed version are unpublished.
#>
function UnpublishOldAppVersions {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $appFiles
    )
    OutputDebugFunctionCall

    try {
        # Deployed app ids read from the .app files
        $deployedApps = @($appFiles | ForEach-Object {
            $appJson = Get-AppJsonFromAppFile -appFile $_
            [PSCustomObject]@{ Id = $appJson.id }
        })
        if ($deployedApps.Count -eq 0) {
            return
        }

        $authContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        $headers = @{ "Authorization" = "Bearer $($authContext.AccessToken)" }
        $automationApiUrl = "$($bcContainerHelperConfig.apiBaseUrl.TrimEnd('/'))/v2.0/$environment/api/microsoft/automation/v2.0"

        $companies = (Invoke-RestMethod -Method Get -Uri "$automationApiUrl/companies" -Headers $headers -UseBasicParsing).value
        if (-not $companies) {
            OutputWarning -message "Could not find any company in environment $environment - skipping unpublish of old app versions."
            return
        }
        $companyId = $companies[0].id
        $companyUrl = "$automationApiUrl/companies($companyId)"
        $extensions = @((Invoke-RestMethod -Method Get -Uri "$companyUrl/extensions" -Headers $headers -UseBasicParsing).value)

        $applicationVersion = GetPTEApplicationVersion -extensions $extensions -environment $environment
        if ($applicationVersion -ge [version]'29.0.0.0') {
            OutputWarning -message "AL-Go cannot explicitly unpublish old PTE versions on Business Central 29 or later; environment $environment is running $applicationVersion. Business Central manages cleanup in the background, which may be delayed; cleanup timing and retained versions are not guaranteed. AL-Go cleanup was skipped; the deployment remains successful."
            return
        }
        if ($applicationVersion -lt [version]'25.4.0.0') {
            OutputWarning -message "Unpublishing old app versions requires Business Central 25.4 or later; environment $environment is running $applicationVersion."
            return
        }

        foreach($deployed in $deployedApps) {
            # All published versions of this app (installed and uninstalled)
            $matching = @($extensions | Where-Object { $_.id -eq $deployed.Id })
            if ($matching.Count -le 1) {
                # Only one (or no) published version - nothing to clean up
                continue
            }
            # Use the currently installed version as the cleanup threshold. The environment may have a newer
            # version installed than the deployed artifact, which PublishPTEApps treats as success.
            $installedVersions = @($matching | Where-Object { $_.isInstalled } | ForEach-Object { [version]::new($_.versionMajor, $_.versionMinor, $_.versionBuild, $_.versionRevision) })
            if ($installedVersions.Count -eq 0) {
                # No installed version - nothing to clean up against
                continue
            }
            $installedVersion = @($installedVersions | Sort-Object -Descending)[0]
            foreach($old in $matching) {
                $oldVersion = [version]::new($old.versionMajor, $old.versionMinor, $old.versionBuild, $old.versionRevision)
                if ($old.isInstalled -or $oldVersion -ge $installedVersion) {
                    # Keep anything still installed and any version at or above the installed version
                    continue
                }
                Write-Host "Unpublishing $($old.displayName) v$oldVersion"
                try {
                    Invoke-RestMethod -Method Post -Headers $headers -Body '{}' -ContentType 'application/json' -UseBasicParsing `
                        -Uri "$companyUrl/extensions($($old.packageId))/Microsoft.NAV.unpublish" | Out-Null
                }
                catch {
                    OutputWarning -message "Failed to unpublish $($old.displayName) v$($oldVersion): $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        OutputWarning -message "Unpublishing old app versions in environment $environment failed: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
        Install or upgrade apps in Business Central.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to install or upgrade apps in.
    .PARAMETER apps
        The list of app files to install or upgrade.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function InstallOrUpgradeApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )
    OutputDebugFunctionCall

    $schemaSyncMode = 'Add'
    if ($installMode -eq 'ForceUpgrade') {
        $schemaSyncMode = 'Force'
        $installMode = 'upgrade'
    }

    $tempPath = NewTemporaryFolder
    try {
        Copy-AppFilesToFolder -appFiles $apps -folder $tempPath | Out-Null
        $apps = @(Get-ChildItem -Path $tempPath -Filter *.app | ForEach-Object { $_.FullName })
        $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
        $PTEsToInstall = @()
        # Run through all apps and install or upgrade AppSource apps first (and collect PTEs)
        foreach($app in $apps) {
            # Get AppJson (works for full .app files, symbol files and also runtime packages)
            $appJson = Get-AppJsonFromAppFile -appFile $app
            $isPTE = ($appjson.idRanges.from -lt 100000 -and $appjson.idRanges.from -ge 50000)
            $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
            $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode
            if ($needsUpgrade) {
                if (-not $isPTE -and $installedApp.publishedAs.Trim() -eq 'Dev') {
                    OutputWarning -message "Dependency AppSource App $($appJson.name) is published in Dev scope. Cannot upgrade."
                    $needsUpgrade = $false
                }
            }
            if ($needsUpgrade -or $needsInstall) {
                if ($isPTE) {
                    $PTEsToInstall += $app
                }
                else {
                    Install-BcAppFromAppSource -bcAuthContext $bcAuthContext -environment $environment -appId $appJson.id -acceptIsvEula -installOrUpdateNeededDependencies -allowInstallationOnProduction
                    # Update installed apps list as dependencies may have changed / been installed
                    $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
                }
            }
        }
        if ($PTEsToInstall) {
            # Install or upgrade PTEs
            PublishPTEApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $PTEsToInstall -SchemaSyncMode $schemaSyncMode
        }
    }
    finally {
        Remove-Item -Path $tempPath -Force -Recurse
    }
}

<#
    .SYNOPSIS
        Install unknown dependencies in Business Central.
    .PARAMETER bcAuthContext
        The Business Central authentication context.
    .PARAMETER environment
        The environment to install unknown dependencies in.
    .PARAMETER apps
        The list of unknown dependency apps to install.
    .PARAMETER installMode
        The mode of installation, can be 'ignore', 'upgrade', 'forceUpgrade'.
#>
function InstallUnknownDependencies {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )
    OutputDebugFunctionCall

    Write-Host "Installing unknown dependencies: $($apps -join ', ')"
    try {
        $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
        # Run through all apps and install or upgrade AppSource apps first (and collect PTEs)
        foreach($app in $apps) {
            # The output of Sort-AppFilesByDependencies is in the format of "AppId:AppName"
            $appId, $appName = $app.Split(':')
            $appVersion = ""
            if ($appName -like 'Microsoft__EXCLUDE_*') {
                Write-Host "App $appName is ignored as it is marked as EXCLUDE"
                continue
            }
            elseif ($appName -match "_(\d+\.\d+\.\d+\.\d+)\.app$") {
                $appVersion = $matches.1
            } else {
                Write-Host "Version not found or incorrect format for unknown dependency $app"
                continue
            }
            # Create a fake appJson with the properties used in CheckIfAppNeedsInstallOrUpgrade
            $appJson = @{
                "name" = $appName
                "id" = $appId
                "Version" = $appVersion
            }

            $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
            $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode
            OutputDebug -message "Checking app $($appJson.name): needsInstall=$needsInstall, needsUpgrade=$needsUpgrade"
            if ($needsUpgrade) {
                if ($installedApp.publishedAs.Trim() -eq 'Dev') {
                    OutputWarning -message "Dependency AppSource App $($appJson.name) is published in Dev scope. Cannot upgrade."
                    $needsUpgrade = $false
                }
            }
            if ($needsUpgrade -or $needsInstall) {
                Install-BcAppFromAppSource -bcAuthContext $bcAuthContext -environment $environment -appId $appJson.id -acceptIsvEula -installOrUpdateNeededDependencies -allowInstallationOnProduction
                # Update installed apps list as dependencies may have changed / been installed
                $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
            }
        }
    }
    finally {
        Write-Host "Unknown dependencies installed or upgraded"
    }
}

Export-ModuleMember -Function GetHeadRefFromPRId, GetAppsAndDependenciesFromArtifacts, CheckIfAppNeedsInstallOrUpgrade, CheckInstalledApps, PublishPTEApps, UnpublishOldAppVersions, InstallOrUpgradeApps, InstallUnknownDependencies
