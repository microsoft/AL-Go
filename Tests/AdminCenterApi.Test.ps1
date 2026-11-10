Import-Module (Join-Path $PSScriptRoot '..\Actions\.Modules\AdminCenterApi.psm1') -DisableNameChecking

Describe 'AL-Go Admin Center API helpers' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\Actions\AL-Go-Helper.ps1')
        DownloadAndImportBcContainerHelper -baseFolder ([IO.Path]::GetTempPath())
        Import-Module (Join-Path $PSScriptRoot '..\Actions\.Modules\AdminCenterApi.psm1') -DisableNameChecking
    }

    InModuleScope AdminCenterApi {
        Describe 'Admin Center requests and named endpoints' {
            BeforeEach {
                $script:packagePath = Join-Path $TestDrive 'Binary Package.app'
                $script:packageBytes = [byte[]]@(0,128,255,13,10)
                [IO.File]::WriteAllBytes($script:packagePath, $script:packageBytes)
                Mock Write-Host { }
                Mock Renew-BcAuthContext { return @{ AccessToken = 'test-token' } }
                Mock Invoke-RestMethod { return @{ id = 'operation-1' } }
            }

            It 'Sends binary multipart once to the escaped endpoint with <syncMode>' -TestCases @(
                @{ syncMode = 'Add' }, @{ syncMode = 'ForceSync' }
            ) {
                param($syncMode)
                $script:expectedSyncMode = $syncMode
                Mock Invoke-RestMethod {
                    param($Body, $ContentType)
                    ,$Body | Should -BeOfType ([byte[]])
                    $ContentType | Should -BeLike 'multipart/form-data; boundary=*'
                    $wire = [Text.Encoding]::GetEncoding(28591).GetString($Body)
                    $wire | Should -Match 'name="?extensionFile"?; filename="Binary Package.app"'
                    $wire | Should -Match 'Content-Type: application/octet-stream'
                    $wire | Should -Match 'name="?deploymentSchedule"?\r\n\r\nImmediate\r\n'
                    $wire | Should -Match ('name="?syncMode"?\r\n\r\n' + $script:expectedSyncMode + '\r\n')
                    $wire | Should -Match 'name="?acceptIsvEula"?\r\n\r\ntrue\r\n'
                    $wire | Should -Match 'name="?installOrUpdateNeededDependencies"?\r\n\r\nfalse\r\n'
                    $wire.Contains([Text.Encoding]::GetEncoding(28591).GetString($script:packageBytes)) | Should -BeTrue
                    return @{ id = 'operation-1' }
                }

                $result = Install-AdminCenterPTE -bcAuthContext @{ tenantId = 'tenant' } -environment 'QA / East' `
                    -applicationFamily 'Family / US' -appFile $script:packagePath -syncMode $syncMode

                $result.id | Should -Be 'operation-1'
                Assert-MockCalled Renew-BcAuthContext -Exactly 1 -ParameterFilter { $bcAuthContext.tenantId -eq 'tenant' }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/Family%20%2F%20US/environments/QA%20%2F%20East/apps/pteInstall' -and
                    $Method -eq 'Post' -and $Body -is [byte[]] -and
                    $ContentType -like 'multipart/form-data; boundary=*' -and $TimeoutSec -eq 300 -and
                    $Headers.Authorization -eq 'Bearer test-token' -and $UseBasicParsing -and $ErrorAction -eq 'Stop'
                }
                $stream = [IO.File]::Open($script:packagePath, 'Open', 'ReadWrite', 'None')
                $stream.Dispose()
            }

            It 'Reads the exact escaped app operation without body or content type' {
                Mock Invoke-RestMethod {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'Body'
                    $PesterBoundParameters.Keys | Should -Not -Contain 'ContentType'
                    return @{ id = 'operation / 1' }
                }

                Get-AdminCenterAppOperation -bcAuthContext @{} -environment Sandbox -appId 'app / 1' -operationId 'operation / 1' -timeoutSeconds 7

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Method -eq 'Get' -and $TimeoutSec -eq 7 -and
                    $Uri -eq 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/BusinessCentral/environments/Sandbox/apps/app%20%2F%201/operations/operation%20%2F%201'
                }
            }

            It 'Normalizes <identityField> and installed <state> apps including <appType> scope' -TestCases @(
                @{ identityField = 'id'; state = 'installed'; appType = 'global' },
                @{ identityField = 'appId'; state = 'Installed'; appType = 'tenant' },
                @{ identityField = 'id'; state = 'UpdatePending'; appType = 'dev' },
                @{ identityField = 'appId'; state = 'Updating'; appType = 'global' }
            ) {
                param($identityField, $state, $appType)
                $script:appResponse = @{ name = 'Application'; version = '30.0.57777.0'; state = $state; appType = $appType }
                $script:appResponse[$identityField] = 'c1335042-3002-4257-bf8a-75c898ccb1b8'
                Mock Invoke-RestMethod { return [PSCustomObject]@{ value = @([PSCustomObject]$script:appResponse) } }

                $apps = @(Get-AdminCenterInstalledExtensions -bcAuthContext @{ tenantId = 'tenant' } -environment 'QA / East' -applicationFamily 'Family / US')

                $apps.Count | Should -Be 1
                $apps[0].id | Should -Be 'c1335042-3002-4257-bf8a-75c898ccb1b8'
                $apps[0].displayName | Should -Be Application
                $apps[0].version | Should -Be '30.0.57777.0'
                $apps[0].versionMajor | Should -Be 30
                $apps[0].versionMinor | Should -Be 0
                $apps[0].versionBuild | Should -Be 57777
                $apps[0].versionRevision | Should -Be 0
                $apps[0].isInstalled | Should -BeTrue
                $apps[0].state | Should -Be $state
                $apps[0].publishedAs | Should -Be $appType
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Method -eq 'Get' -and $TimeoutSec -eq 30 -and
                    $Uri -eq 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/Family%20%2F%20US/environments/QA%20%2F%20East/apps'
                }
            }

            It 'Accepts an empty apps array without inventing installed apps' {
                Mock Invoke-RestMethod { return @{ value = @() } }
                @(Get-AdminCenterInstalledExtensions -bcAuthContext @{} -environment Sandbox).Count | Should -Be 0
            }

            It 'Rejects malformed installed-app data: <problem>' -TestCases @(
                @{ problem = 'missing array' }, @{ problem = 'missing identity' }, @{ problem = 'conflicting identity' },
                @{ problem = 'missing name' }, @{ problem = 'missing state' }, @{ problem = 'unknown state' },
                @{ problem = 'uninstalled' }, @{ problem = 'incomplete version' }, @{ problem = 'invalid version' },
                @{ problem = 'unknown scope' }
            ) {
                param($problem)
                $script:appResponse = @{ id = 'app'; name = 'Application'; version = '30.0.57777.0'; state = 'installed'; appType = 'global' }
                switch ($problem) {
                    'missing identity' { $script:appResponse.Remove('id') }
                    'conflicting identity' { $script:appResponse.appId = 'different-app' }
                    'missing name' { $script:appResponse.Remove('name') }
                    'missing state' { $script:appResponse.Remove('state') }
                    'unknown state' { $script:appResponse.state = 'unknown' }
                    'uninstalled' { $script:appResponse.state = 'uninstalled' }
                    'incomplete version' { $script:appResponse.version = '30.0' }
                    'invalid version' { $script:appResponse.version = 'unknown' }
                    'unknown scope' { $script:appResponse.appType = 'unknown' }
                }
                Mock Invoke-RestMethod { return @{ value = @($script:appResponse) } }
                if ($problem -eq 'missing array') { Mock Invoke-RestMethod { return @{} } }

                { Get-AdminCenterInstalledExtensions -bcAuthContext @{} -environment Sandbox } | Should -Throw '*Admin Center*'
                Assert-MockCalled Invoke-RestMethod -Exactly 1
            }

            It 'Marks authentication renewal failures as not sent without trying HTTP' {
                Mock Renew-BcAuthContext { throw [System.TimeoutException]::new('Renewal failed') }

                try {
                    Install-AdminCenterPTE -bcAuthContext @{} -environment Sandbox -appFile $script:packagePath
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception | Should -BeOfType ([System.TimeoutException])
                    $_.Exception.Message | Should -Be 'Renewal failed'
                    $_.Exception.Data['AdminCenterRequestStarted'] | Should -BeFalse
                }
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Rejects authentication without a token before sending' {
                Mock Renew-BcAuthContext { return @{} }

                try {
                    Get-AdminCenterAppOperation -bcAuthContext @{} -environment Sandbox -appId app -operationId operation
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception.Message | Should -BeLike '*Authentication failed*'
                    ($_.FullyQualifiedErrorId -split ',')[0] | Should -Be 'AdminCenterAuthenticationFailed'
                    $_.Exception.Data['AdminCenterRequestStarted'] | Should -BeFalse
                }
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Preserves original HTTP error details and never retries a failed POST or GET' -TestCases @(
                @{ method = 'Post' }, @{ method = 'Get' }
            ) {
                param($method)
                Mock Invoke-RestMethod {
                    $exception = [System.Net.WebException]::new('403 Forbidden')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 }) -Force
                    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'ServiceDenied', 'PermissionDenied', $null)
                    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":{"message":"User not authorized"}}')
                    throw $record
                }

                try {
                    Invoke-AdminCenterApi -bcAuthContext @{} -environment Sandbox -path @('apps','pteInstall') -method $method
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception | Should -BeOfType ([System.Net.WebException])
                    $_.Exception.Response.StatusCode | Should -Be 403
                    $_.Exception.Data['AdminCenterRequestStarted'] | Should -BeTrue
                    $_.ErrorDetails.Message | Should -Match 'User not authorized'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1
            }

            It 'Does not retry an ambiguous upload timeout' {
                Mock Invoke-RestMethod { throw [System.TimeoutException]::new('Response lost') }

                try {
                    Install-AdminCenterPTE -bcAuthContext @{} -environment Sandbox -appFile $script:packagePath
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception | Should -BeOfType ([System.TimeoutException])
                    $_.Exception.Data['AdminCenterRequestStarted'] | Should -BeTrue
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1
                $stream = [IO.File]::Open($script:packagePath, 'Open', 'ReadWrite', 'None')
                $stream.Dispose()
            }

            It 'Preserves local package failure and never calls the request wrapper' {
                Mock Invoke-AdminCenterApi { throw 'Request must not be called' }

                try {
                    Install-AdminCenterPTE -bcAuthContext @{} -environment Sandbox -appFile (Join-Path $TestDrive 'Missing.app')
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception.Message | Should -Match 'Missing.app'
                }
                Assert-MockCalled Invoke-AdminCenterApi -Times 0
                Assert-MockCalled Invoke-RestMethod -Times 0
            }
        }
    }

    It 'Pins the tested contract and encodes each environment and family segment' {
        Get-AdminCenterApiUrl -environment 'QA / East' -applicationFamily 'Family / US' |
            Should -Be 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/Family%20%2F%20US/environments/QA%20%2F%20East'
    }

    It 'Defaults to the standard BusinessCentral application family' {
        Get-AdminCenterApiUrl -environment Sandbox |
            Should -Be 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/BusinessCentral/environments/Sandbox'
    }

    It 'Preserves exception and plain service messages on one log line' {
        $exception = [System.Exception]::new('403 Forbidden')
        $record = [System.Management.Automation.ErrorRecord]::new($exception, 'Denied', 'PermissionDenied', $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("Permission AdminCenter.ReadWrite.All missing.`nUser not authorized.")

        $message = Get-AdminCenterApiErrorMessage -errorRecord $record

        $message | Should -Match '403 Forbidden'
        $message | Should -Match 'Permission AdminCenter.ReadWrite.All missing'
        $message | Should -Match 'User not authorized'
        $message | Should -Not -Match '[\r\n]'
    }

    It 'Reads only service error fields rather than arbitrary structured response properties' {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('403 Forbidden'),
            'Denied', 'PermissionDenied', $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":{"code":"AuthorizationFailed","message":"access denied"},"credentials":{"value":"private-arbitrary-value"},"headers":{"Authorization":"private-base64"}}')

        $message = Get-AdminCenterApiErrorMessage -errorRecord $record

        $message | Should -Match '403 Forbidden AuthorizationFailed access denied'
        $message | Should -Not -Match 'private-arbitrary-value|private-base64|credentials|headers'
    }

    It 'Does not accept or inspect an authentication context' {
        (Get-Command Get-AdminCenterApiErrorMessage).Parameters.Keys | Should -Not -Contain 'bcAuthContext'
    }

    It 'Preserves OAuth error fields without rendering other response properties' {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('{"error":"invalid_client","error_description":"Client not authorized","request":{"headers":{"Authorization":"private-header"}}}'),
            'Denied', 'PermissionDenied', $null)

        $message = Get-AdminCenterApiErrorMessage -errorRecord $record

        $message | Should -Match 'Client not authorized invalid_client'
        $message | Should -Not -Match 'private-header|request|headers'
    }
}
