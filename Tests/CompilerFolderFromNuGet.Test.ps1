Get-Module CompilerFolderFromNuGet | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\.Modules\CompilerFolderFromNuGet.psm1' -Resolve) -Force -DisableNameChecking

Describe "CompilerFolderFromNuGet Module Tests" {

    Describe 'Select-BcSymbolsVersion' {
        # Artifact versions and symbol package versions agree on major.minor.build only.
        # Verified against every sandbox artifact version from 26.0 onwards.
        It 'picks the version sharing major.minor.build' {
            $versions = @('28.4.53241.52000', '28.4.53241.53504', '28.3.52162.52273')
            Select-BcSymbolsVersion -Versions $versions -ArtifactVersion '28.4.53241.53312' | Should -Be '28.4.53241.53504'
        }

        It 'picks the highest revision, comparing numerically not as strings' {
            $versions = @('28.4.53241.9', '28.4.53241.100', '28.4.53241.99')
            Select-BcSymbolsVersion -Versions $versions -ArtifactVersion '28.4.53241.1' | Should -Be '28.4.53241.100'
        }

        It 'matches when the symbol revision is lower than the artifact revision' {
            # 28.3.52162.52273 serves artifact 28.3.52162.53506
            $versions = @('28.3.52162.52273')
            Select-BcSymbolsVersion -Versions $versions -ArtifactVersion '28.3.52162.53506' | Should -Be '28.3.52162.52273'
        }

        It 'returns null when no version shares the build' {
            Select-BcSymbolsVersion -Versions @('28.4.53241.1') -ArtifactVersion '27.0.38460.53486' | Should -BeNullOrEmpty
        }

        It 'returns null for an empty feed' {
            Select-BcSymbolsVersion -Versions @() -ArtifactVersion '28.4.53241.1' | Should -BeNullOrEmpty
        }

        It 'does not match a build that merely starts with the same digits' {
            # 28.4.5324 must not match 28.4.53241
            Select-BcSymbolsVersion -Versions @('28.4.532410.1') -ArtifactVersion '28.4.53241.1' | Should -BeNullOrEmpty
        }

        It 'throws on a malformed artifact version' {
            { Select-BcSymbolsVersion -Versions @('1.2.3.4') -ArtifactVersion '28.4' } | Should -Throw
        }
    }

    Describe 'Select-ALCompilerVersion' {
        BeforeAll {
            # Pester 5 runs the Describe body during discovery, so shared fixtures must
            # be created in BeforeAll and referenced through the script scope.
            $script:versions = @('16.2.28.57946', '17.0.30.1', '17.0.34.45391', '18.0.39.10160-beta')
        }

        It 'maps Business Central major to AL major (BC - 11)' {
            Select-ALCompilerVersion -Versions $script:versions -BcVersion '28.4.53241.53504' -Policy 'default' | Should -Be '17.0.34.45391'
            Select-ALCompilerVersion -Versions $script:versions -BcVersion '27.5.46862.47359' -Policy 'default' | Should -Be '16.2.28.57946'
        }

        It 'falls back to a prerelease when the matching major has no stable release' {
            # BC 29 maps to AL 18, which is beta-only while the version is in preview
            Select-ALCompilerVersion -Versions $script:versions -BcVersion '29.0.53450.0' -Policy 'default' | Should -Be '18.0.39.10160-beta'
        }

        It 'ignores prereleases for the latest policy' {
            Select-ALCompilerVersion -Versions $script:versions -BcVersion '29.0.53450.0' -Policy 'latest' | Should -Be '17.0.34.45391'
        }

        It 'includes prereleases for the preview policy' {
            Select-ALCompilerVersion -Versions $script:versions -BcVersion '27.5.46862.47359' -Policy 'preview' | Should -Be '18.0.39.10160-beta'
        }

        It 'throws when no compiler exists for the matching major' {
            { Select-ALCompilerVersion -Versions @('16.2.28.57946') -BcVersion '99.0.0.0' -Policy 'default' } | Should -Throw
        }
    }

    Describe 'Select-NuGetVersionInRange' {
        BeforeAll {
            $script:versions = @('28.3.0.0', '28.4.0.0', '28.4.53241.53504', '28.5.0.0')
        }

        It 'honours an inclusive lower and exclusive upper bound' {
            Select-NuGetVersionInRange -Versions $script:versions -Range '[28.4.0.0,28.5.0.0)' | Should -Be '28.4.53241.53504'
        }

        It 'honours an inclusive upper bound' {
            Select-NuGetVersionInRange -Versions $script:versions -Range '[28.4.0.0,28.5.0.0]' | Should -Be '28.5.0.0'
        }

        It 'treats a bare version as a minimum' {
            Select-NuGetVersionInRange -Versions $script:versions -Range '28.4.0.0' | Should -Be '28.5.0.0'
        }

        It 'returns null when nothing satisfies the range' {
            Select-NuGetVersionInRange -Versions $script:versions -Range '[29.0.0.0,30.0.0.0)' | Should -BeNullOrEmpty
        }

        It 'ignores prereleases' {
            Select-NuGetVersionInRange -Versions @('28.4.0.0-beta') -Range '[28.0.0.0,29.0.0.0)' | Should -BeNullOrEmpty
        }
    }

    Describe 'Get-BcApplicationSymbolsPackageName' {
        It 'uses no country suffix for w1' {
            Get-BcApplicationSymbolsPackageName -Country 'w1' | Should -Be 'Microsoft.Application.symbols'
        }

        It 'uppercases the country for every other localization' {
            Get-BcApplicationSymbolsPackageName -Country 'us' | Should -Be 'Microsoft.Application.US.symbols'
            Get-BcApplicationSymbolsPackageName -Country 'dk' | Should -Be 'Microsoft.Application.DK.symbols'
        }
    }

    Describe 'Test-SymbolsFromNuGetSupported' {
        BeforeAll {
            $script:projectFolder = Join-Path ([System.IO.Path]::GetTempPath()) "symbolsFromNuGetTest_$([GUID]::NewGuid())"
            New-Item (Join-Path $script:projectFolder 'CloudApp') -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $script:projectFolder 'OnPremApp') -ItemType Directory -Force | Out-Null
            '{ "name": "CloudApp", "target": "Cloud" }' | Set-Content (Join-Path $script:projectFolder 'CloudApp/app.json') -Encoding UTF8
            '{ "name": "OnPremApp", "target": "OnPrem" }' | Set-Content (Join-Path $script:projectFolder 'OnPremApp/app.json') -Encoding UTF8
        }

        AfterAll {
            Remove-Item $script:projectFolder -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'accepts an app targeting Cloud' {
            $settings = @{ appFolders = @('CloudApp'); testFolders = @(); bcptTestFolders = @(); vsixFile = '' }
            { Test-SymbolsFromNuGetSupported -Settings $settings -ProjectFolder $script:projectFolder } | Should -Not -Throw
        }

        It 'rejects an app targeting OnPrem, which may use .NET interop' {
            $settings = @{ appFolders = @('OnPremApp'); testFolders = @(); bcptTestFolders = @(); vsixFile = '' }
            { Test-SymbolsFromNuGetSupported -Settings $settings -ProjectFolder $script:projectFolder } | Should -Throw -ExpectedMessage "*OnPrem*"
        }

        It 'rejects a vsixFile download URL' {
            $settings = @{ appFolders = @('CloudApp'); testFolders = @(); bcptTestFolders = @(); vsixFile = 'https://example.com/al.vsix' }
            { Test-SymbolsFromNuGetSupported -Settings $settings -ProjectFolder $script:projectFolder } | Should -Throw -ExpectedMessage "*vsixFile*"
        }

        It 'accepts the vsixFile policy keywords' {
            foreach ($policy in @('', 'default', 'latest', 'preview')) {
                $settings = @{ appFolders = @('CloudApp'); testFolders = @(); bcptTestFolders = @(); vsixFile = $policy }
                { Test-SymbolsFromNuGetSupported -Settings $settings -ProjectFolder $script:projectFolder } | Should -Not -Throw
            }
        }

        It 'ignores app folders with no app.json' {
            $settings = @{ appFolders = @('DoesNotExist'); testFolders = @(); bcptTestFolders = @(); vsixFile = '' }
            { Test-SymbolsFromNuGetSupported -Settings $settings -ProjectFolder $script:projectFolder } | Should -Not -Throw
        }
    }

    Describe 'Get-BcSymbolsPackageNameForDependency' {
        It 'removes spaces from the app name and appends the app id' {
            Get-BcSymbolsPackageNameForDependency -Name 'Library Assert' -Id 'dd0be2ea-f733-4d65-bb34-a28f4624fb14' -Country 'us' |
                Should -Be 'Microsoft.LibraryAssert.US.symbols.dd0be2ea-f733-4d65-bb34-a28f4624fb14'
        }

        It 'omits the country segment for w1, like the application package' {
            Get-BcSymbolsPackageNameForDependency -Name 'Test Runner' -Id '23de40a6-dfe8-4f80-80db-d70f83ce8caf' -Country 'w1' |
                Should -Be 'Microsoft.TestRunner.symbols.23de40a6-dfe8-4f80-80db-d70f83ce8caf'
        }

        It 'handles names with punctuation, verified against the feed' {
            Get-BcSymbolsPackageNameForDependency -Name 'Error Messages with Recommendations' -Id '64c9d5e2-7744-4866-bc0e-5ebc2898e651' -Country 'us' |
                Should -Be 'Microsoft.ErrorMessageswithRecommendations.US.symbols.64c9d5e2-7744-4866-bc0e-5ebc2898e651'
        }
    }

    Describe 'Get-MicrosoftDependencyPackages' {
        BeforeAll {
            $script:depFolder = Join-Path ([System.IO.Path]::GetTempPath()) "msdeps_$([GUID]::NewGuid())"
            New-Item (Join-Path $script:depFolder 'TestApp') -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $script:depFolder 'PlainApp') -ItemType Directory -Force | Out-Null
            @'
{ "name": "TestApp", "dependencies": [
    { "id": "dd0be2ea-f733-4d65-bb34-a28f4624fb14", "name": "Library Assert", "publisher": "Microsoft", "version": "28.0.0.0" },
    { "id": "23de40a6-dfe8-4f80-80db-d70f83ce8caf", "name": "Test Runner", "publisher": "Microsoft", "version": "28.0.0.0" },
    { "id": "99999999-9999-9999-9999-999999999999", "name": "Some Partner App", "publisher": "Contoso", "version": "1.0.0.0" }
] }
'@ | Set-Content (Join-Path $script:depFolder 'TestApp/app.json') -Encoding UTF8
            '{ "name": "PlainApp" }' | Set-Content (Join-Path $script:depFolder 'PlainApp/app.json') -Encoding UTF8
        }

        AfterAll { Remove-Item $script:depFolder -Recurse -Force -ErrorAction SilentlyContinue }

        It 'returns a package for every Microsoft dependency' {
            $packages = @(Get-MicrosoftDependencyPackages -AppFolders @((Join-Path $script:depFolder 'TestApp')) -Country 'us')
            $packages.Count | Should -Be 2
            $packages | Should -Contain 'Microsoft.LibraryAssert.US.symbols.dd0be2ea-f733-4d65-bb34-a28f4624fb14'
            $packages | Should -Contain 'Microsoft.TestRunner.US.symbols.23de40a6-dfe8-4f80-80db-d70f83ce8caf'
        }

        It 'ignores non-Microsoft dependencies, which AL-Go resolves separately' {
            $packages = @(Get-MicrosoftDependencyPackages -AppFolders @((Join-Path $script:depFolder 'TestApp')) -Country 'us')
            ($packages -join ' ') | Should -Not -Match 'Contoso|Some'
        }

        It 'returns nothing for an app with no dependencies' {
            @(Get-MicrosoftDependencyPackages -AppFolders @((Join-Path $script:depFolder 'PlainApp')) -Country 'us').Count | Should -Be 0
        }

        It 'deduplicates across app folders' {
            $folders = @((Join-Path $script:depFolder 'TestApp'), (Join-Path $script:depFolder 'TestApp'))
            @(Get-MicrosoftDependencyPackages -AppFolders $folders -Country 'us').Count | Should -Be 2
        }

        It 'tolerates a folder with no app.json' {
            @(Get-MicrosoftDependencyPackages -AppFolders @((Join-Path $script:depFolder 'Nope')) -Country 'us').Count | Should -Be 0
        }
    }
}
