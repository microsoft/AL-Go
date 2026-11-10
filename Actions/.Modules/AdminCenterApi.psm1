$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# Pin the contract AL-Go implements; update this with its callers and contract tests.
$adminCenterApiVersion = 'v2.29'

<#
    .SYNOPSIS
        Build an AL-Go-owned Business Central Admin Center environment URL.
    .PARAMETER applicationFamily
        Application family containing the environment.
    .PARAMETER environment
        Target environment name.
#>
function Get-AdminCenterApiUrl {
    Param(
        [string] $applicationFamily = 'BusinessCentral',
        [Parameter(Mandatory = $true)]
        [string] $environment
    )

    return "https://api.businesscentral.dynamics.com/admin/$adminCenterApiVersion/applications/$([Uri]::EscapeDataString($applicationFamily))/environments/$([Uri]::EscapeDataString($environment))"
}

<#
    .SYNOPSIS
        Read exception and service error messages without dumping response objects.
    .PARAMETER errorRecord
        Error containing exception and optional service response details.
#>
function Get-AdminCenterApiErrorMessage {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $errorRecord
    )

    $messages = @($errorRecord.Exception.Message)
    if ($errorRecord.ErrorDetails) { $messages += $errorRecord.ErrorDetails.Message }
    $message = (@(foreach ($text in $messages) {
        if ($text.TrimStart().StartsWith('{') -or $text.TrimStart().StartsWith('[')) {
            try {
                $details = $text | ConvertFrom-Json | ConvertTo-HashTable -recurse
                if ($details -is [hashtable]) {
                    if ($details['error'] -is [hashtable]) { $details = $details['error'] }
                    foreach ($field in @('code', 'message', 'error_description')) {
                        if ($details[$field] -is [string]) { $details[$field] }
                    }
                    if ($details['error'] -is [string]) { $details['error'] }
                }
            }
            catch {
                'Structured service error details could not be read.'
            }
        }
        else {
            $text
        }
    }) -join ' ')
    return ($message -replace '[\r\n]+', ' ')
}

<#
    .SYNOPSIS
        Send one authenticated Admin Center request without retries.
    .DESCRIPTION
        Preserves HTTP errors and records whether sending was attempted in Exception.Data.
    .PARAMETER bcAuthContext
        Authentication context to renew.
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
#>
function Invoke-AdminCenterApi {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $path,
        [ValidateSet('Get', 'Post')]
        [string] $method = 'Get',
        [byte[]] $body,
        [string] $contentType,
        [ValidateRange(1, 300)]
        [int] $timeoutSeconds = 30,
        [string] $applicationFamily = 'BusinessCentral'
    )

    $requestStarted = $false
    try {
        $uri = Get-AdminCenterApiUrl -environment $environment -applicationFamily $applicationFamily
        $uri += '/' + (($path | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
        $authContext = Renew-BcAuthContext -bcAuthContext $bcAuthContext
        if (!$authContext -or !$authContext['AccessToken']) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Security.Authentication.AuthenticationException]::new('Authentication failed before Admin Center request.'),
                'AdminCenterAuthenticationFailed', 'AuthenticationError', $null)
        }
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
        Makes one upload attempt without retries.
    .PARAMETER bcAuthContext
        Authentication context.
    .PARAMETER environment
        Target environment.
    .PARAMETER appFile
        App package to upload.
    .PARAMETER syncMode
        Admin Center schema synchronization mode, Add or ForceSync.
    .PARAMETER applicationFamily
        Target application family.
#>
function Install-AdminCenterPTE {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string] $appFile,
        [ValidateSet('Add', 'ForceSync')]
        [string] $syncMode = 'Add',
        [string] $applicationFamily = 'BusinessCentral'
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
        Invoke-AdminCenterApi -bcAuthContext $bcAuthContext -environment $environment -applicationFamily $applicationFamily `
            -path @('apps', 'pteInstall') -method Post -body $bytes -contentType $multipart.Headers.ContentType.ToString() -timeoutSeconds 300
    }
    finally {
        if ($multipart) { $multipart.Dispose() }
    }
}

<#
    .SYNOPSIS
        Read the exact app operation without polling or retrying.
    .PARAMETER bcAuthContext
        Authentication context.
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
#>
function Get-AdminCenterAppOperation {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string] $appId,
        [string] $operationId,
        [ValidateRange(1, 30)]
        [int] $timeoutSeconds = 30,
        [string] $applicationFamily = 'BusinessCentral'
    )

    Invoke-AdminCenterApi -bcAuthContext $bcAuthContext -environment $environment -applicationFamily $applicationFamily `
        -path @('apps', $appId, 'operations', $operationId) -timeoutSeconds $timeoutSeconds
}

<#
    .SYNOPSIS
        Read installed extensions from Admin Center in the deployment extension format.
    .DESCRIPTION
        Uses the observed id/name/version/state response and accepts the documented appId identity.
        Returns installed apps only, with full version components for existing deployment checks.
        Installed, UpdatePending and Updating all describe installed apps. The documented appType
        is retained as publishedAs so deployment can preserve its Dev-scope dependency safeguard.
        Missing or malformed installed-app data fails explicitly.
    .PARAMETER bcAuthContext
        Authentication context.
    .PARAMETER environment
        Target environment.
    .PARAMETER applicationFamily
        Target application family.
#>
function Get-AdminCenterInstalledExtensions {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string] $applicationFamily = 'BusinessCentral'
    )

    $response = Invoke-AdminCenterApi -bcAuthContext $bcAuthContext -environment $environment -applicationFamily $applicationFamily -path @('apps')
    $response = $response | ConvertTo-HashTable -recurse
    if ($response -isnot [hashtable] -or !$response.ContainsKey('value') -or $response['value'] -isnot [array]) {
        throw 'Admin Center installed-app response must contain an apps array.'
    }
    foreach ($app in $response['value']) {
        if ($app -isnot [hashtable] -or $app['state'] -isnot [string] -or !$app['state'].Trim()) {
            throw 'Admin Center app is missing its installation state.'
        }
        if ($app['state'] -notin 'installed', 'updatePending', 'updating') {
            throw 'Admin Center app has an unsupported installation state.'
        }
        $id = if ($app['appId']) { $app['appId'] } else { $app['id'] }
        $version = $null
        if ($id -isnot [string] -or !$id.Trim() -or
            ($app['appId'] -and $app['id'] -and $app['appId'] -ne $app['id']) -or
            $app['name'] -isnot [string] -or !$app['name'].Trim() -or
            $app['version'] -isnot [string] -or
            ![version]::TryParse($app['version'], [ref]$version) -or $version.Revision -lt 0 -or
            $app['appType'] -notin 'global', 'tenant', 'dev') {
            throw 'Admin Center installed app has missing or invalid identity, name, full version or app type.'
        }
        [PSCustomObject]@{
            id = $id
            displayName = $app['name']
            version = $version.ToString()
            versionMajor = $version.Major
            versionMinor = $version.Minor
            versionBuild = $version.Build
            versionRevision = $version.Revision
            isInstalled = $true
            state = $app['state']
            publishedAs = $app['appType']
        }
    }
}

Export-ModuleMember -Function Get-AdminCenterApiUrl, Get-AdminCenterApiErrorMessage, Invoke-AdminCenterApi, Install-AdminCenterPTE, Get-AdminCenterAppOperation, Get-AdminCenterInstalledExtensions
