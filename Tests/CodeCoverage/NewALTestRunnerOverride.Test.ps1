$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\..\Actions\RunPipeline\RunPipeline.psm1") -Force -DisableNameChecking

    # Define stub functions that record calls for verification.
    # .GetNewClosure() scriptblocks resolve commands in the module scope, bypassing Pester mocks.
    # We use global stubs with call recording instead.
    $global:_RunAlTestsCalls = @()
    function global:Run-AlTests {
        param($ServiceUrl, $Credential, $AutorizationType, $TestSuite, [bool]$Detailed, [switch]$DisableSSLVerification,
              $ResultsFormat, $CodeCoverageTrackingType, $ProduceCodeCoverageMap, $CodeCoverageOutputPath,
              $CodeCoverageFilePrefix, $ExtensionId, $AppName, $ResultsFilePath, [bool]$SaveResultFile,
              $DisabledTests, $TestCodeunitsRange, $TestProcedureRange, $RequiredTestIsolation, $TestType, $TestIsolation)
        $global:_RunAlTestsCalls += @{ ServiceUrl = $ServiceUrl; CodeCoverageTrackingType = $CodeCoverageTrackingType; ProduceCodeCoverageMap = $ProduceCodeCoverageMap; ExtensionId = $ExtensionId; TestIsolation = $TestIsolation; SaveResultFile = $SaveResultFile; ResultsFilePath = $ResultsFilePath }
    }
    function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "" } }
}

AfterAll {
    Remove-Item Function:\global:Run-AlTests -ErrorAction SilentlyContinue
    Remove-Item Function:\global:Get-BcContainerServerConfiguration -ErrorAction SilentlyContinue
    Remove-Variable -Name _RunAlTestsCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe "New-ALTestRunnerOverride" {
    BeforeEach {
        $global:_RunAlTestsCalls = @()
    }

    It "Should return a scriptblock" {
        $result = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
        $result | Should -BeOfType [scriptblock]
    }

    It "Should reject invalid TrackingType" {
        { New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "Invalid" -ProduceMap "PerCodeunit" } | Should -Throw
    }

    It "Should reject invalid ProduceMap" {
        { New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "Invalid" } | Should -Throw
    }

    Context "URL construction" {
        BeforeEach {
            New-Item -Path "TestDrive:\artifacts" -ItemType Directory -Force | Out-Null
        }

        It "Should construct URL with tenant parameter for standard URL" {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].ServiceUrl | Should -Be "http://testcontainer:80/BC/?tenant=default"
        }

        It "Should append tenant to URL with existing query parameters" {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/?company=CRONUS" } }
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].ServiceUrl | Should -Be "http://testcontainer:80/BC/?company=CRONUS&tenant=default"
        }

        It "Should not add tenant if URL already contains tenant parameter" {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/?tenant=mytenant" } }
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].ServiceUrl | Should -Be "http://testcontainer:80/BC/?tenant=mytenant"
        }

        It "Should fallback to container name URL when PublicWebBaseUrl is empty" {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "" } }
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "mycontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].ServiceUrl | Should -Be "http://mycontainer:80/BC/?tenant=default"
        }

        It "Should use tenant from parameters when provided" {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = ""; tenant = "customtenant" }
            $global:_RunAlTestsCalls[0].ServiceUrl | Should -Be "http://testcontainer:80/BC/?tenant=customtenant"
        }
    }

    Context "Result file parsing - JUnit format" {
        BeforeEach {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
            New-Item -Path "TestDrive:\artifacts" -ItemType Directory -Force | Out-Null
        }

        It "Should return true when all JUnit tests pass" {
            Set-Content -Path "TestDrive:\results.xml" -Value '<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="S1" tests="3" failures="0" errors="0"><testcase name="T1" /><testcase name="T2" /><testcase name="T3" /></testsuite></testsuites>' -Encoding UTF8
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            $result = & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "TestDrive:\results.xml" }
            $result | Should -BeTrue
        }

        It "Should return false when JUnit tests have failures" {
            Set-Content -Path "TestDrive:\results_fail.xml" -Value '<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="S1" tests="3" failures="1" errors="0"><testcase name="T1" /><testcase name="T2"><failure message="failed" /></testcase><testcase name="T3" /></testsuite></testsuites>' -Encoding UTF8
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            $result = & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "TestDrive:\results_fail.xml" }
            $result | Should -BeFalse
        }
    }

    Context "Result file parsing - XUnit format" {
        BeforeEach {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
            New-Item -Path "TestDrive:\artifacts" -ItemType Directory -Force | Out-Null
        }

        It "Should return true when all XUnit tests pass" {
            Set-Content -Path "TestDrive:\xunit_pass.xml" -Value '<?xml version="1.0" encoding="utf-8"?><assemblies><assembly name="A1" total="3" passed="3" failed="0"><collection name="C1" total="3" passed="3" failed="0" /></assembly></assemblies>' -Encoding UTF8
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            $result = & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; XUnitResultFileName = "TestDrive:\xunit_pass.xml" }
            $result | Should -BeTrue
        }

        It "Should return false when XUnit tests have failures" {
            Set-Content -Path "TestDrive:\xunit_fail.xml" -Value '<?xml version="1.0" encoding="utf-8"?><assemblies><assembly name="A1" total="3" passed="2" failed="1"><collection name="C1" total="3" passed="2" failed="1" /></assembly></assemblies>' -Encoding UTF8
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            $result = & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; XUnitResultFileName = "TestDrive:\xunit_fail.xml" }
            $result | Should -BeFalse
        }
    }

    Context "Code coverage settings" {
        BeforeEach {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
        }

        It "Should create CodeCoverage subdirectory under build artifact folder" {
            $artifactFolder = "TestDrive:\build_artifacts"
            New-Item -Path $artifactFolder -ItemType Directory -Force | Out-Null
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder $artifactFolder -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            Test-Path (Join-Path $artifactFolder "CodeCoverage") | Should -BeTrue
        }

        It "Should pass TrackingType and ProduceMap to Run-AlTests" {
            $artifactFolder = "TestDrive:\build_artifacts2"
            New-Item -Path $artifactFolder -ItemType Directory -Force | Out-Null
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder $artifactFolder -TrackingType "PerTest" -ProduceMap "PerTest"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].CodeCoverageTrackingType | Should -Be "PerTest"
            $global:_RunAlTestsCalls[0].ProduceCodeCoverageMap | Should -Be "PerTest"
        }
    }

    Context "Parameter forwarding" {
        BeforeEach {
            function global:Get-BcContainerServerConfiguration { param($ContainerName) return @{ PublicWebBaseUrl = "http://testcontainer:80/BC/" } }
            New-Item -Path "TestDrive:\artifacts" -ItemType Directory -Force | Out-Null
        }

        It "Should forward extensionId when provided" {
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = "12345678-1234-1234-1234-123456789012"; appName = ""; JUnitResultFileName = "" }
            $global:_RunAlTestsCalls[0].ExtensionId | Should -Be "12345678-1234-1234-1234-123456789012"
        }

        It "Should map testRunnerCodeunitId 130451 to Disabled isolation" {
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = ""; testRunnerCodeunitId = "130451" }
            $global:_RunAlTestsCalls[0].TestIsolation | Should -Be "Disabled"
        }

        It "Should map testRunnerCodeunitId 130450 to Codeunit isolation" {
            $sb = New-ALTestRunnerOverride -BuildArtifactFolder "TestDrive:\artifacts" -TrackingType "PerRun" -ProduceMap "PerCodeunit"
            & $sb @{ containerName = "testcontainer"; credential = [pscredential]::new("admin", (ConvertTo-SecureString "pass" -AsPlainText -Force)); extensionId = ""; appName = ""; JUnitResultFileName = ""; testRunnerCodeunitId = "130450" }
            $global:_RunAlTestsCalls[0].TestIsolation | Should -Be "Codeunit"
        }
    }
}
