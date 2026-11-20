$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\AL-Go-Helper.ps1')

# Pin the contract AL-Go implements; update this with its callers and contract tests.
$adminCenterApiVersion = 'v2.29'
$script:adminCenterAuthContext = $null
$script:adminCenterTarget = $null

<#
    .SYNOPSIS
        Prepare the Admin Center target and authentication context for native requests.
    .DESCRIPTION
        Retains the supplied independent context and target for all native requests.
    .PARAMETER authContext
        Dedicated Admin authentication context supplied by the caller, not the original BCH context.
    .PARAMETER settings
        AL-Go settings containing the native API root and application family.
    .PARAMETER preserveScopes
        Preserve explicitly supplied AUTHCONTEXT scopes or resource instead of using the native root.
#>
function Initialize-AdminCenterAuthContext {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext,
        [hashtable] $settings = @{},
        [switch] $preserveScopes
    )

    $target = Get-DeploymentTarget -settings $settings
    $scopes = if ($preserveScopes) { $authContext['Scopes'] } else { "$($target.apiBaseUrl)/" }
    if ($authContext['Scopes'] -ne $scopes) {
        $authContext['Scopes'] = $scopes
        $authContext['UtcExpiresOn'] = [DateTime]::MinValue
    }
    $script:adminCenterAuthContext = $authContext
    $script:adminCenterTarget = $target
}

<#
    .SYNOPSIS
        Resolve the repository's native Admin Center API root and application family.
    .PARAMETER settings
        AL-Go repository settings.
#>
function Get-DeploymentTarget {
    Param(
        [hashtable] $settings = @{}
    )

    $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    if ($settings.ContainsKey('deploymentBaseUrl') -and $settings['deploymentBaseUrl'] -isnot [string]) {
        throw 'deploymentBaseUrl must be a string.'
    }
    if ($settings['deploymentBaseUrl']) { $apiBaseUrl = [string]$settings['deploymentBaseUrl'] }
    $uri = $null
    if (![Uri]::TryCreate($apiBaseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'deploymentBaseUrl must be an absolute HTTPS API root without credentials, query or fragment.'
    }
    $applicationFamily = 'BusinessCentral'
    if ($settings.ContainsKey('deploymentApplicationFamily')) {
        $applicationFamily = $settings['deploymentApplicationFamily']
        if ($applicationFamily -isnot [string] -or [string]::IsNullOrWhiteSpace($applicationFamily)) {
            throw 'deploymentApplicationFamily must be a nonempty string.'
        }
    }
    return @{ apiBaseUrl = $apiBaseUrl.TrimEnd('/'); applicationFamily = $applicationFamily }
}

<#
    .SYNOPSIS
        Build an AL-Go-owned Business Central Admin Center environment URL.
    .PARAMETER applicationFamily
        Application family containing the environment.
    .PARAMETER environment
        Target environment name.
    .PARAMETER apiBaseUrl
        Native Admin Center API root, independent of BcContainerHelper configuration.
#>
function Get-AdminCenterApiUrl {
    Param(
        [string] $applicationFamily = 'BusinessCentral',
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [string] $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    )

    return "$($apiBaseUrl.TrimEnd('/'))/admin/$adminCenterApiVersion/applications/$([Uri]::EscapeDataString($applicationFamily))/environments/$([Uri]::EscapeDataString($environment))"
}

<#
    .SYNOPSIS
        Send one authenticated Admin Center request without retries.
    .DESCRIPTION
        Preserves HTTP errors and records whether sending was attempted in Exception.Data.
        Requires the dedicated Admin context and target to be initialized before use.
        Uses that target unless explicitly overridden and retains renewed authentication.
    .PARAMETER environment
        Target environment.
    .PARAMETER path
        Unescaped endpoint segments relative to the environment.
    .PARAMETER method
        HTTP method.
    .PARAMETER body
        Serialized request bytes, passed unchanged on PowerShell 5 and 7.
    .PARAMETER contentType
        Request content type.
    .PARAMETER timeoutSeconds
        Maximum duration of this request.
    .PARAMETER applicationFamily
        Target application family.
    .PARAMETER apiBaseUrl
        Target API root.
#>
function Invoke-AdminCenterApi {
    Param(
        [string] $environment,
        [string[]] $path,
        [ValidateSet('Get', 'Post')]
        [string] $method = 'Get',
        [byte[]] $body,
        [string] $contentType,
        [ValidateRange(1, 300)]
        [int] $timeoutSeconds = 30,
        [string] $applicationFamily = 'BusinessCentral',
        [string] $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    )

    $requestStarted = $false
    try {
        if ($null -eq $script:adminCenterAuthContext -or $null -eq $script:adminCenterTarget) {
            throw 'The Admin Center context and target must be initialized before making requests.'
        }
        if (!$PSBoundParameters.ContainsKey('apiBaseUrl')) { $apiBaseUrl = $script:adminCenterTarget.apiBaseUrl }
        if (!$PSBoundParameters.ContainsKey('applicationFamily')) { $applicationFamily = $script:adminCenterTarget.applicationFamily }
        $uri = Get-AdminCenterApiUrl -environment $environment -applicationFamily $applicationFamily -apiBaseUrl $apiBaseUrl
        $uri += '/' + (($path | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
        $authContext = Renew-BcAuthContext -bcAuthContext $script:adminCenterAuthContext
        if (!$authContext -or !$authContext['AccessToken']) {
            throw 'Admin Center token renewal returned no access token before sending the request.'
        }
        $script:adminCenterAuthContext = $authContext
        Write-Host "::add-mask::$($authContext.AccessToken)"
        $parameters = @{
            Uri = $uri
            Method = $method
            Headers = @{ Authorization = "Bearer $($authContext.AccessToken)" }
            UseBasicParsing = $true
            TimeoutSec = $timeoutSeconds
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('body')) { $parameters.Body = $body }
        if ($PSBoundParameters.ContainsKey('contentType')) { $parameters.ContentType = $contentType }
        $requestStarted = $true
        Invoke-RestMethod @parameters
    }
    catch {
        $_.Exception.Data['AdminCenterRequestStarted'] = $requestStarted
        throw
    }
}

<#
    .SYNOPSIS
        Upload an app package for immediate PTE installation.
    .DESCRIPTION
        Builds and disposes multipart content using binary serialization supported on PowerShell 5 and 7.
        Makes one upload attempt without retries using the initialized Admin context.
        Returns the operation without waiting. Use Install-AdminCenterPTEApps to wait for installation.
    .PARAMETER environment
        Target environment.
    .PARAMETER appFile
        App package to upload.
    .PARAMETER syncMode
        Admin Center schema synchronization mode, Add or ForceSync.
    .PARAMETER applicationFamily
        Target application family.
    .PARAMETER apiBaseUrl
        Target API root.
#>
function Install-AdminCenterPTEApp {
    Param(
        [string] $environment,
        [string] $appFile,
        [ValidateSet('Add', 'ForceSync')]
        [string] $syncMode = 'Add',
        [string] $applicationFamily = 'BusinessCentral',
        [string] $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    )

    $multipart = $null
    try {
        Add-Type -AssemblyName System.Net.Http
        $multipart = [System.Net.Http.MultipartFormDataContent]::new()
        $fileContent = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($appFile))
        $multipart.Add($fileContent, 'extensionFile', [System.IO.Path]::GetFileName($appFile))
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $fields = @{
            deploymentSchedule = 'Immediate'
            syncMode = $syncMode
            acceptIsvEula = 'true'
            installOrUpdateNeededDependencies = 'false'
        }
        foreach ($field in $fields.Keys) {
            $multipart.Add([System.Net.Http.StringContent]::new($fields[$field]), $field)
        }
        $bytes = $multipart.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $parameters = @{} + $PSBoundParameters
        $parameters.Remove('appFile')
        $parameters.Remove('syncMode')
        Invoke-AdminCenterApi @parameters `
            -path @('apps', 'pteInstall') -method Post -body $bytes -contentType $multipart.Headers.ContentType.ToString() -timeoutSeconds 300
    }
    finally {
        if ($multipart) { $multipart.Dispose() }
    }
}

<#
    .SYNOPSIS
        Read the exact app operation without polling or retrying.
    .DESCRIPTION
        Uses the initialized Admin authentication context and target.
    .PARAMETER environment
        Target environment.
    .PARAMETER appId
        App identifier.
    .PARAMETER operationId
        Operation identifier returned by installation.
    .PARAMETER timeoutSeconds
        Maximum duration of this status request.
    .PARAMETER applicationFamily
        Target application family.
    .PARAMETER apiBaseUrl
        Target API root.
#>
function Get-AdminCenterAppOperation {
    Param(
        [string] $environment,
        [string] $appId,
        [string] $operationId,
        [ValidateRange(1, 30)]
        [int] $timeoutSeconds = 30,
        [string] $applicationFamily = 'BusinessCentral',
        [string] $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    )

    $parameters = @{} + $PSBoundParameters
    $parameters.Remove('appId')
    $parameters.Remove('operationId')
    Invoke-AdminCenterApi @parameters -path @('apps', $appId, 'operations', $operationId)
}

<#
    .SYNOPSIS
        Read installed extensions from Admin Center in the deployment extension format.
    .DESCRIPTION
        Uses the observed id/name/version/state response and accepts the documented appId identity.
        Returns installed-app records with full version components when valid.
        The endpoint returns installed apps. The appType is retained as publishedAs so deployment
        can preserve its Dev-scope dependency safeguard. Records without an unambiguous identity
        fail explicitly. Invalid or incomplete versions retain empty version components so
        selected-app version comparisons fail rather than assume a version.
        Uses the initialized Admin authentication context and target.
    .PARAMETER environment
        Target environment.
    .PARAMETER applicationFamily
        Target application family.
    .PARAMETER apiBaseUrl
        Target API root.
#>
function Get-AdminCenterInstalledExtensions {
    Param(
        [string] $environment,
        [string] $applicationFamily = 'BusinessCentral',
        [string] $apiBaseUrl = 'https://api.businesscentral.dynamics.com'
    )

    $response = Invoke-AdminCenterApi @PSBoundParameters -path @('apps')
    $response = $response | ConvertTo-HashTable -recurse
    if ($response -isnot [hashtable] -or !$response.ContainsKey('value') -or $response['value'] -isnot [array]) {
        throw 'Admin Center installed-app response must contain an apps array.'
    }
    foreach ($app in $response['value']) {
        if ($app -isnot [hashtable]) {
            throw 'Admin Center installed app has missing or invalid identity.'
        }
        $id = if ($app['appId']) { $app['appId'] } else { $app['id'] }
        if ($id -isnot [string] -or !$id.Trim() -or
            ($app['appId'] -and $app['id'] -and $app['appId'] -ne $app['id'])) {
            throw 'Admin Center installed app has missing or conflicting identity.'
        }
        $version = $null
        if ($app['version'] -isnot [string] -or
            ![version]::TryParse($app['version'], [ref]$version) -or $version.Revision -lt 0) {
            $version = $null
        }
        [PSCustomObject]@{
            id = $id
            displayName = $app['name']
            version = $app['version']
            versionMajor = if ($version) { $version.Major } else { $null }
            versionMinor = if ($version) { $version.Minor } else { $null }
            versionBuild = if ($version) { $version.Build } else { $null }
            versionRevision = if ($version) { $version.Revision } else { $null }
            isInstalled = $true
            state = $app['state']
            publishedAs = $app['appType']
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

    $installedApps = @($extensions | ForEach-Object { $_ | ConvertTo-HashTable -recurse } |
        Where-Object { $_['isInstalled'] })
    $applications = @($installedApps | Where-Object { $_['id'] -eq $applicationAppId })
    if (!$applications.Count) {
        $applications = @($installedApps | Where-Object { $_['displayName'] -eq 'Application' })
    }
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
        Wait for the exact Admin Center PTE operation to complete successfully.
    .DESCRIPTION
        Polls only the returned app and operation IDs. An accepted or scheduled immediate install
        is not success. Only transient status-read errors are retried, never the upload.
        Uses the initialized Admin authentication context.
    .PARAMETER environment
        Target environment.
    .PARAMETER operation
        Upload response containing the operation id, appId and status.
    .PARAMETER appId
        Expected app ID from the package.
    .PARAMETER timeoutSeconds
        Maximum elapsed polling time. Defaults to 30 minutes.
    .PARAMETER maxStatusRequests
        Maximum number of status requests. Defaults to 360.
    .PARAMETER pollIntervalSeconds
        Delay between status requests. Defaults to 30 seconds, capped by the remaining timeout.
#>
function WaitPTEOperation {
    Param(
        [string] $environment,
        $operation,
        [string] $appId,
        [ValidateRange(1, 1800)]
        [int] $timeoutSeconds = 1800,
        [ValidateRange(1, 360)]
        [int] $maxStatusRequests = 360,
        [ValidateRange(0, 30)]
        [int] $pollIntervalSeconds = 30
    )

    $operation = $operation | ConvertTo-HashTable -recurse
    if ($operation -isnot [hashtable] -or !$operation['id'] -or $operation['appId'] -ne $appId) {
        throw "PTE upload returned missing or mismatched app/operation details for app $appId. The upload will not be replayed."
    }
    $operationId = [string]$operation['id']
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
                $serviceError = @($operation['errorMessage'])
                if ($operation['error'] -is [hashtable]) {
                    $serviceError += $operation['error']['message']
                }
                $serviceError = @($serviceError | Where-Object { $_ -is [string] }) -join ' '
                throw "PTE operation $operationId for app $appId did not succeed ($status). $serviceError"
            }
        }
        if ($requests -ge $maxStatusRequests -or $timer.Elapsed.TotalSeconds -ge $timeoutSeconds) {
            break
        }
        $sleepSeconds = [Math]::Min($pollIntervalSeconds, [Math]::Max(0, $timeoutSeconds - $timer.Elapsed.TotalSeconds))
        Start-Sleep -Milliseconds ([int][Math]::Ceiling($sleepSeconds * 1000))
        if ($timer.Elapsed.TotalSeconds -ge $timeoutSeconds) { break }
        $requests++
        try {
            $requestTimeout = [int][Math]::Max(1, [Math]::Min(30, [Math]::Ceiling($timeoutSeconds - $timer.Elapsed.TotalSeconds)))
            $operation = Get-AdminCenterAppOperation -environment $environment `
                -appId $appId -operationId $operationId -timeoutSeconds $requestTimeout
            $operation = $operation | ConvertTo-HashTable -recurse
            $transientErrors = 0
        }
        catch {
            $statusCode = 0
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            $transient = $_.Exception.Data['AdminCenterRequestStarted'] -ne $false -and ($statusCode -in 408,429,500,502,503,504 -or
                (!$statusCode -and ($_.Exception -is [System.Net.WebException] -or
                    $_.Exception -is [System.Net.Http.HttpRequestException] -or $_.Exception -is [System.TimeoutException])))
            if (!$transient -or ++$transientErrors -gt 5) {
                throw "Unable to read PTE operation $operationId for app ${appId}: $_"
            }
            OutputWarning -message "Transient error reading PTE operation ${operationId}: $_. Retrying the status request."
        }
    }
    throw "Timed out waiting for PTE operation $operationId for app $appId after $timeoutSeconds seconds or $maxStatusRequests status requests. The upload will not be replayed."
}

<#
    .SYNOPSIS
        Publish a batch of PTE packages through Admin Center.
    .DESCRIPTION
        Requires BC 29 or later. Expands packages, excludes runtime packages and orders dependencies.
        Skips same or newer installed versions, and waits for each exact install operation before continuing.
        Uses the initialized Admin authentication context and target.
        Requires BcContainerHelper package and authentication helpers to be loaded by the caller.
    .PARAMETER environment
        Target Business Central environment name.
    .PARAMETER appFiles
        App packages or archives to publish.
    .PARAMETER schemaSyncMode
        Existing helper-compatible sync mode: Add or Force (mapped to ForceSync).
#>
function Install-AdminCenterPTEApps {
    Param(
        [string] $environment,
        [string[]] $appFiles,
        [ValidateSet('Add', 'Force')]
        [string] $schemaSyncMode = 'Add'
    )

    $extensions = @(Get-AdminCenterInstalledExtensions -environment $environment)
    $applicationVersion = GetPTEApplicationVersion -extensions $extensions -environment $environment
    if ($applicationVersion -lt [version]'29.0.0.0') {
        throw "Admin Center PTE publishing requires BC 29 or later; the selected API will not be changed."
    }
    $tempPath = NewTemporaryFolder
    try {
        $copiedApps = @(Copy-AppFilesToFolder -appFiles $appFiles -folder $tempPath)
        $sortedApps = @(Sort-AppFilesByDependencies -appFiles $copiedApps -excludeRuntimePackages)
        $syncMode = if ($schemaSyncMode -eq 'Force') { 'ForceSync' } else { 'Add' }
        foreach ($appFile in $sortedApps) {
            $appJson = Get-AppJsonFromAppFile -appFile $appFile
            $appVersion = [version]$appJson.version
            $matchingApps = @($extensions | Where-Object { $_.id -eq $appJson.id })
            $installedVersions = @($matchingApps | Where-Object { $_.isInstalled } |
                ForEach-Object { [version]::new("$($_.versionMajor).$($_.versionMinor).$($_.versionBuild).$($_.versionRevision)") })
            if (@($installedVersions | Where-Object { $_ -ge $appVersion }).Count -gt 0) {
                Write-Host "Skipping $($appJson.name) v${appVersion}: version $($installedVersions | Sort-Object -Descending | Select-Object -First 1) is already installed."
                continue
            }
            Write-Host "Publishing and installing $($appJson.name) v$appVersion"
            $operation = Install-AdminCenterPTEApp -environment $environment -appFile $appFile -syncMode $syncMode
            WaitPTEOperation -environment $environment -operation $operation -appId $appJson.id
            Write-Host "Successfully installed $($appJson.name) v$appVersion"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -Recurse
    }
}

Export-ModuleMember -Function GetPTEApplicationVersion, Install-AdminCenterPTEApps, Initialize-AdminCenterAuthContext, Get-AdminCenterApiUrl, Invoke-AdminCenterApi, Install-AdminCenterPTEApp, Get-AdminCenterAppOperation, Get-AdminCenterInstalledExtensions
