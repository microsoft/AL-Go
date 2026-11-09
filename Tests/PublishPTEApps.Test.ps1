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
                versionMajor = 30; versionMinor = 0; versionBuild = 0; versionRevision = 0
            }
            $script:extensions = @($script:application)
            Mock Write-Host { }
            Mock OutputWarning { }
            Mock Renew-BcAuthContext { return @{ AccessToken = 'renewed-test-token' } }
            Mock Invoke-RestMethod { throw "Unexpected HTTP request" }
            Mock Install-AdminCenterPTE { throw 'Unexpected installation request' }
            Mock Get-AdminCenterAppOperation { throw 'Unexpected operation request' }
            Mock Get-AdminCenterInstalledExtensions { return $script:extensions }
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
                Mock Install-AdminCenterPTE { return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' } }
                Mock WaitPTEOperation { }
            }

            It 'Uses only the released helper for BC <major> and preserves Force and immediate defaults' -TestCases @(
                @{ major = 27 }, @{ major = 28 }
            ) {
                param($major)
                $script:application.versionMajor = $major
                $script:application.versionMinor = 9
                $script:application.versionBuild = 99999
                $script:application.versionRevision = 99999
                Mock Publish-PerTenantExtensionApps {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'schedule'
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                }

                PublishPTEApps -bcAuthContext @{ tenantId = 'tenant' } -environment 'Sandbox' -appFiles @('Apps.zip') -schemaSyncMode Force

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $bcAuthContext.tenantId -eq 'tenant' -and
                    $appFiles[0] -eq 'Apps.zip' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled NewTemporaryFolder -Times 0
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Keeps API implementation helpers private and exposes the shared publisher' {
                $exports = (Get-Module Deploy).ExportedFunctions.Keys
                $exports | Should -Contain 'PublishPTEApps'
                $exports | Should -Not -Contain 'InvokePTEUpload'
                $exports | Should -Not -Contain 'WaitPTEOperation'
                $exports | Should -Not -Contain 'GetPTEApplicationVersion'
                (Get-Command PublishPTEApps).Parameters.Keys | Should -Not -Contain 'applicationFamily'
                (Get-Command WaitPTEOperation).Parameters.Keys | Should -Not -Contain 'applicationFamily'
            }

            It 'Uses AL-Go Admin Center publishing for BC <major>' -TestCases @(
                @{ major = 29 }, @{ major = 30 }, @{ major = 31 }
            ) {
                param($major)
                $script:application.versionMajor = $major

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('Apps.zip')

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Copy-AppFilesToFolder -Exactly 1 -ParameterFilter { $appFiles[0] -eq 'Apps.zip' }
                Assert-MockCalled Sort-AppFilesByDependencies -Exactly 1 -ParameterFilter { $excludeRuntimePackages }
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and
                    $syncMode -eq 'Add'
                }
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and
                    $appId -eq 'app-1'
                }
                Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { $LiteralPath -eq 'test-app-folder' -and $Recurse -and $Force }
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
            }

            It 'Uses Automation reads after an Admin <problem> without changing write routing' -TestCases @(
                @{ problem = 'authorization' }, @{ problem = 'network' }, @{ problem = 'malformed response' },
                @{ problem = 'missing Application' }, @{ problem = 'incomplete Application' }, @{ problem = 'ambiguous Application' }
            ) {
                param($problem)
                switch ($problem) {
                    authorization { Mock Get-AdminCenterInstalledExtensions { throw '403 Forbidden: User not authorized' } }
                    network { Mock Get-AdminCenterInstalledExtensions { throw [System.Net.WebException]::new('Connection failed') } }
                    'malformed response' { Mock Get-AdminCenterInstalledExtensions { throw 'Admin Center installed app has invalid full version.' } }
                    'missing Application' { Mock Get-AdminCenterInstalledExtensions { return @() } }
                    'incomplete Application' {
                        Mock Get-AdminCenterInstalledExtensions { return @{ displayName = 'Application'; isInstalled = $true; versionMajor = 30 } }
                    }
                    'ambiguous Application' { Mock Get-AdminCenterInstalledExtensions { return @($script:application, $script:application.Clone()) } }
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter { $Object -like '*Admin Center installed-app read failed*Using the read-only Automation API*' }
            }

            It 'Uses the Automation Application version below 29 when the Admin read fails' {
                $script:application.versionMajor = 28
                Mock Get-AdminCenterInstalledExtensions { throw '403 Forbidden' }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                Assert-MockCalled Install-AdminCenterPTE -Times 0
            }

            It 'Propagates Automation read failure instead of publishing with a default version' {
                Mock Get-AdminCenterInstalledExtensions { throw '403 Forbidden' }
                Mock Get-BcInstalledExtensions { throw 'Automation read failed' }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw '*Automation read failed*'

                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Uses the default API family with <helperConfiguration> helper configuration' -TestCases @(
                @{ helperConfiguration = 'overridden' }, @{ helperConfiguration = 'missing' }
            ) {
                param($helperConfiguration)
                if ($helperConfiguration -eq 'missing') {
                    $script:bcContainerHelperConfig = $null
                }

                Mock Install-AdminCenterPTE {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                    return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' }
                }
                Mock WaitPTEOperation {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                }
                PublishPTEApps -bcAuthContext @{} -environment 'QA / East' -appFiles @('App.app') -schemaSyncMode Force

                Assert-MockCalled Install-AdminCenterPTE -Exactly 1 -ParameterFilter {
                    $environment -eq 'QA / East' -and
                    $syncMode -eq 'ForceSync'
                }
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'QA / East'
                }
            }

            It 'Does not mistake the package version for the target BC version' {
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '28.0.0.0' } }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
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
                Assert-MockCalled Install-AdminCenterPTE -Times 0
            }

            It 'Ignores uninstalled Application records when detecting the target version' {
                $oldApplication = $script:application.Clone()
                $oldApplication.isInstalled = $false
                $oldApplication.versionMajor = 28
                $script:extensions = @($oldApplication, [PSCustomObject]$script:application)

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
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

                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled WaitPTEOperation -Times 0
            }

            It 'Upgrades an older installed app even if an uninstalled newer package is present' {
                $script:extensions += @(
                    @{ id = 'app-1'; displayName = 'App'; isInstalled = $true; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                    @{ id = 'app-1'; displayName = 'App'; isInstalled = $false; versionMajor = 3; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
                )

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app')

                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
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
                Mock Install-AdminCenterPTE {
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
                Assert-MockCalled Install-AdminCenterPTE -Times 0 -ParameterFilter { $appFile -eq 'Runtime.app' }
            }

            It 'Remembers completed installs when another package for the same app is encountered' {
                Mock Sort-AppFilesByDependencies { return @('App.app', 'Duplicate.app') }

                PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app', 'Duplicate.app')

                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
                Assert-MockCalled WaitPTEOperation -Exactly 1
            }

            It 'Does not fall back or continue after an ambiguous <step> failure' -TestCases @(
                @{ step = 'upload' }, @{ step = 'polling' }, @{ step = 'authorization' }
            ) {
                param($step)
                switch ($step) {
                    upload { Mock Install-AdminCenterPTE { throw "Package upload failed" } }
                    polling { Mock WaitPTEOperation { throw "Installation failed" } }
                    authorization { Mock Install-AdminCenterPTE { throw "403 Forbidden" } }
                }

                { PublishPTEApps -bcAuthContext @{} -environment 'Sandbox' -appFiles @('App.app') } | Should -Throw

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
                Assert-MockCalled Remove-Item -Exactly 1
            }

            It 'Falls back on a confirmed failure with actionable service diagnostics and preserves Force' {
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('403 Forbidden: AdminCenter permission missing')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') -schemaSyncMode Force

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $appFiles.Count -eq 1 -and $appFiles[0] -eq 'App.app' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
                    $message -like '*403 Forbidden*permission missing*permissions*ContinuousDeployment.md#pte-deployment-authorization*Falling back*'
                }
                Assert-MockCalled WaitPTEOperation -Times 0
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
            }

            It 'Falls back when the helper reports authentication failed before sending an upload' {
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('Authentication failed: consent missing')
                    $exception.Data['AdminCenterRequestStarted'] = $false
                    throw $exception
                }
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
                    $message -like '*Authentication failed: consent missing*permissions*Falling back*'
                }
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Classifies installation HTTP <statusCode> without replaying ambiguous requests' -TestCases @(
                @{ statusCode = 400; allowed = $true },
                @{ statusCode = 401; allowed = $true },
                @{ statusCode = 403; allowed = $true },
                @{ statusCode = 404; allowed = $true },
                @{ statusCode = 409; allowed = $false },
                @{ statusCode = 429; allowed = $true },
                @{ statusCode = 500; allowed = $false },
                @{ statusCode = 503; allowed = $false }
            ) {
                param($statusCode, $allowed)
                $script:installStatus = $statusCode
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new("Service HTTP $script:installStatus")
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = $script:installStatus })
                    $exception.Data['AdminCenterRequestStarted'] = $true
                    throw $exception
                }

                if ($allowed) {
                    PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')
                    Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                }
                else {
                    { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw "*Service HTTP $statusCode*"
                    Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                }
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
            }

            It 'Allows fallback for a local file preparation failure reported before sending' {
                Mock Install-AdminCenterPTE {
                    $exception = [IO.FileNotFoundException]::new('Package missing')
                    $exception.Data['AdminCenterRequestStarted'] = $false
                    throw $exception
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
            }

            It 'Never treats a status-read rejection or renewal failure as a rejected upload' -TestCases @(
                @{ sent = $true }, @{ sent = $false }
            ) {
                param($sent)
                $script:statusRequestSent = $sent
                Mock WaitPTEOperation {
                    $exception = [System.Exception]::new('403 while checking accepted operation')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 })
                    $exception.Data['AdminCenterRequestStarted'] = $script:statusRequestSent
                    throw $exception
                }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw '*accepted operation*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
            }

            It 'Does not replay completed apps and uses legacy publishing only for remaining sorted apps' {
                Mock Sort-AppFilesByDependencies { return @('First.app', 'Second.app', 'Duplicate.app', 'Third.app') }
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    $id = if ($appFile -eq 'Duplicate.app') { 'First.app' } else { $appFile }
                    return @{ id = $id; name = $id; version = '2.0.0.0' }
                }
                Mock Install-AdminCenterPTE {
                    param($appFile)
                    if ($appFile -eq 'Second.app') {
                        $exception = [System.Exception]::new('Package rejected')
                        $exception.Data['PTEFallbackAllowed'] = $true
                        throw $exception
                    }
                    return @{ id = 'completed'; appId = $appFile; status = 'succeeded' }
                }

                $results = @{}
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Apps.zip') -publishingResults $results

                Assert-MockCalled Install-AdminCenterPTE -Exactly 2
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter { $appId -eq 'First.app' }
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 2
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter { $appFiles[0] -eq 'Second.app' }
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter { $appFiles[0] -eq 'Third.app' }
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0 -ParameterFilter { $appFiles[0] -in 'First.app','Duplicate.app' }
                $results['First.app'] | Should -Be 'AdminCenter'
                $results['Second.app'] | Should -Be 'Automation'
                $results['Third.app'] | Should -Be 'Automation'
            }

            It 'Retains Admin Center cleanup protection across dependency and primary batches for the same app' {
                $results = @{}
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Dependency.app') -publishingResults $results
                $results['app-1'] | Should -Be 'AdminCenter'
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '3.0.0.0' } }
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('Confirmed rejection')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Primary.app') -publishingResults $results

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                $results['app-1'] | Should -Be 'AdminCenter'
            }

            It 'Does not retain publishing paths from a different action' {
                $firstResults = @{}
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') -publishingResults $firstResults
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('Confirmed rejection')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }
                $secondResults = @{}

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') -publishingResults $secondResults

                $firstResults['app-1'] | Should -Be 'AdminCenter'
                $secondResults['app-1'] | Should -Be 'Automation'
            }

            It 'Refreshes installed state before fallback and skips a now-installed app' {
                Mock Install-AdminCenterPTE {
                    $script:extensions += @{
                        id = 'app-1'; isInstalled = $true; versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0
                    }
                    $exception = [System.Exception]::new('Terminal operation failed after installation')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
            }

            It 'Propagates a legacy fallback failure without continuing or claiming success' {
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('Confirmed Admin Center failure')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }
                Mock Publish-PerTenantExtensionApps { throw 'Legacy publishing failed' }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw '*Legacy publishing failed*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                Assert-MockCalled Remove-Item -Exactly 1
            }

            It 'Falls back after a terminal operation failure' {
                Mock WaitPTEOperation {
                    $exception = [System.Exception]::new('Operation failed: rejected package')
                    $exception.Data['PTEFallbackAllowed'] = $true
                    throw $exception
                }

                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
            }

            It 'Stops after an accepted operation loses polling without replaying completed or later apps' {
                Mock Sort-AppFilesByDependencies { return @('First.app', 'Second.app', 'Third.app') }
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    return @{ id = $appFile; name = $appFile; version = '2.0.0.0' }
                }
                Mock WaitPTEOperation {
                    param($appId)
                    if ($appId -eq 'Second.app') {
                        throw 'Timed out waiting for operation operation-2 for app Second.app; last status running'
                    }
                }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Apps.zip') } |
                    Should -Throw '*operation-2*Second.app*running*'

                Assert-MockCalled Install-AdminCenterPTE -Exactly 2
                Assert-MockCalled Install-AdminCenterPTE -Times 0 -ParameterFilter { $appFile -eq 'Third.app' }
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
                    $message -like '*operation-2*permissions*stopping without legacy fallback*'
                }
            }
        }

        Context "Exact operation polling" {
            BeforeEach {
                $script:operation = [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'running'; scheduleKind = 'immediate' }
                Mock Start-Sleep { }
                Mock Get-AdminCenterAppOperation { return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' } }
            }

            It 'Accepts immediate success without polling' {
                $script:operation.status = 'succeeded'

                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
            }

            It 'Allows fallback for terminal <status> but not an unrecognized outcome' -TestCases @(
                @{ status = 'failed'; allowed = $true },
                @{ status = 'canceled'; allowed = $true },
                @{ status = 'skipped'; allowed = $true },
                @{ status = 'unknown'; allowed = $false }
            ) {
                param($status, $allowed)
                $script:operation.status = $status
                $script:operation | Add-Member NoteProperty errorMessage 'Service validation detail'

                try {
                    WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'
                    throw 'Expected terminal error'
                }
                catch {
                    $_.Exception.Data['PTEFallbackAllowed'] | Should -Be $allowed
                    $_.Exception.Message | Should -Match 'Service validation detail'
                }
            }

            It 'Does not dump credentials, headers or arbitrary operation response fields on failure' {
                $script:operation.status = 'failed'
                $script:operation | Add-Member NoteProperty error (@{ message = 'Package validation failed'; credentials = 'private-credentials' })
                $script:operation | Add-Member NoteProperty headers (@{ Authorization = 'private-header' })
                $script:operation | Add-Member NoteProperty arbitrary 'private-response-field'

                try {
                    WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception.Message | Should -Match 'Package validation failed'
                    $_.Exception.Message | Should -Not -Match 'private-credentials|private-header|private-response-field'
                }
            }

            It 'Polls only the exact returned operation and renews authentication' {
                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $appId -eq 'app-1' -and $operationId -eq 'operation / 1' -and $timeoutSeconds -le 30
                }
                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -eq 30000 }
            }

            It 'Uses the requested shorter polling interval without changing the operation endpoint' {
                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' -pollIntervalSeconds 5

                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -eq 5000 }
                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $appId -eq 'app-1' -and $operationId -eq 'operation / 1'
                }
            }

            It 'Does not count scheduled immediate installation as success' {
                $script:operation.status = 'scheduled'

                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1
            }

            It 'Fails explicitly for terminal or unknown status <status>' -TestCases @(
                @{ status = 'failed' }, @{ status = 'canceled' }, @{ status = 'skipped' }, @{ status = 'unknown' }, @{ status = '' }
            ) {
                param($status)
                $script:operation.status = $status
                $script:operation | Add-Member -NotePropertyName errorMessage -NotePropertyValue 'Service diagnostic'

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*operation / 1*Service diagnostic*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
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

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*missing or mismatched*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
            }

            It 'Rejects missing or unrelated status response <response>' -TestCases @(
                @{ response = 'empty' }, @{ response = 'anotherOperation' }, @{ response = 'anotherApp' }, @{ response = 'collection' }
            ) {
                param($response)
                $script:responseKind = $response
                Mock Get-AdminCenterAppOperation {
                    switch ($script:responseKind) {
                        empty { return $null }
                        anotherOperation { return [PSCustomObject]@{ id = 'other'; status = 'succeeded' } }
                        anotherApp { return [PSCustomObject]@{ id = 'operation / 1'; appId = 'other'; status = 'succeeded' } }
                        collection { return [PSCustomObject]@{ value = @(@{ id = 'operation / 1'; status = 'succeeded' }) } }
                    }
                }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Missing or mismatched PTE operation*'
            }

            It 'Retries transient status failures and then succeeds without any write' {
                $script:reads = 0
                Mock Get-AdminCenterAppOperation {
                    $script:reads++
                    if ($script:reads -lt 3) { throw [System.TimeoutException]::new('Temporary failure') }
                    return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' }
                }

                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 3
                Assert-MockCalled OutputWarning -Exactly 2
            }

            It 'Stops after five consecutive transient retries' {
                Mock Get-AdminCenterAppOperation { throw [System.TimeoutException]::new('Temporary failure') }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*Temporary failure*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 6
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
                Mock Get-AdminCenterAppOperation {
                    $script:reads++
                    if ($script:reads -eq 1) {
                        $exception = [System.Exception]::new("HTTP $script:httpStatus")
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = $script:httpStatus })
                        throw $exception
                    }
                    return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' }
                }

                if ($retry) {
                    WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'
                    Assert-MockCalled Get-AdminCenterAppOperation -Exactly 2
                    Assert-MockCalled OutputWarning -Exactly 1
                }
                else {
                    { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*'
                    Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1
                    Assert-MockCalled OutputWarning -Times 0
                }
            }

            It 'Resets the consecutive retry budget after a successful running status read' {
                $script:reads = 0
                Mock Get-AdminCenterAppOperation {
                    $script:reads++
                    if ($script:reads -eq 6) { return [PSCustomObject]@{ id = 'operation / 1'; status = 'running' } }
                    if ($script:reads -eq 12) { return [PSCustomObject]@{ id = 'operation / 1'; status = 'succeeded' } }
                    throw [System.TimeoutException]::new('Transient timeout')
                }

                WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 12
                Assert-MockCalled OutputWarning -Exactly 10
            }

            It 'Does not retry non-transient errors or renew failures' {
                Mock Get-AdminCenterAppOperation {
                    $exception = [System.TimeoutException]::new('Authentication renewal failed: 403 Forbidden')
                    $exception.Data['AdminCenterRequestStarted'] = $false
                    throw $exception
                }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*403 Forbidden*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Does not retry an authorization status-read failure' {
                Mock Get-AdminCenterAppOperation { throw '401 Unauthorized' }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*401 Unauthorized*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Bounds status attempts even when the operation remains scheduled' {
                Mock Get-AdminCenterAppOperation { return [PSCustomObject]@{ id = 'operation / 1'; status = 'scheduled' } }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' -maxStatusRequests 2 } | Should -Throw '*Timed out*2 status requests*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 2
            }

            It 'Limits the default immediate polling to 360 status requests' {
                Mock Get-AdminCenterAppOperation { return [PSCustomObject]@{ id = 'operation / 1'; status = 'running' } }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Timed out*1800 seconds or 360 status requests*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 360
            }

            It 'Honors the elapsed timeout before another status request' {
                Mock Start-Sleep { [System.Threading.Thread]::Sleep(1100) }

                { WaitPTEOperation -bcAuthContext @{} -environment Sandbox -operation $script:operation -appId 'app-1' -timeoutSeconds 1 } | Should -Throw '*Timed out*1 seconds*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -gt 0 -and $Milliseconds -le 1000 }
            }
        }
    }
}
