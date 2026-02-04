Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# Import AL-Go-Helper first (needed for helper functions)
. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

# Import the module
Import-Module (Join-Path $PSScriptRoot "../Actions/DownloadProjectDependencies/DownloadProjectDependencies.psm1" -Resolve) -Force

Describe "DownloadProjectDependencies - Get-AppFilesFromUrl Tests" {
    BeforeEach {
        # Create a temp download folder
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'downloadPath', Justification = 'False positive.')]
        $downloadPath = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Set up RUNNER_TEMP for zip extraction
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalRunnerTemp', Justification = 'False positive.')]
        $originalRunnerTemp = $env:RUNNER_TEMP
        $env:RUNNER_TEMP = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Create a test .app file to use as mock response
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'mockAppFile', Justification = 'False positive.')]
        $mockAppFile = Join-Path $env:RUNNER_TEMP "MockApp.app"
        [System.IO.File]::WriteAllBytes($mockAppFile, [byte[]](1, 2, 3, 4, 5))
    }

    AfterEach {
        # Clean up
        if (Test-Path $downloadPath) {
            Remove-Item -Path $downloadPath -Recurse -Force
        }
        if ($env:RUNNER_TEMP -and (Test-Path $env:RUNNER_TEMP)) {
            Remove-Item -Path $env:RUNNER_TEMP -Recurse -Force
        }
        $env:RUNNER_TEMP = $originalRunnerTemp
    }

    It 'Downloads a single .app file from URL' {
        # Mock Invoke-WebRequest at module level - this works because Invoke-CommandWithRetry
        # calls Invoke-WebRequest with a scriptblock that runs in the module scope
        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3, 4, 5))
        } -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/TestApp.app" -DownloadPath $downloadPath

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -BeLike "*TestApp.app"
        Test-Path @($result)[0] | Should -BeTrue
    }

    It 'Extracts .app files from a zip archive' {
        # Create test .app files in a zip
        $zipSourcePath = Join-Path $env:RUNNER_TEMP "ZipSource"
        New-Item -ItemType Directory -Path $zipSourcePath | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $zipSourcePath "App1.app"), [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes((Join-Path $zipSourcePath "App2.app"), [byte[]](4, 5, 6))
        $zipPath = Join-Path $env:RUNNER_TEMP "TestApps.zip"
        Compress-Archive -Path "$zipSourcePath\*" -DestinationPath $zipPath

        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            Copy-Item -Path $zipPath -Destination $OutFile -Force
        } -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/TestApps.zip" -DownloadPath $downloadPath

        $result | Should -HaveCount 2
        $result | Should -Contain (Join-Path $downloadPath "App1.app")
        $result | Should -Contain (Join-Path $downloadPath "App2.app")
        Test-Path (Join-Path $downloadPath "App1.app") | Should -BeTrue
        Test-Path (Join-Path $downloadPath "App2.app") | Should -BeTrue
        # Zip file should be removed
        Test-Path (Join-Path $downloadPath "TestApps.zip") | Should -BeFalse
    }

    It 'Extracts .app files from nested folders in zip archive' {
        # Create test .app files in nested structure
        $zipSourcePath = Join-Path $env:RUNNER_TEMP "ZipSourceNested"
        New-Item -ItemType Directory -Path "$zipSourcePath\folder1\subfolder" -Force | Out-Null
        New-Item -ItemType Directory -Path "$zipSourcePath\folder2" -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $zipSourcePath "folder1\subfolder\NestedApp.app"), [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes((Join-Path $zipSourcePath "folder2\AnotherApp.app"), [byte[]](4, 5, 6))
        $zipPath = Join-Path $env:RUNNER_TEMP "NestedApps.zip"
        Compress-Archive -Path "$zipSourcePath\*" -DestinationPath $zipPath

        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            Copy-Item -Path $zipPath -Destination $OutFile -Force
        } -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/NestedApps.zip" -DownloadPath $downloadPath

        $result | Should -HaveCount 2
        $result | Should -Contain (Join-Path $downloadPath "NestedApp.app")
        $result | Should -Contain (Join-Path $downloadPath "AnotherApp.app")
    }

    It 'Extracts .app files from nested ZIP inside ZIP' {
        # Create inner ZIP with .app file
        $innerZipSource = Join-Path $env:RUNNER_TEMP "InnerZipSource"
        New-Item -ItemType Directory -Path $innerZipSource -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $innerZipSource "InnerApp.app"), [byte[]](1, 2, 3))
        $innerZipPath = Join-Path $env:RUNNER_TEMP "InnerApps.zip"
        Compress-Archive -Path "$innerZipSource\*" -DestinationPath $innerZipPath

        # Create outer ZIP containing the inner ZIP and another .app
        $outerZipSource = Join-Path $env:RUNNER_TEMP "OuterZipSource"
        New-Item -ItemType Directory -Path $outerZipSource -Force | Out-Null
        Copy-Item -Path $innerZipPath -Destination (Join-Path $outerZipSource "InnerApps.zip")
        [System.IO.File]::WriteAllBytes((Join-Path $outerZipSource "OuterApp.app"), [byte[]](4, 5, 6))
        $outerZipPath = Join-Path $env:RUNNER_TEMP "OuterApps.zip"
        Compress-Archive -Path "$outerZipSource\*" -DestinationPath $outerZipPath

        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            Copy-Item -Path $outerZipPath -Destination $OutFile -Force
        } -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/OuterApps.zip" -DownloadPath $downloadPath

        $result | Should -HaveCount 2
        $result | Should -Contain (Join-Path $downloadPath "OuterApp.app")
        $result | Should -Contain (Join-Path $downloadPath "InnerApp.app")
    }

    It 'Returns empty array and warns when zip contains no .app files' {
        # Create zip with non-.app files
        $zipSourcePath = Join-Path $env:RUNNER_TEMP "ZipSourceNoApps"
        New-Item -ItemType Directory -Path $zipSourcePath | Out-Null
        Set-Content -Path (Join-Path $zipSourcePath "readme.txt") -Value "No apps here"
        $zipPath = Join-Path $env:RUNNER_TEMP "NoApps.zip"
        Compress-Archive -Path "$zipSourcePath\*" -DestinationPath $zipPath

        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            Copy-Item -Path $zipPath -Destination $OutFile -Force
        } -ModuleName DownloadProjectDependencies

        Mock OutputWarning {} -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/NoApps.zip" -DownloadPath $downloadPath

        @($result) | Should -HaveCount 0
        Should -Invoke OutputWarning -ModuleName DownloadProjectDependencies -Times 1 -ParameterFilter {
            $message -like "*No .app files found in zip archive*"
        }
    }

    It 'Handles URL with query parameters' {
        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3, 4, 5))
        } -ModuleName DownloadProjectDependencies

        $result = Get-AppFilesFromUrl -Url "https://example.com/downloads/TestApp.app?token=abc123&expires=2025" -DownloadPath $downloadPath

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -BeLike "*TestApp.app"
    }

    It 'Generates GUID filename when URL path contains only invalid characters' {
        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3, 4, 5))
        } -ModuleName DownloadProjectDependencies

        # URL with only spaces/invalid chars as filename (after sanitization becomes empty)
        $result = Get-AppFilesFromUrl -Url "https://example.com/%20%20%20" -DownloadPath $downloadPath

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -Match "\.app$"
        # Should be a GUID pattern like: 12345678-1234-1234-1234-123456789abc.app
        @($result)[0] | Should -Match "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.app$"
        Test-Path @($result)[0] | Should -BeTrue
    }
}

Describe "DownloadProjectDependencies - Get-AppFilesFromLocalPath Tests" {
    BeforeEach {
        # Create a temp folder for test files
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testFolder', Justification = 'False positive.')]
        $testFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Create destination folder for extracted files
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'destFolder', Justification = 'False positive.')]
        $destFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Set up RUNNER_TEMP for zip extraction
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalRunnerTemp', Justification = 'False positive.')]
        $originalRunnerTemp = $env:RUNNER_TEMP
        $env:RUNNER_TEMP = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    AfterEach {
        if (Test-Path $testFolder) {
            Remove-Item -Path $testFolder -Recurse -Force
        }
        if (Test-Path $destFolder) {
            Remove-Item -Path $destFolder -Recurse -Force
        }
        if ($env:RUNNER_TEMP -and (Test-Path $env:RUNNER_TEMP)) {
            Remove-Item -Path $env:RUNNER_TEMP -Recurse -Force
        }
        $env:RUNNER_TEMP = $originalRunnerTemp
    }

    It 'Copies single .app file to destination' {
        $appFile = Join-Path $testFolder "MyApp.app"
        [System.IO.File]::WriteAllBytes($appFile, [byte[]](1, 2, 3))

        $result = Get-AppFilesFromLocalPath -Path $appFile -DestinationPath $destFolder

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -Be (Join-Path $destFolder "MyApp.app")
        Test-Path @($result)[0] | Should -BeTrue
    }

    It 'Copies all .app files from folder to destination' {
        # Create nested structure
        $subFolder = New-Item -ItemType Directory -Path (Join-Path $testFolder "SubFolder")
        [System.IO.File]::WriteAllBytes((Join-Path $testFolder "App1.app"), [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes((Join-Path $subFolder "App2.app"), [byte[]](4, 5, 6))
        [System.IO.File]::WriteAllBytes((Join-Path $subFolder "NotAnApp.txt"), [byte[]](7, 8, 9))

        $result = Get-AppFilesFromLocalPath -Path $testFolder -DestinationPath $destFolder

        @($result) | Should -HaveCount 2
        @($result) | Should -Contain (Join-Path $destFolder "App1.app")
        @($result) | Should -Contain (Join-Path $destFolder "App2.app")
        Test-Path (Join-Path $destFolder "App1.app") | Should -BeTrue
        Test-Path (Join-Path $destFolder "App2.app") | Should -BeTrue
        Test-Path (Join-Path $destFolder "NotAnApp.txt") | Should -BeFalse
    }

    It 'Resolves wildcard patterns' {
        [System.IO.File]::WriteAllBytes((Join-Path $testFolder "App1.app"), [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes((Join-Path $testFolder "App2.app"), [byte[]](4, 5, 6))
        [System.IO.File]::WriteAllBytes((Join-Path $testFolder "Other.txt"), [byte[]](7, 8, 9))

        $result = Get-AppFilesFromLocalPath -Path (Join-Path $testFolder "*.app") -DestinationPath $destFolder

        @($result) | Should -HaveCount 2
    }

    It 'Extracts .app files from a .nupkg file (ZIP with different extension)' {
        # Create a .nupkg (which is really a ZIP) - create as .zip first, then rename for PS5 compatibility
        $nupkgContentFolder = Join-Path $env:RUNNER_TEMP "NupkgContent"
        New-Item -ItemType Directory -Path $nupkgContentFolder | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $nupkgContentFolder "PackagedApp.app"), [byte[]](1, 2, 3))

        $tempZipFile= Join-Path $testFolder "MyPackage.zip"
        Compress-Archive -Path (Join-Path $nupkgContentFolder "*") -DestinationPath $tempZipFile
        $nupkgFile = Join-Path $testFolder "MyPackage.nupkg"
        Move-Item -Path $tempZipFile -Destination $nupkgFile

        $result = Get-AppFilesFromLocalPath -Path $nupkgFile -DestinationPath $destFolder

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -BeLike "*PackagedApp.app"
        Test-Path @($result)[0] | Should -BeTrue
    }

    It 'Returns empty array for wildcard pattern with no matches' {
        $result = Get-AppFilesFromLocalPath -Path (Join-Path $testFolder "*.app") -DestinationPath $destFolder

        @($result) | Should -HaveCount 0
    }

    It 'Warns when no files found at local path' {
        Mock OutputWarning {} -ModuleName DownloadProjectDependencies

        # Use a cross-platform path (nested Join-Path for PS5 compatibility)
        $nonExistentPath = Join-Path (Join-Path $testFolder "NonExistent") "Path.app"
        $result = Get-AppFilesFromLocalPath -Path $nonExistentPath -DestinationPath $destFolder

        @($result) | Should -HaveCount 0
        Should -Invoke OutputWarning -ModuleName DownloadProjectDependencies -Times 1 -ParameterFilter {
            $message -like "*No files found at local path*"
        }
    }

    It 'Warns when encountering unknown file types' {
        Mock OutputWarning {} -ModuleName DownloadProjectDependencies

        [System.IO.File]::WriteAllBytes((Join-Path $testFolder "readme.txt"), [byte[]](1, 2, 3))

        $result = Get-AppFilesFromLocalPath -Path $testFolder -DestinationPath $destFolder

        @($result) | Should -HaveCount 0
        Should -Invoke OutputWarning -ModuleName DownloadProjectDependencies -Times 1 -ParameterFilter {
            $message -like "*Unknown file type*"
        }
    }
}

Describe "DownloadProjectDependencies - Get-DependenciesFromInstallApps Tests" {
    BeforeEach {
        # Create a temp download folder
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'downloadPath', Justification = 'False positive.')]
        $downloadPath = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Set up RUNNER_TEMP for zip extraction
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalRunnerTemp', Justification = 'False positive.')]
        $originalRunnerTemp = $env:RUNNER_TEMP
        $env:RUNNER_TEMP = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Store original env vars
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalSettings', Justification = 'False positive.')]
        $originalSettings = $env:Settings
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalSecrets', Justification = 'False positive.')]
        $originalSecrets = $env:Secrets
    }

    AfterEach {
        # Clean up
        if (Test-Path $downloadPath) {
            Remove-Item -Path $downloadPath -Recurse -Force
        }
        if ($env:RUNNER_TEMP -and (Test-Path $env:RUNNER_TEMP)) {
            Remove-Item -Path $env:RUNNER_TEMP -Recurse -Force
        }
        $env:RUNNER_TEMP = $originalRunnerTemp
        $env:Settings = $originalSettings
        $env:Secrets = $originalSecrets
    }

    It 'Returns empty arrays when no installApps or installTestApps configured' {
        $env:Settings = @{
            installApps = @()
            installTestApps = @()
        } | ConvertTo-Json -Depth 10

        $result = Get-DependenciesFromInstallApps -DestinationPath $downloadPath

        $result.Apps | Should -HaveCount 0
        $result.TestApps | Should -HaveCount 0
    }

    It 'Copies local .app files to destination path' {
        # Create temporary test files in a source folder (not the download path)
        $sourceFolder = Join-Path $env:RUNNER_TEMP "SourceApps"
        New-Item -ItemType Directory -Path $sourceFolder | Out-Null
        $testAppFile = Join-Path $sourceFolder "MyApp.app"
        [System.IO.File]::WriteAllBytes($testAppFile, [byte[]](1, 2, 3))
        $testTestAppFile = Join-Path $sourceFolder "TestApp.app"
        [System.IO.File]::WriteAllBytes($testTestAppFile, [byte[]](1, 2, 3))

        $env:Settings = @{
            installApps = @($testAppFile)
            installTestApps = @($testTestAppFile)
        } | ConvertTo-Json -Depth 10

        $result = Get-DependenciesFromInstallApps -DestinationPath $downloadPath

        $result.Apps | Should -Contain (Join-Path $downloadPath "MyApp.app")
        $result.TestApps | Should -Contain (Join-Path $downloadPath "TestApp.app")
        Test-Path (Join-Path $downloadPath "MyApp.app") | Should -BeTrue
        Test-Path (Join-Path $downloadPath "TestApp.app") | Should -BeTrue
    }

    It 'Returns empty array for non-existent local paths' {
        # Use a path that works cross-platform (nested Join-Path for PS5 compatibility)
        $nonExistentPath = Join-Path (Join-Path $downloadPath "NonExistent") "MyApp.app"
        $env:Settings = @{
            installApps = @($nonExistentPath)
            installTestApps = @()
        } | ConvertTo-Json -Depth 10

        $result = Get-DependenciesFromInstallApps -DestinationPath $downloadPath

        $result.Apps | Should -HaveCount 0
    }

    It 'Downloads apps from URLs' {
        $env:Settings = @{
            installApps = @("https://example.com/App1.app")
            installTestApps = @("https://example.com/TestApp1.app")
        } | ConvertTo-Json -Depth 10

        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3))
        } -ModuleName DownloadProjectDependencies

        $result = Get-DependenciesFromInstallApps -DestinationPath $downloadPath

        $result.Apps | Should -HaveCount 1
        $result.TestApps | Should -HaveCount 1
    }

    It 'Replaces secret placeholders in URLs' {
        $env:Settings = @{
            installApps = @('https://example.com/App.app?token=${{ mySecret }}')
            installTestApps = @()
        } | ConvertTo-Json -Depth 10

        # Base64 encode the secret value
        $secretValue = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("secret-token-value"))
        $env:Secrets = @{
            mySecret = $secretValue
        } | ConvertTo-Json -Depth 10

        $script:capturedUrl = $null
        Mock Invoke-WebRequest {
            param($Method, $UseBasicParsing, $Uri, $OutFile)
            $script:capturedUrl = $Uri
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3))
        } -ModuleName DownloadProjectDependencies

        $null = Get-DependenciesFromInstallApps -DestinationPath $downloadPath

        $script:capturedUrl | Should -Be "https://example.com/App.app?token=secret-token-value"
    }

    It 'Throws error for unknown secret reference' {
        $env:Settings = @{
            installApps = @('https://example.com/App.app?token=${{ unknownSecret }}')
            installTestApps = @()
        } | ConvertTo-Json -Depth 10

        $env:Secrets = @{} | ConvertTo-Json -Depth 10

        { Get-DependenciesFromInstallApps -DestinationPath $downloadPath } | Should -Throw "*unknown secret 'unknownSecret'*"
    }
}
