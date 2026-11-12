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
                $script:adminCenterAuthContext = $null
                $script:adminCenterSourceContext = $null
                $script:adminCenterTarget = $null
                $script:packagePath = Join-Path $TestDrive 'Binary Package.app'
                $script:packageBytes = [byte[]]@(0,128,255,13,10)
                [IO.File]::WriteAllBytes($script:packagePath, $script:packageBytes)
                Mock Write-Host { }
                Mock Renew-BcAuthContext { return @{ AccessToken = 'test-token' } }
                Mock Invoke-RestMethod { return @{ id = 'operation-1' } }
            }

            AfterEach {
                $script:adminCenterAuthContext = $null
                $script:adminCenterSourceContext = $null
                $script:adminCenterTarget = $null
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
                    -apiBaseUrl 'https://api.embed.test/service/' -applicationFamily 'Family / US' -appFile $script:packagePath -syncMode $syncMode

                $result.id | Should -Be 'operation-1'
                Assert-MockCalled Renew-BcAuthContext -Exactly 1 -ParameterFilter { $bcAuthContext.tenantId -eq 'tenant' }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://api.embed.test/service/admin/v2.29/applications/Family%20%2F%20US/environments/QA%20%2F%20East/apps/pteInstall' -and
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

                Get-AdminCenterAppOperation -bcAuthContext @{} -environment Sandbox -appId 'app / 1' -operationId 'operation / 1' -timeoutSeconds 7 `
                    -apiBaseUrl 'https://api.embed.test' -applicationFamily 'Custom Family'

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Method -eq 'Get' -and $TimeoutSec -eq 7 -and
                    $Uri -eq 'https://api.embed.test/admin/v2.29/applications/Custom%20Family/environments/Sandbox/apps/app%20%2F%201/operations/operation%20%2F%201'
                }
            }

            It 'Reads installed apps only from the configured root and explicit family' {
                Mock Invoke-RestMethod { return @{ value = @() } }

                @(Get-AdminCenterInstalledExtensions -bcAuthContext @{} -environment 'QA / East' `
                    -apiBaseUrl 'https://api.embed.test/service/' -applicationFamily 'Custom / Family').Count | Should -Be 0

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://api.embed.test/service/admin/v2.29/applications/Custom%20%2F%20Family/environments/QA%20%2F%20East/apps'
                }
            }

            It 'Renews an isolated Admin context without changing the BCH resource or token' {
                $original = @{
                    tenantId = 'tenant'; Scopes = 'https://legacy.test/'; AccessToken = 'legacy-token'
                    UtcExpiresOn = [DateTime]::UtcNow.AddHours(1)
                }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{ deploymentBaseUrl = 'https://admin.test' }
                Mock Renew-BcAuthContext {
                    $bcAuthContext.Scopes | Should -Be 'https://admin.test/'
                    $bcAuthContext.UtcExpiresOn | Should -Be ([DateTime]::MinValue)
                    $bcAuthContext.AccessToken = 'admin-token'
                    return $bcAuthContext
                }

                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps -apiBaseUrl 'https://admin.test'

                $original.Scopes | Should -Be 'https://legacy.test/'
                $original.AccessToken | Should -Be 'legacy-token'
                $original.UtcExpiresOn | Should -BeGreaterThan ([DateTime]::UtcNow)
                Assert-MockCalled Renew-BcAuthContext -Exactly 1
                Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter { $Object -eq '::add-mask::admin-token' }
            }

            It 'Preserves an explicit scope even when it differs from the Admin endpoint' {
                $expires = [DateTime]::UtcNow.AddHours(1)
                Mock Renew-BcAuthContext {
                    $bcAuthContext.Scopes | Should -Be 'https://explicit-resource.test/.default'
                    $bcAuthContext.UtcExpiresOn | Should -Be $expires
                    return @{ AccessToken = 'explicit-token' }
                }
                $original = @{
                    Scopes = 'https://explicit-resource.test/.default'
                    UtcExpiresOn = $expires
                }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{ deploymentBaseUrl = 'https://admin.test' } -preserveScopes
                Invoke-AdminCenterApi -environment Sandbox -path apps -apiBaseUrl 'https://admin.test' -bcAuthContext $original
                Assert-MockCalled Renew-BcAuthContext -Exactly 1
            }

            It 'Does not mutate the BCH context when Admin renewal fails' {
                $original = @{ Scopes = 'https://legacy.test/' }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{ deploymentBaseUrl = 'https://admin.test' }
                Mock Renew-BcAuthContext {
                    $bcAuthContext.Scopes = 'changed-copy'
                    throw [TimeoutException]::new('Renewal timed out')
                }
                { Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps } | Should -Throw '*Renewal timed out*'
                $original.Scopes | Should -Be 'https://legacy.test/'
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Uses the Admin resource in the actual BCH renewal without retargeting its original context' {
                Mock Invoke-RestMethod -ModuleName BcContainerHelper { return @{ access_token = 'fake-token' } }
                Mock Parse-JWTtoken -ModuleName BcContainerHelper {
                    return @{ appid = 'fake-client'; exp = 2000000000 }
                }
                $newContext = Get-Command New-BcAuthContext -Module BcContainerHelper
                $original = & $newContext -tenantID fake-tenant -clientID fake-client -clientSecret fake-secret `
                    -scopes 'https://legacy.test/' -silent
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{ deploymentBaseUrl = 'https://admin.test' }
                Mock Renew-BcAuthContext {
                    $renew = Get-Command Renew-BcAuthContext -Module BcContainerHelper
                    & $renew -bcAuthContext $bcAuthContext -silent
                }

                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps -apiBaseUrl 'https://admin.test'

                Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 1 -ParameterFilter {
                    $Body.scope -eq 'https://admin.test/.default'
                }
                Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 1 -ParameterFilter {
                    $Body.scope -eq 'https://legacy.test/.default'
                }
                $original.Scopes | Should -Be 'https://legacy.test/'
            }

            It 'Reuses renewed native tokens across reads, upload and polling, then renews once on expiry' {
                $script:tokenRequests = 0
                Mock Invoke-RestMethod -ModuleName BcContainerHelper {
                    $script:tokenRequests++
                    return @{ access_token = "fake-token-$script:tokenRequests" }
                }
                Mock Parse-JWTtoken -ModuleName BcContainerHelper {
                    return @{ appid = 'fake-client'; exp = 2000000000 }
                }
                $newContext = Get-Command New-BcAuthContext -Module BcContainerHelper
                $original = & $newContext -tenantID fake-tenant -clientID fake-client -clientSecret fake-secret `
                    -scopes 'https://legacy.test/' -silent
                $originalToken = $original.AccessToken
                $originalExpiry = $original.UtcExpiresOn
                $originalConfig = $bcContainerHelperConfig.apiBaseUrl
                $settings = @{ deploymentBaseUrl = 'https://admin.test'; deploymentApplicationFamily = 'Family / US' }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings $settings
                $settings.deploymentBaseUrl = 'https://changed-after-initialization.test'
                Mock Renew-BcAuthContext {
                    $renew = Get-Command Renew-BcAuthContext -Module BcContainerHelper
                    & $renew -bcAuthContext $bcAuthContext -silent
                }
                Mock Invoke-RestMethod { return @{ value = @(); id = 'operation-1' } }

                Get-AdminCenterInstalledExtensions -bcAuthContext $original -environment Sandbox | Out-Null
                Install-AdminCenterPTE -bcAuthContext $original -environment Sandbox -appFile $script:packagePath | Out-Null
                Get-AdminCenterAppOperation -bcAuthContext $original -environment Sandbox -appId app -operationId operation | Out-Null

                Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 1 -ParameterFilter {
                    $Body.scope -eq 'https://admin.test/.default'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 3 -ParameterFilter {
                    $Headers.Authorization -eq 'Bearer fake-token-2' -and
                    ([Uri]$Uri).AbsoluteUri -like 'https://admin.test/admin/v2.29/applications/Family%20%2F%20US/environments/Sandbox/apps*'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter { $Uri -like '*/apps' }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter { $Uri -like '*/apps/pteInstall' }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter { $Uri -like '*/apps/app/operations/operation' }
                $script:adminCenterAuthContext.UtcExpiresOn = [DateTime]::MinValue
                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps | Out-Null
                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps | Out-Null

                Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 2 -ParameterFilter {
                    $Body.scope -eq 'https://admin.test/.default'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 2 -ParameterFilter {
                    $Headers.Authorization -eq 'Bearer fake-token-3'
                }
                $original.AccessToken | Should -Be $originalToken
                $original.UtcExpiresOn | Should -Be $originalExpiry
                $original.Scopes | Should -Be 'https://legacy.test/'
                $bcContainerHelperConfig.apiBaseUrl | Should -Be $originalConfig
            }

            It 'Reuses a valid same-resource token without a token exchange' {
                Mock Renew-BcAuthContext {
                    $renew = Get-Command Renew-BcAuthContext -Module BcContainerHelper
                    & $renew -bcAuthContext $bcAuthContext -silent
                }
                $newContext = Get-Command New-BcAuthContext -Module BcContainerHelper
                Mock Parse-JWTtoken -ModuleName BcContainerHelper { return @{ appid = 'fake-client'; exp = 2000000000 } }
                Mock Invoke-RestMethod -ModuleName BcContainerHelper { return @{ access_token = 'valid-token' } }
                $original = & $newContext -tenantID fake-tenant -clientID fake-client -clientSecret fake-secret -silent
                Initialize-AdminCenterAuthContext -bcAuthContext $original

                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps | Out-Null
                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps | Out-Null

                Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 1
                Assert-MockCalled Invoke-RestMethod -Exactly 2 -ParameterFilter { $Headers.Authorization -eq 'Bearer valid-token' }
            }

            It 'Overwrites target and auth together on initialization without affecting direct callers' {
                $first = @{ Scopes = 'https://first.test/'; AccessToken = 'first-token' }
                Initialize-AdminCenterAuthContext -bcAuthContext $first -settings @{
                    deploymentBaseUrl = 'https://first-admin.test'; deploymentApplicationFamily = 'FirstFamily'
                }
                Mock Renew-BcAuthContext {
                    $bcAuthContext.AccessToken = 'mutated-before-failure'
                    throw [TimeoutException]::new('Renewal timed out')
                }
                { Invoke-AdminCenterApi -bcAuthContext $first -environment First -path apps } | Should -Throw '*Renewal timed out*'
                $first.AccessToken | Should -Be first-token
                Assert-MockCalled Invoke-RestMethod -Times 0
                $second = @{ Scopes = 'https://second.test/'; AccessToken = 'second-token' }
                Initialize-AdminCenterAuthContext -bcAuthContext $second -settings @{
                    deploymentBaseUrl = 'https://second.test'; deploymentApplicationFamily = 'SecondFamily'
                }
                [object]::ReferenceEquals($script:adminCenterSourceContext, $second) | Should -BeTrue
                [object]::ReferenceEquals($script:adminCenterAuthContext, $second) | Should -BeFalse
                Mock Renew-BcAuthContext { return $bcAuthContext }

                Invoke-AdminCenterApi -bcAuthContext $second -environment Second -path apps | Out-Null
                Invoke-AdminCenterApi -bcAuthContext $first -environment First -path apps | Out-Null

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -like 'https://second.test/admin/v2.29/applications/SecondFamily/*' -and $Headers.Authorization -eq 'Bearer second-token'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -like 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/BusinessCentral/*' -and $Headers.Authorization -eq 'Bearer first-token'
                }
                $script:adminCenterAuthContext.AccessToken | Should -Be second-token
                $script:adminCenterAuthContext.Scopes | Should -Be 'https://second.test/'
                $script:adminCenterTarget.apiBaseUrl | Should -Be 'https://second.test'
            }

            It 'Honors explicit native endpoint overrides independently of action target defaults' {
                $original = @{ Scopes = 'https://action.test/'; AccessToken = 'action-token' }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{
                    deploymentBaseUrl = 'https://action.test'; deploymentApplicationFamily = 'ActionFamily'
                }
                Mock Renew-BcAuthContext { return $bcAuthContext }
                Mock Invoke-RestMethod { return @{ value = @(); id = 'operation' } }
                Get-AdminCenterInstalledExtensions -bcAuthContext $original -environment Sandbox `
                    -apiBaseUrl 'https://explicit.test' -applicationFamily 'ExplicitFamily' | Out-Null
                Install-AdminCenterPTE -bcAuthContext $original -environment Sandbox -appFile $script:packagePath `
                    -apiBaseUrl 'https://api.businesscentral.dynamics.com' | Out-Null
                Get-AdminCenterAppOperation -bcAuthContext $original -environment Sandbox -appId app -operationId operation `
                    -applicationFamily BusinessCentral | Out-Null
                Invoke-AdminCenterApi -bcAuthContext $original -environment Sandbox -path apps | Out-Null

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://explicit.test/admin/v2.29/applications/ExplicitFamily/environments/Sandbox/apps'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://api.businesscentral.dynamics.com/admin/v2.29/applications/ActionFamily/environments/Sandbox/apps/pteInstall'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://action.test/admin/v2.29/applications/BusinessCentral/environments/Sandbox/apps/app/operations/operation'
                }
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://action.test/admin/v2.29/applications/ActionFamily/environments/Sandbox/apps'
                }
                $script:adminCenterTarget.apiBaseUrl | Should -Be 'https://action.test'
                $script:adminCenterAuthContext.Scopes | Should -Be 'https://action.test/'
            }

            It 'Keeps an unrelated direct callers explicit target and token separate from action state' {
                $original = @{ Scopes = 'https://action.test/'; AccessToken = 'action-token' }
                Initialize-AdminCenterAuthContext -bcAuthContext $original -settings @{
                    deploymentBaseUrl = 'https://action.test'; deploymentApplicationFamily = 'ActionFamily'
                }
                $direct = @{ Scopes = 'https://direct.test/'; AccessToken = 'direct-token' }
                Mock Renew-BcAuthContext { return $bcAuthContext }
                Mock Invoke-RestMethod { return @{ value = @() } }

                Get-AdminCenterInstalledExtensions -bcAuthContext $direct -environment Sandbox `
                    -apiBaseUrl 'https://direct.test' -applicationFamily DirectFamily | Out-Null

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://direct.test/admin/v2.29/applications/DirectFamily/environments/Sandbox/apps' -and
                    $Headers.Authorization -eq 'Bearer direct-token'
                }
                $script:adminCenterAuthContext.AccessToken | Should -Be action-token
                $script:adminCenterTarget.apiBaseUrl | Should -Be 'https://action.test'
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

    InModuleScope AdminCenterApi {
        It 'Resolves <source> API root without deriving the family from the hostname' -TestCases @(
            @{ source = 'standard default'; settings = @{}; helper = @{}; expected = 'https://api.businesscentral.dynamics.com' },
            @{ source = 'default despite legacy override'; settings = @{}; helper = @{ apiBaseUrl = 'https://legacy.test/' }; expected = 'https://api.businesscentral.dynamics.com' },
            @{ source = 'explicit deployment setting'; settings = @{ deploymentBaseUrl = 'https://deploy.test/root/' }; helper = @{ apiBaseUrl = 'https://legacy.test' }; expected = 'https://deploy.test/root' },
            @{ source = 'empty setting despite legacy override'; settings = @{ deploymentBaseUrl = '' }; helper = @{ apiBaseUrl = 'https://legacy.test/' }; expected = 'https://api.businesscentral.dynamics.com' }
        ) {
            param($settings, $helper, $expected)

            $bcContainerHelperConfig = $helper
            $target = Get-DeploymentTarget -settings $settings

            $target.apiBaseUrl | Should -Be $expected
            $target.applicationFamily | Should -Be 'BusinessCentral'
            $bcContainerHelperConfig | Should -Be $helper
        }

        It 'Resolves family independently and does not retain settings between invocations' {
            $settings = @{ deploymentBaseUrl = 'https://custom.test'; deploymentApplicationFamily = 'Family / One' }
            $helper = @{ apiBaseUrl = 'https://legacy.test' }
            $first = Get-DeploymentTarget -settings $settings
            $second = Get-DeploymentTarget

            $first.applicationFamily | Should -Be 'Family / One'
            $second.applicationFamily | Should -Be 'BusinessCentral'
            $second.apiBaseUrl | Should -Be 'https://api.businesscentral.dynamics.com'
            $helper.apiBaseUrl | Should -Be 'https://legacy.test'
            $settings.deploymentBaseUrl | Should -Be 'https://custom.test'
        }

        It 'Rejects invalid API root <root> without including it in the error' -TestCases @(
            @{ root = 'http://custom.test' }, @{ root = 'relative/path' }, @{ root = 'https://user:private@custom.test' },
            @{ root = 'https://custom.test?private=value' }, @{ root = 'https://custom.test#fragment' }
        ) {
            param($root)
            $invalidSettings = @{ deploymentBaseUrl = $root }
            { Get-DeploymentTarget -settings $invalidSettings } |
                Should -Throw 'deploymentBaseUrl must be an absolute HTTPS API root without credentials, query or fragment.'
        }

        It 'Rejects an empty explicit application family' {
            { Get-DeploymentTarget -settings @{ deploymentApplicationFamily = ' ' } } |
                Should -Throw '*deploymentApplicationFamily must be a nonempty string*'
        }

        It 'Rejects non-string explicit settings rather than silently selecting the standard service' {
            { Get-DeploymentTarget -settings @{ deploymentBaseUrl = $null } } | Should -Throw '*deploymentBaseUrl must be a string*'
            { Get-DeploymentTarget -settings @{ deploymentApplicationFamily = @('One', 'Two') } } | Should -Throw '*deploymentApplicationFamily must be a nonempty string*'
        }
    }

    It 'Keeps target resolution private to native initialization' {
        (Get-Module AdminCenterApi).ExportedFunctions.Keys | Should -Not -Contain 'Get-DeploymentTarget'
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
