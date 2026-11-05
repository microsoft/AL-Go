[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock parameters must match function signatures')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/AlToolHelper.psm1' -Resolve) -DisableNameChecking -Force

Describe 'AlToolHelper.psm1 Tests' {
    BeforeAll {
        # Other test files import this module as a nested dependency during discovery.
        Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/AlToolHelper.psm1' -Resolve) -DisableNameChecking -Force
    }

    It 'Exports only the RunTests integration functions' {
        @(Get-Command -Module AlToolHelper).Name | Sort-Object |
            Should -Be @('GetAlToolPath', 'Invoke-AlNativeCommand')
    }

    InModuleScope AlToolHelper {
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
                    'GITHUB_REPOSITORY_ID',
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
                $env:GITHUB_REPOSITORY_ID = '67890'
                $env:GITHUB_RUN_ID = '12345'
                $env:GITHUB_RUN_ATTEMPT = '2'

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

            It 'Reuses the executable from the expected run directory and persists it for later steps' {
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

            It 'Recovers from a missing persisted path through the expected run directory' {
                $env:AlToolPath = Join-Path $TestDrive 'missing-al'
                New-TestAlToolExecutable -Path $script:expectedAlToolPath | Out-Null

                GetAlToolPath | Should -Be $script:expectedAlToolPath

                $env:AlToolPath | Should -Be $script:expectedAlToolPath
                Should -Invoke Invoke-AlNativeCommand -Times 0 -Exactly -ParameterFilter {
                    $FilePath -eq 'dotnet'
                }
            }

            It 'Installs the prerelease tool into the deterministic run directory only once' {
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

            It 'Returns a deterministic directory for the current GitHub run attempt' {
                $firstPath = Get-AlToolInstallDirectory
                $secondPath = Get-AlToolInstallDirectory

                $firstPath | Should -Be $secondPath
                $firstPath | Should -Be (
                    Join-Path (Join-Path ([System.IO.Path]::GetFullPath($env:RUNNER_TEMP)) 'AL-Go-AlTool') `
                        '67890-12345-2'
                )
            }

            It 'Uses a different directory for a later run attempt' {
                $firstPath = Get-AlToolInstallDirectory
                $env:GITHUB_RUN_ATTEMPT = '3'
                $secondPath = Get-AlToolInstallDirectory

                $firstPath | Should -Not -Be $secondPath
            }

            It 'Uses the shared system temporary directory outside GitHub Actions' {
                Remove-Item Env:\RUNNER_TEMP -ErrorAction SilentlyContinue
                Remove-Item Env:\GITHUB_REPOSITORY_ID -ErrorAction SilentlyContinue
                Remove-Item Env:\GITHUB_RUN_ID -ErrorAction SilentlyContinue
                Remove-Item Env:\GITHUB_RUN_ATTEMPT -ErrorAction SilentlyContinue

                $firstPath = Get-AlToolInstallDirectory
                $secondPath = Get-AlToolInstallDirectory
                $firstPath | Should -Be $secondPath
                $firstPath | Should -Be $secondPath
                $firstPath | Should -Be (
                    Join-Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) 'AL-Go-AlTool'
                )
            }

            It 'Returns the expected executable name for <Platform>' -TestCases @(
                @{ Platform = [System.PlatformID]::Win32NT; ExpectedName = 'al.exe' }
                @{ Platform = [System.PlatformID]::Unix; ExpectedName = 'al' }
            ) {
                param($Platform, $ExpectedName)

                Get-AlToolExecutableName -Platform $Platform | Should -Be $ExpectedName
            }

            It 'Removes only the exact incomplete run directory before reinstalling' {
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

            It 'Reports a failed run-scoped installation with its output' {
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

            It 'Invokes only the first application when command resolution returns multiple candidates' {
                $script:firstNativeCandidate = (Get-Process -Id $PID).Path
                $script:secondNativeCandidate = Join-Path $TestDrive 'must-not-run'
                Mock Get-Command {
                    return @(
                        [PSCustomObject]@{ Source = $script:firstNativeCandidate }
                        [PSCustomObject]@{ Source = $script:secondNativeCandidate }
                    )
                } -ParameterFilter { $Name -eq 'multiple-native-candidates' }
                $childScript = "[Console]::Out.WriteLine('first-candidate'); exit 0"
                $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

                $result = Invoke-AlNativeCommand -FilePath 'multiple-native-candidates' -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedChildScript
                )

                $result.ExitCode | Should -Be 0
                $result.StandardOutput | Should -Be @('first-candidate')
                Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
                    $Name -eq 'multiple-native-candidates'
                }
            }

            It 'Does not swallow command-not-found errors' {
                { Invoke-AlNativeCommand -FilePath 'al-go-command-that-does-not-exist' } |
                    Should -Throw
            }

            It 'Runs the stderr regression in a real Windows PowerShell 5 subprocess' {
                if ([Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
                    Set-ItResult -Skipped -Because 'Windows PowerShell 5 is only available on Windows'
                    return
                }

                $windowsPowerShell = (Get-Command (
                        Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                    ) -ErrorAction Stop).Source
                $modulePath = (Resolve-Path (Join-Path $PSScriptRoot '../Actions/.Modules/AlToolHelper.psm1')).Path
                $childScript = "[Console]::Out.WriteLine('native-stdout'); [Console]::Error.WriteLine('native-stderr'); exit 9"
                $encodedChildScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
                $escapedModulePath = $modulePath.Replace("'", "''")
                $escapedPowerShell = $windowsPowerShell.Replace("'", "''")
                $parentScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$escapedModulePath' -Force
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
}
