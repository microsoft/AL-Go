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
            $script:ptePublishingApi = ''
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

        Context "Action route selection" {
            It 'Selects Admin on BC <major> through the native request boundary' -TestCases @(
                @{ major = 29 }, @{ major = 30 }, @{ major = 31 }
            ) {
                param($major)
                $script:application.versionMajor = $major
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and !$PesterBoundParameters.ContainsKey('apiBaseUrl') -and
                    !$PesterBoundParameters.ContainsKey('applicationFamily')
                }
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
            }

            It 'Selects Automation below BC 29 even when Admin access works' {
                $script:application.versionMajor = 28
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be Automation
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Selects Automation once for probe HTTP <statusCode>' -TestCases @(
                @{ statusCode = 401 }, @{ statusCode = 403 }
            ) {
                param($statusCode)
                $script:probeStatus = $statusCode
                Mock Get-AdminCenterInstalledExtensions {
                    $exception = [System.Exception]::new('Admin permission missing')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = $script:probeStatus })
                    throw $exception
                }

                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be Automation
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
                    $message -like '*Admin permission missing*permissions*ContinuousDeployment.md#pte-deployment-authorization*throughout this Deploy action*' -and
                    $message -like '*planned for removal in 2027 release wave 1*'
                }
            }

            It 'Does not emit an Admin permission warning below BC 29 after HTTP <statusCode>' -TestCases @(
                @{ statusCode = 401 }, @{ statusCode = 403 }
            ) {
                param($statusCode)
                $script:application.versionMajor = 28
                $script:probeStatus = $statusCode
                Mock Get-AdminCenterInstalledExtensions {
                    $exception = [System.Exception]::new('Admin permission missing')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = $script:probeStatus })
                    throw $exception
                }

                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be Automation
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Selects Automation for the helper-owned missing-token error' {
                Mock Get-AdminCenterInstalledExtensions {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Security.Authentication.AuthenticationException]::new('Token missing'),
                        'AdminCenterAuthenticationFailed', 'AuthenticationError', $null)
                }

                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox
                $script:ptePublishingApi | Should -Be Automation
                Assert-MockCalled OutputWarning -Exactly 1
            }

            It 'Does not mistake a probe <problem> for an authorization setup failure' -TestCases @(
                @{ problem = 'network' }, @{ problem = 'timeout' }, @{ problem = 'TLS' },
                @{ problem = 'text-only 403' }, @{ problem = 'malformed' }, @{ problem = 'missing Application' },
                @{ problem = 'incomplete Application' }, @{ problem = 'invalid Application' }, @{ problem = 'ambiguous Application' },
                @{ problem = '404' }, @{ problem = '500' }
            ) {
                param($problem)
                switch ($problem) {
                    network { Mock Get-AdminCenterInstalledExtensions { throw [System.Net.WebException]::new('Connection failed') } }
                    timeout { Mock Get-AdminCenterInstalledExtensions { throw [TimeoutException]::new('Timed out') } }
                    TLS { Mock Get-AdminCenterInstalledExtensions { throw [System.Security.Authentication.AuthenticationException]::new('TLS failed') } }
                    'text-only 403' { Mock Get-AdminCenterInstalledExtensions { throw '403 Forbidden' } }
                    malformed { Mock Get-AdminCenterInstalledExtensions { throw 'Invalid app version' } }
                    'missing Application' { Mock Get-AdminCenterInstalledExtensions { return @() } }
                    'incomplete Application' {
                        Mock Get-AdminCenterInstalledExtensions { return @{ displayName = 'Application'; isInstalled = $true; versionMajor = 30 } }
                    }
                    'invalid Application' { $script:application.versionMajor = 'unknown' }
                    'ambiguous Application' { Mock Get-AdminCenterInstalledExtensions { return @($script:application, $script:application.Clone()) } }
                    default {
                        $script:probeStatus = [int]$problem
                        Mock Get-AdminCenterInstalledExtensions {
                            $exception = [System.Exception]::new('Service failure')
                            $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = $script:probeStatus })
                            throw $exception
                        }
                    }
                }
                { Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox } | Should -Throw
                $script:ptePublishingApi | Should -Be ''
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Fails rather than using a default version if the selected Automation read fails' {
                Mock Get-AdminCenterInstalledExtensions {
                    $exception = [System.Exception]::new('Not authorized')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 })
                    throw $exception
                }
                Mock Get-BcInstalledExtensions { throw 'Automation read failed' }

                { Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox } | Should -Throw '*Automation read failed*'
                $script:ptePublishingApi | Should -Be ''
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Overwrites the previous choice on each initialization' {
                Mock Get-AdminCenterInstalledExtensions {
                    $exception = [System.Exception]::new('Not authorized')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 401 })
                    throw $exception
                }
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox
                $script:ptePublishingApi | Should -Be Automation
                Mock Get-AdminCenterInstalledExtensions { return $script:extensions }
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be AdminCenter
            }

            It 'Uses the selected read API without repeating the authorization probe or changing routes' {
                GetInstalledExtensions -bcAuthContext @{} -environment Sandbox -publishingApi AdminCenter | Out-Null
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox'
                }
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Mock Get-AdminCenterInstalledExtensions { throw 'Read failed after selection' }
                { GetInstalledExtensions -bcAuthContext @{} -environment Sandbox -publishingApi AdminCenter } |
                    Should -Throw '*Read failed after selection*'
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                GetInstalledExtensions -bcAuthContext @{} -environment Sandbox -publishingApi Automation | Out-Null
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled OutputWarning -Times 0
            }
        }

        Context "Selected route publishing" {
            BeforeEach {
                $script:ptePublishingApi = 'AdminCenter'
                Mock NewTemporaryFolder { return 'test-app-folder' }
                Mock Copy-AppFilesToFolder { return @('App.app') }
                Mock Sort-AppFilesByDependencies { return @('App.app') }
                Mock Remove-Item { }
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '2.0.0.0' } }
                Mock Install-AdminCenterPTE { return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' } }
                Mock WaitPTEOperation { }
            }

            It 'Reuses the initialized Automation route for dependencies and primary publishing' {
                Mock Get-AdminCenterInstalledExtensions {
                    $exception = [System.Exception]::new('Admin permission missing')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 })
                    throw $exception
                }
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Dependency.app')
                $script:ptePublishingApi | Should -Be Automation
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Primary.app')

                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 2
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled OutputWarning -Exactly 1
            }

            It 'Requires explicit initialization instead of selecting a route while publishing' {
                $script:ptePublishingApi = ''
                GetInstalledExtensions -bcAuthContext @{} -environment Sandbox | Out-Null
                $script:ptePublishingApi | Should -Be ''
                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*must be initialized*'
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Does not switch an Admin route when a later read or write fails authorization' -TestCases @(
                @{ step = 'read' }, @{ step = 'write' }
            ) {
                param($step)
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Dependency.app')
                $exception = [System.Exception]::new('Later access rejected')
                $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 })
                $script:laterFailure = $exception
                if ($step -eq 'read') {
                    Mock Get-AdminCenterInstalledExtensions { throw $script:laterFailure }
                }
                else {
                    Mock Install-AdminCenterPTE { throw $script:laterFailure }
                }
                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Primary.app') } |
                    Should -Throw '*Later access rejected*'

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Reinitializes the route by probing the next environment' {
                Mock Get-AdminCenterInstalledExtensions {
                    if ($environment -eq 'First') {
                        $exception = [System.Exception]::new('First target not configured')
                        $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = 403 })
                        throw $exception
                    }
                    return $script:extensions
                }
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment First
                $script:ptePublishingApi | Should -Be Automation
                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Second
                PublishPTEApps -bcAuthContext @{} -environment Second -appFiles @('App.app')

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 2 -ParameterFilter {
                    $environment -eq 'Second'
                }
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1 -ParameterFilter {
                    $environment -eq 'Second'
                }
            }

            It 'Does not persist a route when the initial probe fails unexpectedly' {
                $script:ptePublishingApi = ''
                Mock Get-AdminCenterInstalledExtensions { throw [TimeoutException]::new('Probe timeout') }
                { Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox } | Should -Throw '*Probe timeout*'
                $script:ptePublishingApi | Should -Be ''
                Assert-MockCalled NewTemporaryFolder -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Does not hide an unexpected metadata read failure before publishing' -TestCases @(
                @{ problem = 'network' }, @{ problem = 'malformed' }
            ) {
                param($problem)
                if ($problem -eq 'network') {
                    Mock Get-AdminCenterInstalledExtensions { throw [System.Net.WebException]::new('Connection failed') }
                }
                else {
                    Mock Get-AdminCenterInstalledExtensions { throw 'Malformed app response' }
                }
                { GetInstalledExtensions -bcAuthContext @{} -environment Sandbox } | Should -Throw
                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Passes original packages to BCH for BC <major> and preserves Force and immediate defaults' -TestCases @(
                @{ major = 27 }, @{ major = 28 }, @{ major = 29 }, @{ major = 30 }, @{ major = 31 }
            ) {
                param($major)
                $script:application.versionMajor = $major
                $script:application.versionMinor = 9
                $script:application.versionBuild = 99999
                $script:application.versionRevision = 99999
                $script:ptePublishingApi = 'Automation'
                Mock Publish-PerTenantExtensionApps {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'schedule'
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                    $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://api.example.test/'
                }

                PublishPTEApps -bcAuthContext @{ tenantId = 'tenant' } -environment 'Sandbox' -appFiles @('Apps.zip') -schemaSyncMode Force

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $bcAuthContext.tenantId -eq 'tenant' -and
                    $appFiles[0] -eq 'Apps.zip' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled NewTemporaryFolder -Times 0
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Times 0
                Assert-MockCalled Invoke-RestMethod -Times 0
            }

            It 'Routes one original batch to the Admin publisher without preparing packages in the router' {
                Mock Publish-AdminCenterPTEApps { }

                PublishPTEApps -bcAuthContext @{ tenantId = 'tenant' } -environment Sandbox -appFiles @('Apps.zip', 'Other.app') `
                    -schemaSyncMode Force

                Assert-MockCalled Publish-AdminCenterPTEApps -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('bcAuthContext') -and $environment -eq 'Sandbox' -and
                    ($appFiles -join ',') -eq 'Apps.zip,Other.app' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Times 0
                Assert-MockCalled Copy-AppFilesToFolder -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Does not silently switch a selected Admin route when the target version changes below BC 29' {
                $script:application.versionMajor = 28

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*selected API will not be changed*'

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
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

            It 'Leaves original BCH credentials out of native snapshot, upload and operation wait calls' {
                PublishPTEApps -bcAuthContext @{ tenantId = 'tenant' } -environment Sandbox -appFiles @('App.app')

                Assert-MockCalled Get-AdminCenterInstalledExtensions -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('bcAuthContext')
                }
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('bcAuthContext')
                }
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('bcAuthContext')
                }
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Uses the full copied paths throughout Admin batch preparation and upload' {
                $script:copiedApp = Join-Path $TestDrive 'expanded packages\Publisher_App_2.0.0.0.app'
                Mock Copy-AppFilesToFolder { return @($script:copiedApp) }
                Mock Sort-AppFilesByDependencies { return $appFiles }

                Publish-AdminCenterPTEApps -environment Sandbox -appFiles @('Apps.zip')

                Assert-MockCalled Sort-AppFilesByDependencies -Exactly 1 -ParameterFilter {
                    $appFiles.Count -eq 1 -and $appFiles[0] -eq $script:copiedApp -and $excludeRuntimePackages
                }
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 1 -ParameterFilter { $appFile -eq $script:copiedApp }
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1 -ParameterFilter { $appFile -eq $script:copiedApp }
                Assert-MockCalled WaitPTEOperation -Exactly 1 -ParameterFilter {
                    $appId -eq 'app-1' -and $operation.id -eq 'operation-1'
                }
                Assert-MockCalled Remove-Item -Exactly 1
            }

            It 'Leaves native target selection to the request boundary' {
                Mock Install-AdminCenterPTE {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'apiBaseUrl'
                    $PesterBoundParameters.Keys | Should -Not -Contain 'applicationFamily'
                    return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' }
                }
                Mock WaitPTEOperation {
                    $PesterBoundParameters.Keys | Should -Not -Contain 'deploymentTarget'
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

            It 'Skips an installed <version> version through Admin Center' -TestCases @(
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
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Times 0
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like '*already installed*' }
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
                    $script:events += "read:$appFile"
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

                ($script:events -join ',') | Should -Be 'read:Dependency.app,upload:Dependency.app,complete:Dependency.app,read:Dependent.app,upload:Dependent.app,complete:Dependent.app'
                Assert-MockCalled Sort-AppFilesByDependencies -Exactly 1 -ParameterFilter { $excludeRuntimePackages -and $appFiles.Count -eq 3 }
                Assert-MockCalled Install-AdminCenterPTE -Times 0 -ParameterFilter { $appFile -eq 'Runtime.app' }
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

            It 'Never changes route after upload HTTP <statusCode>, including the first upload' -TestCases @(
                @{ statusCode = 400 }, @{ statusCode = 401 }, @{ statusCode = 403 },
                @{ statusCode = 404 }, @{ statusCode = 409 }, @{ statusCode = 500 }
            ) {
                param($statusCode)
                $script:uploadStatus = $statusCode
                Mock Install-AdminCenterPTE {
                    $exception = [System.Exception]::new('Upload rejected')
                    $exception | Add-Member NoteProperty Response ([PSCustomObject]@{ StatusCode = $script:uploadStatus })
                    throw $exception
                }
                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*Upload rejected*'
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Leaves Automation package preparation and installed-version skipping entirely to BCH' {
                $script:ptePublishingApi = 'Automation'
                Mock Sort-AppFilesByDependencies { return @('Installed.app', 'First.app', 'Second.app') }
                $script:extensions += @{
                    id = 'Installed.app'; displayName = 'Installed'; isInstalled = $true
                    versionMajor = 3; versionMinor = 0; versionBuild = 0; versionRevision = 0
                }
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    return @{ id = $appFile; name = $appFile; version = '2.0.0.0' }
                }
                Mock Publish-PerTenantExtensionApps {
                    $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://api.example.test/'
                }
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Apps.zip', 'Installed.app') `
                    -schemaSyncMode Force

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    ($appFiles -join ',') -eq 'Apps.zip,Installed.app' -and $schemaSyncMode -eq 'Force'
                }
                Assert-MockCalled Copy-AppFilesToFolder -Times 0
                Assert-MockCalled Sort-AppFilesByDependencies -Times 0
                Assert-MockCalled Get-AppJsonFromAppFile -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Times 0
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
            }

            It 'Propagates Automation batch failures without changing route or preparing packages' {
                $script:ptePublishingApi = 'Automation'
                Mock Publish-PerTenantExtensionApps { throw 'Batch failed' }
                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*Batch failed*'
                $script:ptePublishingApi | Should -Be Automation
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
                Assert-MockCalled NewTemporaryFolder -Times 0
                Assert-MockCalled Remove-Item -Times 0
                Assert-MockCalled Get-AdminCenterInstalledExtensions -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
            }

            It 'Preserves distinct versions from the dependency sorter without synthetic installed entries' {
                Mock Sort-AppFilesByDependencies { return @('Newer.app', 'Older.app') }
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    return @{ id = 'app-1'; name = 'App'; version = $(if ($appFile -eq 'Newer.app') { '3.0.0.0' } else { '2.0.0.0' }) }
                }
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('Apps.zip')

                Assert-MockCalled Install-AdminCenterPTE -Exactly 2
                $script:extensions.Count | Should -Be 1
            }

            It 'Does not fall back for a local file preparation failure reported before sending' {
                Mock Install-AdminCenterPTE {
                    $exception = [IO.FileNotFoundException]::new('Package missing')
                    $exception.Data['AdminCenterRequestStarted'] = $false
                    throw $exception
                }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw '*Package missing*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Does not mistake a TLS authentication exception for a deployment authorization rejection' {
                Mock Install-AdminCenterPTE {
                    throw [System.Security.Authentication.AuthenticationException]::new('TLS handshake failed')
                }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*TLS handshake failed*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
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

            It 'Stops without fallback after a terminal operation failure' {
                Mock WaitPTEOperation {
                    throw 'Operation failed: rejected package'
                }

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } |
                    Should -Throw '*Operation failed: rejected package*'

                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
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
                Assert-MockCalled OutputWarning -Times 0
            }
        }

        Context "Native installed-app decision safety" {
            BeforeEach {
                $script:ptePublishingApi = 'AdminCenter'
                $script:rawApplication = @{
                    id = $applicationAppId; name = 'Application'; version = '30.0.0.0'; state = 'installed'; appType = 'global'
                }
                $script:rawApp = @{ id = 'app-1'; name = 'App'; version = '1.0.0.0'; state = 'installed'; appType = 'tenant' }
                # Bind the production normalizer to the same module as the API and consumer mocks.
                $script:nativeReader = [scriptblock]::Create((Get-Command Get-AdminCenterInstalledExtensions -Module AdminCenterApi).Definition)
                $script:installedAppResponse = @($script:rawApplication, $script:rawApp)
                Mock Invoke-AdminCenterApi { return @{ value = $script:installedAppResponse } }
                Mock Get-AdminCenterInstalledExtensions {
                    & $script:nativeReader -environment $environment
                }
                Mock NewTemporaryFolder { return 'test-app-folder' }
                Mock Copy-AppFilesToFolder { return @('App.app') }
                Mock Get-ChildItem { return [PSCustomObject]@{ FullName = 'App.app' } }
                Mock Sort-AppFilesByDependencies { return @('App.app') }
                Mock Get-AppJsonFromAppFile { return @{ id = 'app-1'; name = 'App'; version = '2.0.0.0'; idRanges = @(@{ from = 50000 }) } }
                Mock Install-AdminCenterPTE { return @{ id = 'operation-1'; appId = 'app-1'; status = 'running' } }
                Mock Install-BcAppFromAppSource { }
                Mock WaitPTEOperation { }
                Mock Remove-Item { }
            }

            It 'Does not require unrelated apps to have names, scopes or usable versions' {
                $script:installedAppResponse = @($script:rawApplication, @{ id = 'unrelated-app'; version = 'invalid' })

                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox
                PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app')

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Install-AdminCenterPTE -Exactly 1
                Assert-MockCalled WaitPTEOperation -Exactly 1
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Rejects selected installed version <version> before upload' -TestCases @(
                @{ version = '1.0' }, @{ version = 'invalid' }
            ) {
                param($version)
                $script:rawApp.version = $version

                { PublishPTEApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw

                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
                Assert-MockCalled Remove-Item -Exactly 1
            }

            It 'Resolves Application by its known identity when its name is absent' {
                $script:rawApplication.Remove('name')

                Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox

                $script:ptePublishingApi | Should -Be AdminCenter
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
            }

            It 'Rejects Application version <version> even when its name is absent' -TestCases @(
                @{ version = '30.0' }, @{ version = 'invalid' }
            ) {
                param($version)
                $script:rawApplication.Remove('name')
                $script:rawApplication.version = $version
                $script:ptePublishingApi = ''

                { Initialize-PTEPublishingApi -bcAuthContext @{} -environment Sandbox } |
                    Should -Throw '*unique installed Application*'

                $script:ptePublishingApi | Should -Be ''
                Assert-MockCalled Get-BcInstalledExtensions -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
            }

            It 'Rejects an invalid selected installed version during primary preflight' {
                $script:rawApp.version = 'invalid'

                { CheckInstalledApps -bcAuthContext @{} -environment Sandbox -appFiles @('App.app') } | Should -Throw

                Assert-MockCalled Install-AdminCenterPTE -Times 0
            }

            It 'Rejects an invalid installed version before writing a matched <kind> dependency' -TestCases @(
                @{ kind = 'PTE'; from = 50000 }, @{ kind = 'AppSource'; from = 100000 }
            ) {
                param($from)
                $script:rawApp.version = 'invalid'
                $script:dependencyFrom = $from
                Mock Get-AppJsonFromAppFile {
                    return @{ id = 'app-1'; name = 'App'; version = '2.0.0.0'; idRanges = @(@{ from = $script:dependencyFrom }) }
                }

                { InstallOrUpgradeApps -bcAuthContext @{} -environment Sandbox -apps @('App.app') -installMode upgrade } | Should -Throw

                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Keeps the Dev-scope AppSource dependency safeguard after normalization' {
                $script:rawApp.appType = 'dev'
                Mock Get-AppJsonFromAppFile {
                    return @{ id = 'app-1'; name = 'App'; version = '2.0.0.0'; idRanges = @(@{ from = 100000 }) }
                }

                InstallOrUpgradeApps -bcAuthContext @{} -environment Sandbox -apps @('App.app') -installMode upgrade

                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { $message -like '*published in Dev scope*Cannot upgrade*' }
                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled Install-AdminCenterPTE -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
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

                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
            }

            It 'Leaves exact-operation target selection to the native request boundary' {
                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('apiBaseUrl') -and !$PesterBoundParameters.ContainsKey('applicationFamily') -and
                    $appId -eq 'app-1' -and $operationId -eq 'operation / 1'
                }
            }

            It 'Reports terminal or unrecognized <status> without fallback metadata' -TestCases @(
                @{ status = 'failed' },
                @{ status = 'canceled' },
                @{ status = 'skipped' },
                @{ status = 'unknown' }
            ) {
                param($status)
                $script:operation.status = $status
                $script:operation | Add-Member NoteProperty errorMessage 'Service validation detail'

                try {
                    WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'
                    throw 'Expected terminal error'
                }
                catch {
                    $_.Exception.Data.Count | Should -Be 0
                    $_.Exception.Message | Should -Match 'Service validation detail'
                }
            }

            It 'Does not dump credentials, headers or arbitrary operation response fields on failure' {
                $script:operation.status = 'failed'
                $script:operation | Add-Member NoteProperty error (@{ message = 'Package validation failed'; credentials = 'private-credentials' })
                $script:operation | Add-Member NoteProperty headers (@{ Authorization = 'private-header' })
                $script:operation | Add-Member NoteProperty arbitrary 'private-response-field'

                try {
                    WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'
                    throw 'Expected failure'
                }
                catch {
                    $_.Exception.Message | Should -Match 'Package validation failed'
                    $_.Exception.Message | Should -Not -Match 'private-credentials|private-header|private-response-field'
                }
            }

            It 'Polls only the exact returned operation and renews authentication' {
                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $appId -eq 'app-1' -and $operationId -eq 'operation / 1' -and $timeoutSeconds -le 30
                }
                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -eq 30000 }
            }

            It 'Uses the requested shorter polling interval without changing the operation endpoint' {
                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' -pollIntervalSeconds 5

                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -eq 5000 }
                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1 -ParameterFilter {
                    $environment -eq 'Sandbox' -and $appId -eq 'app-1' -and $operationId -eq 'operation / 1'
                }
            }

            It 'Does not count scheduled immediate installation as success' {
                $script:operation.status = 'scheduled'

                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1
            }

            It 'Fails explicitly for terminal or unknown status <status>' -TestCases @(
                @{ status = 'failed' }, @{ status = 'canceled' }, @{ status = 'skipped' }, @{ status = 'unknown' }, @{ status = '' }
            ) {
                param($status)
                $script:operation.status = $status
                $script:operation | Add-Member -NotePropertyName errorMessage -NotePropertyValue 'Service diagnostic'

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*operation / 1*Service diagnostic*'

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

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*missing or mismatched*'

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

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Missing or mismatched PTE operation*'
            }

            It 'Retries transient status failures and then succeeds without any write' {
                $script:reads = 0
                Mock Get-AdminCenterAppOperation {
                    $script:reads++
                    if ($script:reads -lt 3) { throw [System.TimeoutException]::new('Temporary failure') }
                    return [PSCustomObject]@{ id = 'operation / 1'; appId = 'app-1'; status = 'succeeded' }
                }

                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 3
                Assert-MockCalled OutputWarning -Exactly 2
            }

            It 'Stops after five consecutive transient retries' {
                Mock Get-AdminCenterAppOperation { throw [System.TimeoutException]::new('Temporary failure') }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*Temporary failure*'

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
                    WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'
                    Assert-MockCalled Get-AdminCenterAppOperation -Exactly 2
                    Assert-MockCalled OutputWarning -Exactly 1
                }
                else {
                    { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*'
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

                WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 12
                Assert-MockCalled OutputWarning -Exactly 10
            }

            It 'Does not retry non-transient errors or renew failures' {
                Mock Get-AdminCenterAppOperation {
                    $exception = [System.TimeoutException]::new('Authentication renewal failed: 403 Forbidden')
                    $exception.Data['AdminCenterRequestStarted'] = $false
                    throw $exception
                }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*403 Forbidden*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Does not retry an authorization status-read failure' {
                Mock Get-AdminCenterAppOperation { throw '401 Unauthorized' }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Unable to read PTE operation*401 Unauthorized*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 1
                Assert-MockCalled OutputWarning -Times 0
            }

            It 'Bounds status attempts even when the operation remains scheduled' {
                Mock Get-AdminCenterAppOperation { return [PSCustomObject]@{ id = 'operation / 1'; status = 'scheduled' } }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' -maxStatusRequests 2 } | Should -Throw '*Timed out*2 status requests*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 2
            }

            It 'Limits the default immediate polling to 360 status requests' {
                Mock Get-AdminCenterAppOperation { return [PSCustomObject]@{ id = 'operation / 1'; status = 'running' } }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' } | Should -Throw '*Timed out*1800 seconds or 360 status requests*'

                Assert-MockCalled Get-AdminCenterAppOperation -Exactly 360
            }

            It 'Honors the elapsed timeout before another status request' {
                Mock Start-Sleep { [System.Threading.Thread]::Sleep(1100) }

                { WaitPTEOperation -environment Sandbox -operation $script:operation -appId 'app-1' -timeoutSeconds 1 } | Should -Throw '*Timed out*1 seconds*'

                Assert-MockCalled Get-AdminCenterAppOperation -Times 0
                Assert-MockCalled Start-Sleep -Exactly 1 -ParameterFilter { $Milliseconds -gt 0 -and $Milliseconds -le 1000 }
            }
        }
    }
}
