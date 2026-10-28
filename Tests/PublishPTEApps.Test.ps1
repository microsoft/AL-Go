Import-Module (Join-Path $PSScriptRoot '../Actions/Deploy/Deploy.psm1') -Force

InModuleScope Deploy {
    Describe "AL-Go PTE publishing" {
        BeforeAll {
            . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
            DownloadAndImportBcContainerHelper -baseFolder ([System.IO.Path]::GetTempPath())
            Add-Type -AssemblyName System.Net.Http
            $script:originalConfig = $bcContainerHelperConfig
        }

        AfterAll {
            $script:bcContainerHelperConfig = $script:originalConfig
        }

        BeforeEach {
            $script:bcContainerHelperConfig = @{ apiBaseUrl = 'https://api.example.test/' }
            $script:application = @{
                id = 'application'; displayName = 'Application'; isInstalled = $true
                versionMajor = 29; versionMinor = 0; versionBuild = 0; versionRevision = 0
            }
            $script:extensions = @($script:application)
            Mock Write-Host { }
            Mock OutputWarning { }
            Mock Renew-BcAuthContext { return @{ AccessToken = 'renewed-test-token' } }
            Mock Invoke-RestMethod { throw "Unexpected HTTP request" }
            Mock Get-BcInstalledExtensions { return $script:extensions }
            Mock Publish-PerTenantExtensionApps { }
        }

        Context "Shared router" {
            BeforeEach {
                Mock NewTemporaryFolder { return 'test-app-folder' }
                Mock Copy-AppFilesToFolder { return @('App.app') }
                Mock Sort-AppFilesByDependencies { return @('App.app') }
                Mock Remove-Item { }
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '2.0.0.0' } }
                Mock InvokePTEUpload { return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' } }
                Mock WaitPTEOperation { }
            }

            It 'Uses only the released helper for BC 28 and preserves Force and immediate defaults' {
                $script:application.versionMajor = 28
                Mock Publish-PerTenantExtensionApps {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'schedule'
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                }

                PublishPTEApps -bcAuthContext @{ tenantId = 'tenant' } -environment 'Sandbox' -appFiles @('Apps.zip') -schemaSyncMode Force

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $bcAuthContext.tenantId -eq 'tenant' -and
                    $appFiles[0] -eq 'Apps.zip' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled InvokePTEUpload -Times 0
                Assert-MockCalled NewTemporaryFolder -Times 0
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Keeps API implementation helpers private and exposes the shared publisher' {
                $exports = (Get-Module Deploy).ExportedFunctions.Keys
                $exports | Should -Contain 'PublishPTEApps'
                $exports | Should -Not -Contain 'InvokePTEUpload'
                $exports | Should -Not -Contain 'WaitPTEOperation'
                $exports | Should -Not -Contain 'GetPTEApplicationVersion'
            }

            It 'Uses AL-Go Admin Center publishing for BC <major>' -TestCases @(
                @{ major = 29 }, @{ major = 30 }
            ) {
                param($major)
                $script:application.versionMajor = $major

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('Apps.zip')

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Copy-AppFilesToFolder -Exactly 1 -ParameterFilter { $appFiles[0] -eq 'Apps.zip' }
                Assert-MockCalled Sort-AppFilesByDependencies -Exactly 1 -ParameterFilter { $excludeRuntimePackages }
                Assert-MockCalled InvokePTEUpload -Exactly 1 -ParameterFilter { $syncMode -eq 'Add' }
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter { $appId -eq 'app-1' }
                Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { $LiteralPath -eq 'test-app-folder' -and $Recurse -and $Force }
            }

            It 'Uses the configured base URL and escapes environment and application family' {
                PublishPTEApps -bcAuthContext @{} -environment 'QA / East' -applicationFamily 'Family / US' -appFiles @('App.app') -schemaSyncMode Force

                Assert-MockCalled InvokePTEUpload -Exactly 1 -ParameterFilter {
                    $uri -eq 'https://api.example.test/admin/v2.29/applications/Family%20%2F%20US/environments/QA%20%2F%20East/apps/pteInstall' -and
                    $syncMode -eq 'ForceSync'
                }
            }

            It 'Does not mistake the package version for the target BC version' {
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '28.0.0.0' } }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled InvokePTEUpload -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Fails explicitly before any publishing when the target version is <problem>' -TestCases @(
                @{ problem = 'missing' }, @{ problem = 'incomplete' }, @{ problem = 'invalid' }, @{ problem = 'ambiguous' }
            ) {
                param($problem)
                switch ($problem) {
                    missing { $script:extensions = @() }
                    incomplete { $script:application.Remove('versionMinor') }
                    invalid { $script:application.versionMajor = 'unknown' }
                    ambiguous { $script:extensions += $script:application.Clone() }
                }

                { PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app') } | Should -Throw '*Could not determine the Business Central version*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled InvokePTEUpload -Times 0
            }

            It 'Ignores uninstalled Application records when detecting the target version' {
                $oldApplication = $script:application.Clone()
                $oldApplication.isInstalled = $false
                $oldApplication.versionMajor = 28
                $script:extensions = @($oldApplication, [PSCustomObject]$script:application)

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled InvokePTEUpload -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Skips an installed <version> version but not a newer uninstalled package' -TestCases @(
                @{ version = 2 }, @{ version = 3 }
            ) {
                param($version)
                $script:extensions += @{
                    id = 'app-1'; displayName = 'App'; isInstalled = $true
                    versionMajor = $version; versionMinor = 0; versionBuild = 0; versionRevision = 0
                }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled InvokePTEUpload -Times 0
                Assert-MockCalled WaitPTEOperation -Times 0
            }

            It 'Upgrades an older installed app even if an uninstalled newer package is present' {
                $script:extensions += @(
                    @{ id = 'app-1'; displayName = 'App'; isInstalled = $true; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                    @{ id = 'app-1'; displayName = 'App'; isInstalled = $false; versionMajor = 3; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
                )

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled InvokePTEUpload -Exactly 1
                Assert-MockCalled WaitPTEOperation -Exactly 1
            }

            It 'Completes each dependency before uploading its dependent app and skips runtime packages' {
                Mock Copy-AppFilesToFolder { return @('Dependent.app', 'Runtime.app', 'Dependency.app') }
                Mock Sort-AppFilesByDependencies { return @('Dependency.app', 'Dependent.app') }
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    return @{ id = $appFile; name = $appFile; version = '2.0.0.0' }
                }
                $script:events = @()
                Mock InvokePTEUpload {
                    param($appFile)
                    $script:events += "upload:$appFile"
                    return @{ id = "operation-$appFile"; appId = $appFile; status = 'running' }
                }
                Mock WaitPTEOperation {
                    param($appId)
                    $script:events += "complete:$appId"
                }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('Apps.zip')

                ($script:events -join ',') | Should -Be 'upload:Dependency.app,complete:Dependency.app,upload:Dependent.app,complete:Dependent.app'
                Assert-MockCalled Sort-AppFilesByDependencies -Exactly 1 -ParameterFilter { $excludeRuntimePackages -and $appFiles.Count -eq 3 }
                Assert-MockCalled InvokePTEUpload -Times 0 -ParameterFilter { $appFile -eq 'Runtime.app' }
            }

            It 'Remembers completed installs when another package for the same app is encountered' {
                Mock Sort-AppFilesByDependencies { return @('App.app', 'Duplicate.app') }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app', 'Duplicate.app')

                Assert-MockCalled InvokePTEUpload -Exactly 1
                Assert-MockCalled WaitPTEOperation -Exactly 1
            }

            It 'Does not fall back or continue after <step> failure' -TestCases @(
                @{ step = 'upload' }, @{ step = 'polling' }, @{ step = 'authorization' }
            ) {
                param($step)
                switch ($step) {
                    upload { Mock InvokePTEUpload { throw "Package upload failed" } }
                    polling { Mock WaitPTEOperation { throw "Installation failed" } }
                    authorization { Mock InvokePTEUpload { throw "403 Forbidden" } }
                }

                { PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app') } | Should -Throw

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled InvokePTEUpload -Exactly 1
                Assert-MockCalled Remove-Item -Exactly 1
            }
        }

        Context "Multipart upload" {
            BeforeEach {
                $script:packagePath = Join-Path $TestDrive 'Binary Package.app'
                $script:packageBytes = [byte[]]@(0, 1, 127, 128, 255, 13, 10, 65, 66)
                [System.IO.File]::WriteAllBytes($script:packagePath, $script:packageBytes)
            }

            It 'Sends actual multipart fields and unchanged binary bytes using <syncMode>' -TestCases @(
                @{ syncMode = 'Add' }, @{ syncMode = 'ForceSync' }
            ) {
                param($syncMode)
                $expectedSyncMode = $syncMode
                Mock Invoke-RestMethod {
                    param($Body, $ContentType)
                    ,$Body | Should -BeOfType [byte[]]
                    $ContentType | Should -BeLike 'multipart/form-data; boundary=*'
                    $wireText = [System.Text.Encoding]::GetEncoding(28591).GetString($Body)
                    $wireText | Should -Match 'name="?deploymentSchedule"?\r\n\r\nImmediate\r\n'
                    $wireText | Should -Match ('name="?syncMode"?\r\n\r\n' + $expectedSyncMode + '\r\n')
                    $wireText | Should -Match 'name="?acceptIsvEula"?\r\n\r\ntrue\r\n'
                    $wireText | Should -Match 'name="?installOrUpdateNeededDependencies"?\r\n\r\nfalse\r\n'
                    $wireText | Should -Match 'name="?extensionFile"?; filename="Binary Package.app"'
                    $wireText | Should -Match 'Content-Type: application/octet-stream'
                    $wireText.Contains([System.Text.Encoding]::GetEncoding(28591).GetString($script:packageBytes)) | Should -BeTrue
                    return [PSCustomObject]@{ id = 'operation-1'; appId = 'app-1'; status = 'running' }
                }

                $result = InvokePTEUpload -bcAuthContext @{} -uri 'https://api.example.test/apps/pteInstall' -appFile $script:packagePath -syncMode $syncMode

                $result.id | Should -Be 'operation-1'
                Assert-MockCalled Renew-BcAuthContext -Exactly 1
                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Method -eq 'Post' -and $TimeoutSec -eq 300 -and $ErrorAction -eq 'Stop' -and
                    $Headers.Authorization -eq 'Bearer renewed-test-token'
                }
                $stream = [System.IO.File]::Open($script:packagePath, 'Open', 'ReadWrite', 'None')
                $stream.Dispose()
            }

            It 'Disposes streams and never replays an ambiguous upload failure' {
                Mock Invoke-RestMethod { throw [System.TimeoutException]::new('Upload timed out') }

                { InvokePTEUpload -bcAuthContext @{} -uri 'https://api.example.test/apps/pteInstall' -appFile $script:packagePath -syncMode Add } | Should -Throw '*Upload timed out*'

                Assert-MockCalled Invoke-RestMethod -Exactly 1
                $stream = [System.IO.File]::Open($script:packagePath, 'Open', 'ReadWrite', 'None')
                $stream.Dispose()
            }

            It 'Fails before upload if renewing authentication fails' {
                Mock Renew-BcAuthContext { throw 'Authentication failed' }

                { InvokePTEUpload -bcAuthContext @{} -uri 'https://api.example.test/apps/pteInstall' -appFile $script:packagePath -syncMode Add } | Should -Throw '*Authentication failed*'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Rejects a renewal response without an access token' {
                Mock Renew-BcAuthContext { return @{} }

                { InvokePTEUpload -bcAuthContext @{} -uri 'https://api.example.test/apps/pteInstall' -appFile $script:packagePath -syncMode Add } | Should -Throw '*Authentication failed*'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Preserves service upload diagnostics without replaying the upload' {
                Mock Invoke-RestMethod {
                    $record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('400 Bad Request'), 'InvalidPackage', 'InvalidData', $null)
                    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Service rejected the package signature')
                    throw $record
                }

                { InvokePTEUpload -bcAuthContext @{} -uri 'https://api.example.test/apps/pteInstall' -appFile $script:packagePath -syncMode Add } | Should -Throw '*400 Bad Request*Service rejected the package signature*not be replayed*'

                Assert-MockCalled Invoke-RestMethod -Exactly 1
            }
        }

        Context "Exact operation polling" {
            BeforeEach {
                $script:operation = [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'running'; scheduleKind = 'immediate' }
                Mock Start-Sleep { }
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' } }
            }

            It 'Accepts immediate success without polling' {
                $script:operation.status = 'succeeded'

                WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Polls only the exact returned operation and renews authentication' {
                WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'

                Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                    $Method -eq 'Get' -and $Uri -eq 'https://api.example.test/apps/app-1/operations/operation%20%2F%201' -and
                    $Headers.Authorization -eq 'Bearer renewed-test-token' -and $TimeoutSec -le 30
                }
                Assert-MockCalled Renew-BcAuthContext -Exactly 1
            }

            It 'Does not count scheduled immediate installation as success' {
                $script:operation.status = 'scheduled'

                WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'

                Assert-MockCalled Invoke-RestMethod -Exactly 1
            }

            It 'Fails explicitly for terminal or unknown status <status>' -TestCases @(
                @{ status = 'failed' }, @{ status = 'canceled' }, @{ status = 'skipped' }, @{ status = 'unknown' }, @{ status = '' }
            ) {
                param($status)
                $script:operation.status = $status
                $script:operation | Add-Member -NotePropertyName errorMessage -NotePropertyValue 'Service diagnostic'

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*operation / 1*Service diagnostic*'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Rejects upload responses with missing or mismatched <detail>' -TestCases @(
                @{ detail = 'operationId' }, @{ detail = 'appId' }, @{ detail = 'wrongApp' }, @{ detail = 'empty' }
            ) {
                param($detail)
                switch ($detail) {
                    operationId { $script:operation.id = '' }
                    appId { $script:operation.PSObject.Properties.Remove('appId') }
                    wrongApp { $script:operation.appId = 'another-app' }
                    empty { $script:operation = $null }
                }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*missing or mismatched*'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Rejects missing or unrelated status response <response>' -TestCases @(
                @{ response = 'empty' }, @{ response = 'anotherOperation' }, @{ response = 'anotherApp' }, @{ response = 'collection' }
            ) {
                param($response)
                $script:responseKind = $response
                Mock Invoke-RestMethod {
                    switch ($script:responseKind) {
                        empty { return $null }
                        anotherOperation { return [PSCustomObject]@{ id = 'other'; status = 'succeeded' } }
                        anotherApp { return [PSCustomObject]@{ id = 'operation / 1'; appId = 'other'; status = 'succeeded' } }
                        collection { return [PSCustomObject]@{ value = @(@{ id = 'operation / 1'; status = 'succeeded' }) } }
                    }
                }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*Missing or mismatched PTE operation*'
            }

            It 'Retries transient status failures and then succeeds without any write' {
                $script:reads = 0
                Mock Invoke-RestMethod {
                    $script:reads++
                    if ($script:reads -lt 3) { throw [System.TimeoutException]::new('Temporary failure') }
                    return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' }
                }

                WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'

                Assert-MockCalled Invoke-RestMethod -Exactly 3 -ParameterFilter { $Method -eq 'Get' }
                Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -ne 'Get' }
                Assert-MockCalled OutputWarning -Exactly 2
            }

            It 'Stops after five consecutive transient retries' {
                Mock Invoke-RestMethod { throw [System.TimeoutException]::new('Temporary failure') }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*Temporary failure*'

                Assert-MockCalled Invoke-RestMethod -Exactly 6
                Assert-MockCalled OutputWarning -Exactly 5
            }

            It 'Retries HTTP <statusCode> but never HTTP authorization failures' -TestCases @(
                @{ statusCode = 408; retry = $true },
                @{ statusCode = 429; retry = $true },
                @{ statusCode = 500; retry = $true },
                @{ statusCode = 502; retry = $true },
                @{ statusCode = 503; retry = $true },
                @{ statusCode = 504; retry = $true },
                @{ statusCode = 401; retry = $false },
                @{ statusCode = 403; retry = $false }
            ) {
                param($statusCode, $retry)
                $script:httpStatus = $statusCode
                $script:reads = 0
                Mock Invoke-RestMethod {
                    $script:reads++
                    if ($script:reads -eq 1) {
                        $exception = [System.Exception]::new("HTTP $script:httpStatus")
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = $script:httpStatus })
                        throw $exception
                    }
                    return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' }
                }

                if ($retry) {
                    WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'
                    Assert-MockCalled Invoke-RestMethod -Exactly 2
                    Assert-MockCalled OutputWarning -Exactly 1
                }
                else {
                    { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*'
                    Assert-MockCalled Invoke-RestMethod -Exactly 1
                    Assert-MockCalled OutputWarning -Times 0
                }
            }

            It 'Resets the consecutive retry budget after a successful running status read' {
                $script:reads = 0
                Mock Invoke-RestMethod {
                    $script:reads++
                    if ($script:reads -eq 6) { return [PSCustomObject]@{ id = 'operation / 1'; status = 'running' } }
                    if ($script:reads -eq 12) { return [PSCustomObject]@{ id = 'operation / 1'; status = 'succeeded' } }
                    throw [System.TimeoutException]::new('Transient timeout')
                }

                WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1'

                Assert-MockCalled Invoke-RestMethod -Exactly 12
                Assert-MockCalled OutputWarning -Exactly 10
            }

            It 'Does not retry non-transient errors or renew failures' {
                Mock Renew-BcAuthContext { throw '403 Forbidden' }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*403 Forbidden*'

                Assert-MockCalled Invoke-RestMethod -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Does not retry an authorization status-read failure' {
                Mock Invoke-RestMethod { throw '401 Unauthorized' }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*401 Unauthorized*'

                Assert-MockCalled Invoke-RestMethod -Exactly 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Bounds status attempts even when the operation remains scheduled' {
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = 'operation / 1'; status = 'scheduled' } }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' -maxStatusRequests 2 } | Should -Throw '*Timed out*2 status requests*'

                Assert-MockCalled Invoke-RestMethod -Exactly 2
            }

            It 'Limits the default immediate polling to 360 status requests' {
                Mock Invoke-RestMethod { return [PSCustomObject]@{ id = 'operation / 1'; status = 'running' } }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' } | Should -Throw '*Timed out*1800 seconds or 360 status requests*'

                Assert-MockCalled Invoke-RestMethod -Exactly 360
            }

            It 'Honors the elapsed timeout before another status request' {
                Mock Start-Sleep { [System.Threading.Thread]::Sleep(1100) }

                { WaitPTEOperation -bcAuthContext @{} -appsUri 'https://api.example.test/apps' -operation $script:operation -appId 'app-1' -timeoutSeconds 1 } | Should -Throw '*Timed out*1 seconds*'

                Assert-MockCalled Invoke-RestMethod -Times 0
            }
        }
    }
}
