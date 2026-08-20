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

    Describe 'Get-NuGetPackageVersionsInParallel retries' {
        # The public feeds return 503 often enough to fail a build, and a swallowed 503
        # is worse than a slow one: the package looks absent and the build dies later
        # with an unrelated AL1022. These tests serve real responses from a local
        # listener rather than mocking HttpClient.
        BeforeAll {
            function Start-FakeFeed {
                param([scriptblock] $Responder)

                $listener = New-Object System.Net.HttpListener
                $port = 0
                foreach ($candidate in 18800..18899) {
                    try {
                        $listener.Prefixes.Clear()
                        $listener.Prefixes.Add("http://localhost:$candidate/")
                        $listener.Start()
                        $port = $candidate
                        break
                    }
                    catch {
                        # port in use, try the next one
                    }
                }
                if ($port -eq 0) { throw 'No free port for the fake feed' }

                $state = [hashtable]::Synchronized(@{ Calls = 0 })
                $runspace = [runspacefactory]::CreateRunspace()
                $runspace.Open()
                $runspace.SessionStateProxy.SetVariable('listener', $listener)
                $runspace.SessionStateProxy.SetVariable('state', $state)
                $runspace.SessionStateProxy.SetVariable('responder', $Responder)
                $ps = [powershell]::Create()
                $ps.Runspace = $runspace
                $ps.AddScript({
                        while ($listener.IsListening) {
                            try { $context = $listener.GetContext() } catch { break }
                            $state.Calls++
                            $result = & $responder $state.Calls
                            $context.Response.StatusCode = $result.Status
                            if ($result.Body) {
                                $bytes = [System.Text.Encoding]::UTF8.GetBytes($result.Body)
                                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                            }
                            $context.Response.Close()
                        }
                    }) | Out-Null
                $handle = $ps.BeginInvoke()

                return @{
                    Url      = "http://localhost:$port"
                    State    = $state
                    Stop     = {
                        $listener.Stop(); $listener.Close()
                        $ps.Stop(); $ps.Dispose(); $runspace.Dispose()
                    }.GetNewClosure()
                    Handle   = $handle
                }
            }
        }

        It 'retries a 503 and returns the versions once the feed recovers' {
            $feed = Start-FakeFeed -Responder {
                param($call)
                if ($call -lt 3) { return @{ Status = 503 } }
                return @{ Status = 200; Body = '{"versions":["1.0.0","2.0.0"]}' }
            }
            try {
                $result = Get-NuGetPackageVersionsInParallel -FlatContainerUrl $feed.Url -PackageIds @('some.package')
                @($result['some.package']) | Should -Be @('1.0.0', '2.0.0')
                $feed.State.Calls | Should -Be 3
            }
            finally { & $feed.Stop }
        }

        It 'throws rather than reporting a package as absent when the feed keeps failing' {
            $feed = Start-FakeFeed -Responder { param($call) return @{ Status = 503 } }
            try {
                { Get-NuGetPackageVersionsInParallel -FlatContainerUrl $feed.Url -PackageIds @('some.package') } |
                    Should -Throw -ExpectedMessage '*after 4 attempts*'
                $feed.State.Calls | Should -Be 4
            }
            finally { & $feed.Stop }
        }

        It 'treats 404 as absent without retrying' {
            $feed = Start-FakeFeed -Responder { param($call) return @{ Status = 404 } }
            try {
                $result = Get-NuGetPackageVersionsInParallel -FlatContainerUrl $feed.Url -PackageIds @('gone.package')
                @($result['gone.package']).Count | Should -Be 0
                $feed.State.Calls | Should -Be 1
            }
            finally { & $feed.Stop }
        }
    }

    Describe 'Invoke-ScriptBlocksInParallel' {
        # Generic mechanism test, independent of BcContainerHelper: proves the RunspacePool actually
        # runs work concurrently (not just relabeled sequential calls) and that one item throwing
        # does not stop or lose the results of the others.

        It 'runs scriptblocks concurrently rather than one after another' {
            $sleepMs = 800
            $argumentLists = @(@($sleepMs), @($sleepMs), @($sleepMs), @($sleepMs))
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Invoke-ScriptBlocksInParallel -ScriptBlock {
                param($ms) Start-Sleep -Milliseconds $ms; return $ms
            } -ArgumentLists $argumentLists
            $sw.Stop()

            # 4 sequential 800ms sleeps would be >=3200ms; concurrent, it should stay well under that -
            # generous margin for slow CI hosts while still proving overlap.
            $sw.ElapsedMilliseconds | Should -BeLessThan ($sleepMs * 3)
            $results.Count | Should -Be 4
            foreach ($result in $results) {
                $result.Error | Should -BeNullOrEmpty
                @($result.Output) | Should -Be @($sleepMs)
            }
        }

        It 'returns results in the same order as ArgumentLists regardless of completion order' {
            # Item 0 sleeps longest, so it would finish last - the result order must not follow
            # completion order.
            $argumentLists = @(@(1, 300), @(2, 10), @(3, 10))
            $results = Invoke-ScriptBlocksInParallel -ScriptBlock {
                param($value, $delayMs) Start-Sleep -Milliseconds $delayMs; return $value
            } -ArgumentLists $argumentLists

            @($results[0].Output) | Should -Be @(1)
            @($results[1].Output) | Should -Be @(2)
            @($results[2].Output) | Should -Be @(3)
        }

        It 'isolates one throwing scriptblock from the others' {
            $argumentLists = @(@(1), @(2), @(3))
            $results = Invoke-ScriptBlocksInParallel -ScriptBlock {
                param($value)
                if ($value -eq 2) { throw "bang $value" }
                return $value * 10
            } -ArgumentLists $argumentLists

            $results.Count | Should -Be 3
            $results[0].Error | Should -BeNullOrEmpty
            @($results[0].Output) | Should -Be @(10)
            $results[1].Error | Should -Not -BeNullOrEmpty
            $results[1].Error.Exception.Message | Should -BeLike '*bang 2*'
            $results[2].Error | Should -BeNullOrEmpty
            @($results[2].Output) | Should -Be @(30)
        }

        It 'returns an empty array for an empty ArgumentLists' {
            @(Invoke-ScriptBlocksInParallel -ScriptBlock { param($x) $x } -ArgumentLists @()).Count | Should -Be 0
        }
    }

    Describe 'Resolve-NonMicrosoftDependencyFromNuGet' {
        # Direct tests of the per-dependency logic that Install-NonMicrosoftDependenciesFromNuGet
        # dispatches (in-process for a single dependency, or via a worker runspace for 2+). Mock still
        # intercepts Download-BcNuGetPackageToFolder normally here, since this all runs in the test's
        # own runspace - the concurrent dispatch itself is covered separately, above.
        BeforeAll {
            function global:Download-BcNuGetPackageToFolder {
                param($nuGetServerUrl, $nuGetToken, $packageName, $version, $select, $folder, $downloadDependencies, $installedPlatform, $installedApps)
            }
        }

        BeforeEach {
            $global:bcContainerHelperConfig = @{}
            $dependency = [PSCustomObject]@{ id = 'ba1776ba-1198-4b4c-a61e-c4612f1880d5'; publisher = 'Insight Works'; name = 'IWorks Common'; version = '2.18.0.0' }
            $commonArgs = @{
                Dependency               = $dependency
                GitHubPackagesServerUrl = ''
                GitHubPackagesToken     = ''
                SelectMode              = 'Latest'
                PackageCachePath        = $TestDrive
                InstalledPlatform       = [System.Version]'26.5.38752.53540'
                InstalledApps           = @([PSCustomObject]@{ Publisher = ''; Name = 'Application'; id = ''; Version = [System.Version]'26.5.38752.53540' })
                TrustedNuGetFeeds       = @()
            }
        }

        It 'logs a Resolving message first, then a Downloaded message, on success' {
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { return @(@{ Name = 'IWorks Common'; Version = '2.19.0.0' }) }

            $result = Resolve-NonMicrosoftDependencyFromNuGet @commonArgs

            $result.DependencyId | Should -Be $dependency.id
            $result.Log.Count | Should -Be 2
            $result.Log[0].Level | Should -Be 'Host'
            $result.Log[0].Message | Should -BeLike '*Resolving non-Microsoft dependency*IWorks Common*'
            $result.Log[1].Level | Should -Be 'Host'
            $result.Log[1].Message | Should -BeLike '*Downloaded*IWorks Common*'
        }

        It 'logs a Resolving message first, then a Warning, when nothing is found' {
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { return @() }

            $result = Resolve-NonMicrosoftDependencyFromNuGet @commonArgs

            $result.Log.Count | Should -Be 2
            $result.Log[0].Level | Should -Be 'Host'
            $result.Log[1].Level | Should -Be 'Warning'
            $result.Log[1].Message | Should -BeLike '*Could not find a NuGet package*'
        }

        It 'logs a Resolving message first, then a Warning, when the download throws' {
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { throw "network error" }

            $result = Resolve-NonMicrosoftDependencyFromNuGet @commonArgs

            $result.Log.Count | Should -Be 2
            $result.Log[0].Level | Should -Be 'Host'
            $result.Log[1].Level | Should -Be 'Warning'
            $result.Log[1].Message | Should -BeLike '*Failed to resolve dependency*network error*'
        }

        It 'sets bcContainerHelperConfig.TrustedNuGetFeeds before downloading, since a worker runspace has its own copy' {
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }
            $commonArgs.TrustedNuGetFeeds = @(@{ url = 'https://example.com/index.json'; token = '' })

            Resolve-NonMicrosoftDependencyFromNuGet @commonArgs | Out-Null

            $bcContainerHelperConfig.TrustedNuGetFeeds.Count | Should -Be 1
            $bcContainerHelperConfig.TrustedNuGetFeeds[0].url | Should -Be 'https://example.com/index.json'
        }
    }

    Describe 'Install-NonMicrosoftDependenciesFromNuGet' {
        BeforeAll {
            function global:OutputWarning { param($message) Write-Host "::warning::$message" }
            function global:GetAccessToken { param($token, $permissions, $repositories) return "scoped:$token" }
            function global:Download-BcNuGetPackageToFolder {
                param($nuGetServerUrl, $nuGetToken, $packageName, $version, $select, $folder, $downloadDependencies, $installedPlatform, $installedApps)
            }
            function script:New-TestAppJson {
                param($Folder, $Id, $Dependencies = @())
                New-Item -Path $Folder -ItemType Directory -Force | Out-Null
                @{ id = $Id; name = 'App'; publisher = 'Test'; version = '1.0.0.0'; dependencies = $Dependencies } |
                    ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $Folder 'app.json') -Encoding UTF8
            }
        }

        BeforeEach {
            $global:bcContainerHelperConfig = @{}
            $testFolder = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            $artifactUrl = 'https://bcartifacts.azureedge.net/sandbox/26.5.38752.53540/w1'
        }

        It 'skips Microsoft dependencies' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = '437dbf0e-84ff-417a-965d-ed2bb9650972'; publisher = 'Microsoft'; name = 'System Application'; version = '26.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl

            Should -Invoke -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder -Times 0
        }

        It 'skips dependencies that match an app being compiled in this workspace' {
            $appId = [Guid]::NewGuid().ToString()
            $depFolder = Join-Path $testFolder 'Dep'
            New-TestAppJson -Folder $depFolder -Id $appId

            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = $appId; publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder, $depFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl

            Should -Invoke -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder -Times 0
        }

        It 'resolves a genuine third-party dependency once, even if declared in multiple app.json files' {
            $depId = 'ba1776ba-1198-4b4c-a61e-c4612f1880d5'
            $dependency = @{ id = $depId; publisher = 'Insight Works'; name = 'IWorks Common'; version = '2.18.0.0' }

            $appFolder1 = Join-Path $testFolder 'App1'
            New-TestAppJson -Folder $appFolder1 -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dependency)
            $appFolder2 = Join-Path $testFolder 'App2'
            New-TestAppJson -Folder $appFolder2 -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dependency)

            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { return @('Insight Works_IWorks Common_2.19.0.0.app') }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder1, $appFolder2) -PackageCachePath $testFolder -Settings @{ nuGetFeedSelectMode = 'LatestMatching' } -ArtifactUrl $artifactUrl

            Should -Invoke -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder -Times 1 -Exactly -ParameterFilter {
                $packageName -eq $depId -and $version -eq '2.18.0.0' -and $select -eq 'LatestMatching' -and $folder -eq $testFolder
            }
        }

        It 'passes the artifact BC version as installedPlatform and as the installed Application version, so LatestMatching rejects incompatible candidates' {
            $depId = [Guid]::NewGuid().ToString()
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = $depId; publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl 'https://bcartifacts.azureedge.net/sandbox/26.5.38752.53540/w1'

            Should -Invoke -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder -Times 1 -Exactly -ParameterFilter {
                "$installedPlatform" -eq '26.5.38752.53540' -and
                    @($installedApps).Count -eq 1 -and
                    $installedApps[0].Name -eq 'Application' -and
                    "$($installedApps[0].Version)" -eq '26.5.38752.53540'
            }
        }

        It 'throws a clear error for a malformed artifact URL instead of resolving dependencies blind' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )

            { Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl 'not-a-url' } | Should -Throw -ExpectedMessage "*Invalid artifact URL*"
        }

        It 'builds installedApps entries with every property Download-BcNuGetPackageToFolder dot-references, since it runs under this module''s inherited Set-StrictMode -Version 2.0' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            $capturedInstalledApps = $null
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder {
                Set-Variable -Name capturedInstalledApps -Value $installedApps -Scope 2
            }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl

            Set-StrictMode -Version 2.0
            try {
                { $capturedInstalledApps[0].id } | Should -Not -Throw
                { $capturedInstalledApps[0].Publisher } | Should -Not -Throw
                { $capturedInstalledApps[0].Name } | Should -Not -Throw
                { $capturedInstalledApps[0].Version } | Should -Not -Throw
            }
            finally {
                Set-StrictMode -Off
            }
        }

        It 'sets TrustedNuGetFeeds from settings.trustedNuGetFeeds and the AppSourceSymbols feed when trustMicrosoftNuGetFeeds is set' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString())
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            $settings = @{
                trustedNuGetFeeds       = @(@{ url = 'https://example.com/index.json'; token = '' })
                trustMicrosoftNuGetFeeds = $true
            }
            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings $settings -ArtifactUrl $artifactUrl

            $bcContainerHelperConfig.TrustedNuGetFeeds.Count | Should -Be 2
            $bcContainerHelperConfig.TrustedNuGetFeeds[0].url | Should -Be 'https://example.com/index.json'
            $bcContainerHelperConfig.TrustedNuGetFeeds[1].url | Should -Be 'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json'
        }

        It 'pre-populates Token/Patterns/Fingerprints on every trusted feed so BcContainerHelper''s lazy Add-Member guard is a no-op' {
            # Find-BcNuGetPackage.ps1 (BcContainerHelper) lazily Add-Members these properties onto
            # each feed object on first use, guarded by a check-then-act pattern that is not
            # thread-safe when the same feed object is shared by reference across the parallel
            # worker runspaces this module dispatches (AddArgument on a local RunspacePool passes
            # by reference, not by clone). Pre-populating them here - one PSCustomObject feed built
            # by this module, one Hashtable feed from settings, since both shapes reach
            # $trustedFeeds in production - means that guard always finds the property already
            # present and never calls Add-Member at all, so two workers racing it can no longer
            # throw "Cannot add a member with the name 'Patterns' because a member with that name
            # already exists."
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString())
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            $settings = @{
                trustedNuGetFeeds        = @(@{ url = 'https://example.com/index.json'; token = '' })
                trustMicrosoftNuGetFeeds = $true
            }
            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings $settings -ArtifactUrl $artifactUrl

            $bcContainerHelperConfig.TrustedNuGetFeeds.Count | Should -Be 2
            foreach ($feed in $bcContainerHelperConfig.TrustedNuGetFeeds) {
                $feed.PSObject.Properties.Name | Should -Contain 'Token'
                $feed.PSObject.Properties.Name | Should -Contain 'Patterns'
                $feed.PSObject.Properties.Name | Should -Contain 'Fingerprints'
            }
        }

        It 'omits the AppSourceSymbols feed when trustMicrosoftNuGetFeeds is false' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString())
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{ trustMicrosoftNuGetFeeds = $false } -ArtifactUrl $artifactUrl

            $bcContainerHelperConfig.TrustedNuGetFeeds.Count | Should -Be 0
        }

        It 'derives the GitHub Packages server URL and a scoped token from gitHubPackagesContext' {
            $depId = [Guid]::NewGuid().ToString()
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = $depId; publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { }

            $gitHubPackagesContext = @{ serverUrl = 'https://nuget.pkg.github.com/contoso/index.json'; token = 'raw-token' } | ConvertTo-Json -Compress
            Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -GitHubPackagesContext $gitHubPackagesContext -ArtifactUrl $artifactUrl

            Should -Invoke -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder -Times 1 -Exactly -ParameterFilter {
                $nuGetServerUrl -eq 'https://nuget.pkg.github.com/contoso/index.json' -and $nuGetToken -eq 'scoped:raw-token'
            }
        }

        It 'warns but does not throw when a dependency cannot be found on any feed' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { return @() }
            Mock -ModuleName CompilerFolderFromNuGet OutputWarning { }

            { Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl } | Should -Not -Throw

            Should -Invoke -ModuleName CompilerFolderFromNuGet OutputWarning -Times 1 -Exactly -ParameterFilter { $message -like '*Could not find a NuGet package*' }
        }

        It 'warns but does not throw when the feed lookup itself throws' {
            $appFolder = Join-Path $testFolder 'App'
            New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @(
                @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep'; version = '1.0.0.0' }
            )
            Mock -ModuleName CompilerFolderFromNuGet Download-BcNuGetPackageToFolder { throw "network error" }
            Mock -ModuleName CompilerFolderFromNuGet OutputWarning { }

            { Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl } | Should -Not -Throw

            Should -Invoke -ModuleName CompilerFolderFromNuGet OutputWarning -Times 1 -Exactly -ParameterFilter { $message -like '*Failed to resolve dependency*' }
        }

        Context 'with 2 or more independent dependencies' {
            # A worker runspace re-imports this module and BcContainerHelper fresh, so
            # Download-BcNuGetPackageToFolder is not visible to Mock from here (a different runspace,
            # a different module instance) - these tests mock the dispatch call itself instead
            # (Invoke-ScriptBlocksInParallel, called directly by Install-NonMicrosoftDependenciesFromNuGet
            # in this same runspace) and assert on what gets dispatched and how results get replayed.
            # Genuine concurrency and per-item error isolation are covered generically, and without any
            # BcContainerHelper involvement, by the 'Invoke-ScriptBlocksInParallel' Describe block above.

            BeforeEach {
                # Only referenced, never dot-sourced for real here, since Invoke-ScriptBlocksInParallel
                # itself is mocked in every test in this Context.
                $previousBcContainerHelperPath = $env:BcContainerHelperPath
                $env:BcContainerHelperPath = Join-Path $testFolder 'fake-BcContainerHelper.ps1'
            }

            AfterEach {
                $env:BcContainerHelperPath = $previousBcContainerHelperPath
            }

            It 'dispatches one argument set per independent dependency to Invoke-ScriptBlocksInParallel' {
                $dep1 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Insight Works'; name = 'IWorks Common'; version = '2.18.0.0' }
                $dep2 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Binary Stream'; name = 'MEM'; version = '1.0.0.0' }
                $appFolder = Join-Path $testFolder 'App'
                New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dep1, $dep2)

                Mock -ModuleName CompilerFolderFromNuGet Invoke-ScriptBlocksInParallel { return @() }

                Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl

                Should -Invoke -ModuleName CompilerFolderFromNuGet Invoke-ScriptBlocksInParallel -Times 1 -Exactly -ParameterFilter {
                    $dependencyIds = @($ArgumentLists | ForEach-Object { $_[2].id })
                    $packageCachePaths = @($ArgumentLists | ForEach-Object { $_[6] })
                    $ArgumentLists.Count -eq 2 -and
                        $dependencyIds -contains $dep1.id -and
                        $dependencyIds -contains $dep2.id -and
                        (@($packageCachePaths | Where-Object { $_ -ne $testFolder })).Count -eq 0
                }
            }

            It 'replays each dependency''s Log through Write-Host / OutputWarning once results are back' {
                $dep1 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Insight Works'; name = 'IWorks Common'; version = '2.18.0.0' }
                $dep2 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Binary Stream'; name = 'MEM'; version = '1.0.0.0' }
                $appFolder = Join-Path $testFolder 'App'
                New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dep1, $dep2)

                Mock -ModuleName CompilerFolderFromNuGet OutputWarning { }
                Mock -ModuleName CompilerFolderFromNuGet Invoke-ScriptBlocksInParallel {
                    return @(
                        [PSCustomObject]@{ Error = $null; Output = @([PSCustomObject]@{ DependencyId = $dep1.id; Log = @(@{ Level = 'Host'; Message = 'Resolving dep1' }, @{ Level = 'Host'; Message = 'Downloaded dep1' }) }) }
                        [PSCustomObject]@{ Error = $null; Output = @([PSCustomObject]@{ DependencyId = $dep2.id; Log = @(@{ Level = 'Host'; Message = 'Resolving dep2' }, @{ Level = 'Warning'; Message = 'Could not find dep2' }) }) }
                    )
                }

                Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl

                Should -Invoke -ModuleName CompilerFolderFromNuGet OutputWarning -Times 1 -Exactly -ParameterFilter { $message -eq 'Could not find dep2' }
            }

            It 'warns for a dependency whose worker runspace itself failed, without losing the others'' results' {
                $dep1 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Insight Works'; name = 'IWorks Common'; version = '2.18.0.0' }
                $dep2 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Binary Stream'; name = 'MEM'; version = '1.0.0.0' }
                $appFolder = Join-Path $testFolder 'App'
                New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dep1, $dep2)

                Mock -ModuleName CompilerFolderFromNuGet OutputWarning { }
                Mock -ModuleName CompilerFolderFromNuGet Invoke-ScriptBlocksInParallel {
                    return @(
                        [PSCustomObject]@{ Error = (New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList ([Exception]::new('runspace exploded')), 'id', 'NotSpecified', $null); Output = @() }
                        [PSCustomObject]@{ Error = $null; Output = @([PSCustomObject]@{ DependencyId = $dep2.id; Log = @(@{ Level = 'Host'; Message = 'Resolving dep2' }, @{ Level = 'Host'; Message = 'Downloaded dep2' }) }) }
                    )
                }

                { Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl } | Should -Not -Throw

                Should -Invoke -ModuleName CompilerFolderFromNuGet OutputWarning -Times 1 -Exactly -ParameterFilter {
                    $message -like "*Failed to resolve dependency*$($dep1.publisher)*" -and $message -like '*runspace exploded*'
                }
            }

            It 'a real worker runspace can actually find Resolve-NonMicrosoftDependencyFromNuGet after importing this module by its real path' {
                # None of the other tests in this Context exercise the real worker runspace at all
                # (Invoke-ScriptBlocksInParallel is mocked in every one of them) - this is the one
                # test that does not mock it, so it is the only test that would have caught four
                # separate real-world failures of the module-path-resolution mechanism (three
                # different ways $ModulePath could end up wrong going into the worker, and the
                # actual root cause: the worker's own ". $BcContainerHelperPath" dot-source merges
                # BcContainerHelper.ps1's own top-level variable assignments into the worker's
                # scope - not a child scope - and BcContainerHelper.ps1 apparently assigns a
                # same-named local variable, silently overwriting the worker's own $ModulePath
                # parameter after it already had the right value). The stub below reproduces that
                # exact collision - a real BcContainerHelper.ps1 is not needed to catch this, only
                # something that assigns $ModulePath the way it does.
                $fakeBcContainerHelperPath = Join-Path $testFolder 'fake-BcContainerHelper.ps1'
                'param([switch] $Silent)
$ModulePath = "C:\this-would-be-BcContainerHelpers-own-internal-path.psd1"' | Set-Content -Path $fakeBcContainerHelperPath -Encoding UTF8
                $env:BcContainerHelperPath = $fakeBcContainerHelperPath

                $dep1 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep1'; version = '1.0.0.0' }
                $dep2 = @{ id = [Guid]::NewGuid().ToString(); publisher = 'Contoso'; name = 'Dep2'; version = '1.0.0.0' }
                $appFolder = Join-Path $testFolder 'App'
                New-TestAppJson -Folder $appFolder -Id ([Guid]::NewGuid().ToString()) -Dependencies @($dep1, $dep2)

                $realModulePath = (Get-Module CompilerFolderFromNuGet).Path
                Mock -ModuleName CompilerFolderFromNuGet OutputWarning { }

                { Install-NonMicrosoftDependenciesFromNuGet -AppFolders @($appFolder) -PackageCachePath $testFolder -Settings @{} -ArtifactUrl $artifactUrl -ModulePath $realModulePath } | Should -Not -Throw

                Should -Invoke -ModuleName CompilerFolderFromNuGet OutputWarning -ParameterFilter {
                    $message -like '*is not available after*' -or $message -like '*is not recognized*'
                } -Times 0
            }
        }
    }
}
