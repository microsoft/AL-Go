Import-Module (Join-Path $PSScriptRoot '../Actions/Deploy/Deploy.psm1') -Force

InModuleScope Deploy { # Allows testing of private functions
    Describe "UnpublishOldAppVersions" {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
            DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

            $script:appId = "00000000-0000-0000-0000-000000000001"
            $script:otherAppId = "00000000-0000-0000-0000-000000000002"
        }

        BeforeEach {
            Mock OutputDebugFunctionCall { }
            Mock OutputWarning { }
            Mock Write-Host { }

            # The deployed app is app 1, version 2.0.0.0
            Mock Get-AppJsonFromAppFile {
                param($appFile)
                if ($appFile -like "*OtherApp*") {
                    return @{ id = $script:otherAppId; name = "Other App"; version = "2.0.0.0" }
                }
                return @{ id = $script:appId; name = "App 1"; version = "2.0.0.0" }
            }

            Mock Renew-BcAuthContext {
                return @{ AccessToken = "test-access-token"; tenantId = "test-tenant" }
            }

            # The implementation requires an installed 'Application' extension >= 25.4 to proceed.
            # This shared fixture is injected into every /extensions response so version detection passes.
            $script:applicationExtension = @{ id = "00000000-0000-0000-0000-0000000000AA"; displayName = "Application"; packageId = "pkg-application"; isInstalled = $true; versionMajor = 26; versionMinor = 0; versionBuild = 0; versionRevision = 0 }

            # Default published extensions in the environment:
            # - app 1 v1.0.0.0 (uninstalled, old)   -> eligible for unpublish
            # - app 1 v2.0.0.0 (installed, deployed) -> keep
            $script:mockExtensions = @(
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v1"; isInstalled = $false; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $true;  versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            )

            Mock Invoke-RestMethod {
                param($Method, $Uri)
                if ($Uri -like "*/companies") {
                    return @{ value = @( @{ id = "company-1"; name = "CRONUS" } ) }
                }
                if ($Method -eq "Get" -and $Uri -like "*/extensions") {
                    return @{ value = @($script:applicationExtension) + $script:mockExtensions }
                }
                # Microsoft.NAV.unpublish POST
                return $null
            }
        }

        It 'Unpublishes an old uninstalled version when a newer version is installed' {
            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Renew-BcAuthContext -Exactly 1
            # Exactly one unpublish call, targeting the old package id
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                $Method -eq "Post" -and $Uri -like "*extensions(pkg-app1-v1)/Microsoft.NAV.unpublish"
            }
        }

        It 'Uses the automation API v2.0 endpoint with a bearer token' {
            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Invoke-RestMethod -ParameterFilter {
                $Uri -like "*/v2.0/test-env/api/microsoft/automation/v2.0/companies" -and $Headers["Authorization"] -eq "Bearer test-access-token"
            }
        }

        It 'Does not unpublish when only one published version exists' {
            $script:mockExtensions = @(
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $true; versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            )

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" }
        }

        It 'Does not unpublish when the deployed version is not installed' {
            # The deployed version (2.0.0.0) is present but NOT installed
            $script:mockExtensions = @(
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v1"; isInstalled = $false; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $false; versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            )

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" }
        }

        It 'Does not unpublish installed old versions or newer versions' {
            $script:mockExtensions = @(
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v1"; isInstalled = $true;  versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 }, # installed -> keep
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $true;  versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 }, # deployed -> keep
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v3"; isInstalled = $false; versionMajor = 3; versionMinor = 0; versionBuild = 0; versionRevision = 0 }  # newer -> keep
            )

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" }
        }

        It 'Only unpublishes versions of the matching app id' {
            $script:mockExtensions = @(
                @{ id = $script:appId;      displayName = "App 1"; packageId = "pkg-app1-v1"; isInstalled = $false; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = $script:appId;      displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $true;  versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = $script:otherAppId; displayName = "Other"; packageId = "pkg-other-v1"; isInstalled = $false; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            )

            # Only deploy App 1 - Other App's old version must not be touched
            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter { $Method -eq "Post" -and $Uri -like "*pkg-app1-v1*" }
            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" -and $Uri -like "*pkg-other*" }
        }

        It 'Warns but does not throw when the unpublish call fails' {
            Mock Invoke-RestMethod {
                param($Method, $Uri)
                if ($Uri -like "*/companies") {
                    return @{ value = @( @{ id = "company-1" } ) }
                }
                if ($Method -eq "Get" -and $Uri -like "*/extensions") {
                    return @{ value = @($script:applicationExtension) + $script:mockExtensions }
                }
                throw "unpublish failed"
            }

            { UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app") } | Should -Not -Throw
            Assert-MockCalled OutputWarning -ParameterFilter { $message -like "*Failed to unpublish*" }
        }

        It 'Warns but does not throw when the environment cannot be queried' {
            Mock Invoke-RestMethod { throw "network error" }

            { UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app") } | Should -Not -Throw
            Assert-MockCalled OutputWarning -ParameterFilter { $message -like "*failed*" }
        }

        It 'Warns when no company is found' {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -like "*/companies") {
                    return @{ value = @() }
                }
                return $null
            }

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled OutputWarning -ParameterFilter { $message -like "*Could not find any company*" }
            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" }
        }

        It 'Does nothing when no app files are provided' {
            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @()

            Assert-MockCalled Renew-BcAuthContext -Times 0
            Assert-MockCalled Invoke-RestMethod -Times 0
        }

        It 'Warns and skips when the environment is older than BC 25.4' {
            $script:applicationExtension = @{ id = "00000000-0000-0000-0000-0000000000AA"; displayName = "Application"; packageId = "pkg-application"; isInstalled = $true; versionMajor = 25; versionMinor = 3; versionBuild = 0; versionRevision = 0 }

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled OutputWarning -ParameterFilter { $message -like "*requires Business Central 25.4*" }
            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq "Post" }
        }

        It 'Uses the installed Application version, ignoring an uninstalled Application record' {
            # An older, uninstalled Application record appears first; the installed 26.0 must be used
            $script:applicationExtension = @{ id = "00000000-0000-0000-0000-0000000000AA"; displayName = "Application"; packageId = "pkg-app-old"; isInstalled = $false; versionMajor = 24; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            $script:mockExtensions = @(
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v1"; isInstalled = $false; versionMajor = 1; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = $script:appId; displayName = "App 1"; packageId = "pkg-app1-v2"; isInstalled = $true;  versionMajor = 2; versionMinor = 0; versionBuild = 0; versionRevision = 0 },
                @{ id = "00000000-0000-0000-0000-0000000000AA"; displayName = "Application"; packageId = "pkg-application"; isInstalled = $true; versionMajor = 26; versionMinor = 0; versionBuild = 0; versionRevision = 0 }
            )

            UnpublishOldAppVersions -bcAuthContext @{ tenantId = "test-tenant" } -environment "test-env" -appFiles @("App1.app")

            Assert-MockCalled OutputWarning -Times 0 -ParameterFilter { $message -like "*requires Business Central 25.4*" }
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
                $Method -eq "Post" -and $Uri -like "*extensions(pkg-app1-v1)/Microsoft.NAV.unpublish"
            }
        }
    }
}
