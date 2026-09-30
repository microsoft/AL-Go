Describe "AL-Go-Helper tests" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
    }

    It 'CheckAndCreateProjectFolder' {
        Mock Write-Host { }

        Push-Location

        # Create a temp folder with the PTE template files
        $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item $tempName -ItemType Directory | Out-Null
        $repoName = "Per Tenant Extension"
        $pteTemplateFiles = Join-Path $PSScriptRoot "../Templates/$repoName" -Resolve
        Copy-Item -Path $pteTemplateFiles -Destination $tempName -Recurse -Force
        $repoFolder = Join-Path $tempName $repoName
        $repoFolder | Should -Exist
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist
        Set-Location $repoFolder

        # Test without project name - should not change the repo
        CheckAndCreateProjectFolder -project '.'
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist
        CheckAndCreateProjectFolder -project ''
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist

        # Create an app in an empty repo
        New-Item -Path 'App' -ItemType Directory | Out-Null
        Set-Content -Path 'App/app.json' -Value '{"id": "123"}'

        # Creating a project in a single project repo with apps should fail
        { CheckAndCreateProjectFolder -project 'project1' } | Should -Throw

        # Remove app folder and try again
        Remove-Item -Path 'App' -Recurse -Force

        # Creating a project in a single project repo without apps should succeed
        { CheckAndCreateProjectFolder -project 'project1' } | Should -Not -Throw

        # .AL-Go folder should be moved to the project folder
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Not -Exist
        Join-Path '.' '.AL-Go/settings.json' | Should -Exist
        'project1.code-workspace' | Should -Exist

        # If repo is setup for multiple projects, using an empty project name should fail
        Set-Location $repoFolder
        { CheckAndCreateProjectFolder -project '' } | Should -Throw

        # Creating a second project should not fail
        { CheckAndCreateProjectFolder -project 'project2' } | Should -Not -Throw
        Join-Path $repoFolder 'project2/.AL-Go/settings.json' | Should -Exist
        Join-Path $repoFolder 'project2/project2.code-workspace' | Should -Exist

        # Clean up
        Pop-Location
        Remove-Item -Path $tempName -Recurse -Force
    }

    It 'GetFoldersFromAllProjects' {
        Mock Write-Host { }
        Mock Out-Host { }

        $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $githubFolder = Join-Path $tempName ".github"
        $projects = [ordered]@{
            "A" = @(
                "app1",
                "app2",
                "app1.test"
            )
            "projects/B" = @(
                "../../src/app3"
                "../../src/app4"
            )
            "projects/C" = @(
                "../../src/app3"
                "../../A/app1"
            )
        }
        foreach($project in $projects.Keys) {
            $projectFolder = Join-Path $tempName $project
            Write-Host $projectFolder
            New-Item $projectFolder -ItemType Directory | Out-Null
            $projectSettings = @{
                "appFolders" = @($projects[$project] | Where-Object { $_ -notlike '*.test' })
                "testFolders" = @($projects[$project] | Where-Object { $_ -like '*.test' })
            }
            $algoFolder = Join-Path $projectFolder $ALGoFolderName
            New-Item $algoFolder -ItemType Directory | Out-Null
            Set-Content -Path (Join-Path $algoFolder "settings.json") -value (ConvertTo-Json -InputObject $projectSettings)
            foreach($folder in $projects[$project]) {
                $folderPath = Join-Path $projectFolder $folder
                if (!(Test-Path $folderPath)) {
                    New-Item $folderPath -ItemType Directory | Out-Null
                    Set-Content -Path (Join-Path $folderPath "app.json") -Value '{"id": "123"}'
                }
            }
        }

        $repoSettings = @{
            "type" = "PTE"
        }
        New-Item $githubFolder -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $githubFolder "AL-Go-settings.json") -value (ConvertTo-Json -InputObject $repoSettings)

        $folders = GetFoldersFromAllProjects -baseFolder $tempName | Sort-Object
        $folders | Should -be @(
            "A$([System.IO.Path]::DirectorySeparatorChar)app1"
            "A$([System.IO.Path]::DirectorySeparatorChar)app1.test"
            "A$([System.IO.Path]::DirectorySeparatorChar)app2"
            "src$([System.IO.Path]::DirectorySeparatorChar)app3"
            "src$([System.IO.Path]::DirectorySeparatorChar)app4"
        )
    }

    Describe 'Get-VersionNumber' {
        # All tests share the same baseline settings to verify each strategy picks the correct source
        BeforeEach {
            $script:baseSettings = @{
                appBuild = 42
                appRevision = 7
                artifact = "https://bcartifacts.azureedge.net/sandbox/24.5.26928.27583/us"
                repoVersion = "3.1.200"
            }
        }

        It 'Default versioning strategy returns settings appBuild and appRevision' {
            $script:baseSettings.versioningStrategy = 0
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy -1 extracts version from artifact URL' {
            $script:baseSettings.versioningStrategy = -1
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be "24.5"
            $result.BuildNumber | Should -Be 26928
            $result.RevisionNumber | Should -Be 27583
        }

        It 'Strategy 16 uses repoVersion for major.minor' {
            $script:baseSettings.versioningStrategy = 16
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 19 (16+3) gets build number from repoVersion' {
            $script:baseSettings.versioningStrategy = 19
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 200
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 19 with two-digit repoVersion defaults build to 0 with warning' {
            $script:baseSettings.versioningStrategy = 19
            $script:baseSettings.repoVersion = "2.4"
            $result = Get-VersionNumber -Settings $script:baseSettings -WarningVariable warnings -WarningAction SilentlyContinue
            $result.MajorMinorVersion | Should -Be "2.4"
            $result.BuildNumber | Should -Be 0
        }

        It 'Strategy 17 (16+1) uses repoVersion for major.minor but does not override appBuild' {
            $script:baseSettings.versioningStrategy = 17
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 3 without bit 16 behaves like default' {
            $script:baseSettings.versioningStrategy = 3
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 2 passes through date-based appBuild and appRevision' {
            $script:baseSettings.versioningStrategy = 2
            $script:baseSettings.appBuild = 20260313 # Simulate date-based build number
            $script:baseSettings.appRevision = 141450 # Simulate time-based revision number
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 20260313 # Build number should be passed through unchanged
            $result.RevisionNumber | Should -Be 141450 # Revision number should be passed through unchanged
        }

        It 'Strategy 15 passes through max build value' {
            $script:baseSettings.versioningStrategy = 15
            $script:baseSettings.appBuild = [Int32]::MaxValue # Simulate max build number
            $script:baseSettings.appRevision = 100 # Simulate some revision number
            $result = Get-VersionNumber -Settings $script:baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be ([Int32]::MaxValue) # Build number should be passed through unchanged
            $result.RevisionNumber | Should -Be 100 # Revision number should be passed through unchanged
        }
    }

    Describe 'AlTool path resolution' {
        BeforeAll {
            function New-TestAlToolExecutable {
                param([string] $Path)

                New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath $Path -Value 'test executable' -Encoding ASCII
                return $Path
            }
        }

        BeforeEach {
            $script:alToolEnvironmentVariables = @(
                'AlToolPath',
                'GITHUB_ENV',
                'GITHUB_JOB',
                'GITHUB_RUN_ATTEMPT',
                'GITHUB_RUN_ID',
                'RUNNER_TEMP'
            )
            $script:previousAlToolEnvironment = @{}
            foreach ($variableName in $script:alToolEnvironmentVariables) {
                $script:previousAlToolEnvironment[$variableName] = [Environment]::GetEnvironmentVariable($variableName)
            }
            $script:previousPath = $env:PATH

            Remove-Item Env:\AlToolPath -ErrorAction SilentlyContinue
            $env:GITHUB_ENV = Join-Path $TestDrive "$([Guid]::NewGuid()).env"
            $env:RUNNER_TEMP = Join-Path $TestDrive 'runner-temp'
            $env:GITHUB_RUN_ID = '12345'
            $env:GITHUB_RUN_ATTEMPT = '2'
            $env:GITHUB_JOB = 'build'

            $script:expectedToolDirectory = Get-AlToolInstallDirectory
            $script:expectedAlToolPath = Join-Path $script:expectedToolDirectory (Get-AlToolExecutableName)
            if (Test-Path -LiteralPath $script:expectedToolDirectory) {
                Remove-Item -LiteralPath $script:expectedToolDirectory -Recurse -Force
            }
            $script:fakeAlToolPath = Join-Path $TestDrive (Get-AlToolExecutableName)
            New-TestAlToolExecutable -Path $script:fakeAlToolPath | Out-Null

            Mock Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('1.2.3')
                    StandardError  = [string[]]@()
                    Output         = [string[]]@('1.2.3')
                    ExitCode       = [int] 0
                }
            }
        }

        AfterEach {
            foreach ($variableName in $script:alToolEnvironmentVariables) {
                [Environment]::SetEnvironmentVariable(
                    $variableName,
                    $script:previousAlToolEnvironment[$variableName],
                    [EnvironmentVariableTarget]::Process
                )
            }
            $env:PATH = $script:previousPath
        }

        It 'Reuses and verifies a valid path from the current process without discovery or installation' {
            $env:AlToolPath = $script:fakeAlToolPath

            GetAlToolPath | Should -Be $script:fakeAlToolPath

            Should -Invoke Invoke-AlNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $script:fakeAlToolPath -and $ArgumentList[0] -eq '--version'
            }
            Should -Invoke Invoke-AlNativeCommand -Times 0 -Exactly -ParameterFilter {
                $FilePath -eq 'dotnet'
            }
            Test-Path -LiteralPath $env:GITHUB_ENV | Should -BeFalse
        }

        It 'Reuses the executable from the expected job directory and persists it for later steps' {
            New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null

            $resolvedPath = GetAlToolPath

            $resolvedPath | Should -Be $script:expectedAlToolPath
            $env:AlToolPath | Should -Be $script:expectedAlToolPath
            Get-Content -LiteralPath $env:GITHUB_ENV -Encoding UTF8 |
                Should -Contain "AlToolPath=$script:expectedAlToolPath"
            Should -Invoke Invoke-AlNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $script:expectedAlToolPath -and $ArgumentList[0] -eq '--version'
            }
            Should -Invoke Invoke-AlNativeCommand -Times 0 -Exactly -ParameterFilter {
                $FilePath -eq 'dotnet'
            }
        }

        It 'Recovers from a missing persisted path through the expected job directory' {
            $env:AlToolPath = Join-Path $TestDrive 'missing-al'
            New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null

            GetAlToolPath | Should -Be $script:expectedAlToolPath

            $env:AlToolPath | Should -Be $script:expectedAlToolPath
            Should -Invoke Invoke-AlNativeCommand -Times 0 -Exactly -ParameterFilter {
                $FilePath -eq 'dotnet'
            }
        }

        It 'Installs the prerelease tool into the deterministic job directory only once' {
            $pathBefore = $env:PATH
            Mock Get-Command { throw 'Global AlTool discovery must not run.' } -ParameterFilter { $Name -eq 'al' }
            Mock New-Object { throw 'An installation mutex must not be created.' } -ParameterFilter {
                $TypeName -eq 'System.Threading.Mutex'
            }
            Mock Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@()
                        Output         = [string[]]@()
                        ExitCode       = [int] 0
                    }
                }
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('1.2.3')
                    StandardError  = [string[]]@()
                    Output         = [string[]]@('1.2.3')
                    ExitCode       = [int] 0
                }
            }

            GetAlToolPath | Should -Be $script:expectedAlToolPath
            GetAlToolPath | Should -Be $script:expectedAlToolPath

            Should -Invoke Invoke-AlNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'dotnet' -and
                $ArgumentList.Count -eq 6 -and
                $ArgumentList[0] -eq 'tool' -and
                $ArgumentList[1] -eq 'install' -and
                $ArgumentList[2] -eq 'Microsoft.Dynamics.BusinessCentral.Development.Tools' -and
                $ArgumentList[3] -eq '--prerelease' -and
                $ArgumentList[4] -eq '--tool-path' -and
                $ArgumentList[5] -eq $script:expectedToolDirectory
            }
            Should -Invoke Get-Command -Times 0 -Exactly -ParameterFilter { $Name -eq 'al' }
            Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter {
                $TypeName -eq 'System.Threading.Mutex'
            }
            $env:PATH | Should -Be $pathBefore
        }

        It 'Returns a deterministic sanitized directory for the current GitHub job' {
            $env:GITHUB_RUN_ID = 'run/12'
            $env:GITHUB_RUN_ATTEMPT = 'attempt 3'
            $env:GITHUB_JOB = 'build\matrix:us'

            $firstPath = Get-AlToolInstallDirectory
            $secondPath = Get-AlToolInstallDirectory

            $rawJobIdentity = 'run-run/12-attempt-attempt 3-job-build\matrix:us'
            $expectedIdentity = "$(ConvertTo-AlToolPathSegment -Value $rawJobIdentity)-$(Get-AlToolIdentityHash -Value $rawJobIdentity)"
            $firstPath | Should -Be $secondPath
            $firstPath | Should -Be (
                Join-Path (Join-Path ([System.IO.Path]::GetFullPath($env:RUNNER_TEMP)) 'AL-Go-AlTool') `
                    $expectedIdentity
            )
        }

        It 'Uses different directories for distinct GitHub job identities' {
            $firstPath = Get-AlToolInstallDirectory
            $env:GITHUB_JOB = 'test'
            $secondPath = Get-AlToolInstallDirectory

            $firstPath | Should -Not -Be $secondPath
        }

        It 'Keeps distinct identities separate when their sanitized or truncated text matches' {
            $env:GITHUB_JOB = "$('a' * 80)/one"
            $firstPath = Get-AlToolInstallDirectory
            $env:GITHUB_JOB = "$('a' * 80):one"
            $secondPath = Get-AlToolInstallDirectory

            $firstPath | Should -Not -Be $secondPath
        }

        It 'Uses a deterministic local fallback outside GitHub Actions' {
            Remove-Item Env:\RUNNER_TEMP -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_RUN_ID -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_RUN_ATTEMPT -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_JOB -ErrorAction SilentlyContinue

            $firstPath = Get-AlToolInstallDirectory
            $secondPath = Get-AlToolInstallDirectory

            $firstPath | Should -Be $secondPath
            $firstPath | Should -BeLike (
                Join-Path (Join-Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) 'AL-Go-AlTool') `
                    'local-*'
            )
        }

        It 'Returns the expected executable name for <Platform>' -TestCases @(
            @{ Platform = [System.PlatformID]::Win32NT; ExpectedName = 'al.exe' }
            @{ Platform = [System.PlatformID]::Unix; ExpectedName = 'al' }
        ) {
            param($Platform, $ExpectedName)

            Get-AlToolExecutableName -Platform $Platform | Should -Be $ExpectedName
        }

        It 'Removes only the exact incomplete job directory before reinstalling' {
            New-Item -Path $script:expectedToolDirectory -ItemType Directory -Force | Out-Null
            $staleFile = Join-Path $script:expectedToolDirectory 'partial-install.txt'
            Set-Content -LiteralPath $staleFile -Value 'partial' -Encoding ASCII
            $neighborDirectory = Join-Path (Split-Path $script:expectedToolDirectory -Parent) 'neighbor-job'
            $neighborFile = Join-Path $neighborDirectory 'keep.txt'
            New-Item -Path $neighborDirectory -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $neighborFile -Value 'keep' -Encoding ASCII

            Mock Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    Test-Path -LiteralPath $staleFile | Should -BeFalse
                    Test-Path -LiteralPath $neighborFile | Should -BeTrue
                    New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@()
                        Output         = [string[]]@()
                        ExitCode       = [int] 0
                    }
                }
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@('1.2.3')
                    StandardError  = [string[]]@()
                    Output         = [string[]]@('1.2.3')
                    ExitCode       = [int] 0
                }
            }

            GetAlToolPath | Should -Be $script:expectedAlToolPath

            Test-Path -LiteralPath $staleFile | Should -BeFalse
            Test-Path -LiteralPath $neighborFile | Should -BeTrue
        }

        It 'Reports a failed job-scoped installation with its output' {
            Mock Invoke-AlNativeCommand {
                if ($FilePath -eq 'dotnet') {
                    return [PSCustomObject]@{
                        StandardOutput = [string[]]@()
                        StandardError  = [string[]]@('install stderr')
                        Output         = [string[]]@('install stderr')
                        ExitCode       = [int] 17
                    }
                }
            }

            { GetAlToolPath } |
                Should -Throw "*dotnet tool install exited with code 17*install stderr*"
        }

        It 'Fails when the installation command does not produce the expected executable' {
            Mock Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@()
                    Output         = [string[]]@()
                    ExitCode       = [int] 0
                }
            }

            { GetAlToolPath } |
                Should -Throw "*expected executable '$script:expectedAlToolPath' does not exist*"
        }

        It 'Reports AlTool version failure explicitly' {
            New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null
            Mock Invoke-AlNativeCommand {
                return [PSCustomObject]@{
                    StandardOutput = [string[]]@()
                    StandardError  = [string[]]@('version stderr')
                    Output         = [string[]]@('version stderr')
                    ExitCode       = [int] 11
                }
            }

            { GetAlToolPath } |
                Should -Throw "*'al --version'*exited with code 11*version stderr*"
        }
    }

    Describe 'AlTool native invocation' {
        It 'Captures native stdout, stderr, and a nonzero exit code without terminating' {
            $powerShell = (Get-Process -Id $PID).Path
            $childScript = "[Console]::Out.WriteLine('native-stdout'); [Console]::Error.WriteLine('native-stderr'); exit 7"
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

            $result = Invoke-AlNativeCommand -FilePath $powerShell -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedChildScript
            )

            $result.ExitCode | Should -Be 7
            $result.StandardOutput | Should -Be @('native-stdout')
            ($result.StandardError -join "`n") | Should -Match 'native-stderr'
            ($result.Output -join "`n") | Should -Match 'native-stdout'
            ($result.Output -join "`n") | Should -Match 'native-stderr'
        }

        It 'Does not swallow command-not-found errors' {
            { Invoke-AlNativeCommand -FilePath 'al-go-command-that-does-not-exist' } |
                Should -Throw
        }

        It 'Runs the stderr regression in a real Windows PowerShell 5 subprocess' {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because 'Windows PowerShell 5 is only available on Windows'
                return
            }

            $windowsPowerShell = (Get-Command (
                    Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                ) -ErrorAction Stop).Source
            $helperPath = (Resolve-Path (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')).Path
            $childScript = "[Console]::Out.WriteLine('native-stdout'); [Console]::Error.WriteLine('native-stderr'); exit 9"
            $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
            $escapedHelperPath = $helperPath.Replace("'", "''")
            $escapedPowerShell = $windowsPowerShell.Replace("'", "''")
            $parentScript = @"
`$ErrorActionPreference = 'Stop'
. '$escapedHelperPath'
`$result = Invoke-AlNativeCommand -FilePath '$escapedPowerShell' -ArgumentList @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', '$encodedChildScript'
)
@{
    StandardOutput = @(`$result.StandardOutput)
    StandardError = @(`$result.StandardError)
    ExitCode = `$result.ExitCode
} | ConvertTo-Json -Compress
"@
            $encodedParentScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($parentScript))

            $parentOutput = & $windowsPowerShell -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedParentScript 2>&1
            $parentExitCode = $LASTEXITCODE

            $parentExitCode | Should -Be 0
            $payload = ($parentOutput -join "`n") | ConvertFrom-Json
            $payload.ExitCode | Should -Be 9
            @($payload.StandardOutput) | Should -Be @('native-stdout')
            ($payload.StandardError -join "`n") | Should -Match 'native-stderr'
        }
    }
}
