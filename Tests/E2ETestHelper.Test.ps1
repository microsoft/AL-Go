$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'E2E private repository support' {
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\e2eTests\e2eTestHelper.psm1') -Force -DisableNameChecking
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:originalLocation = Get-Location
    $script:originalEnvironment = @{}
    foreach ($name in @('TEMP', 'TMP', 'TMPDIR', 'GH_TOKEN', 'GITHUB_WORKSPACE', 'GITHUB_OUTPUT')) {
        $script:originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
}

AfterAll {
    Set-Location $script:originalLocation
    foreach ($name in $script:originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:originalEnvironment[$name])
    }
}

AfterEach {
    Set-Location $script:originalLocation
    foreach ($name in $script:originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:originalEnvironment[$name])
    }
}

Describe 'Private E2E repository initialization' {
    BeforeEach {
        $testDirectory = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        New-Item -Path $testDirectory -ItemType Directory | Out-Null
        Set-Location $testDirectory
        $env:TEMP = $testDirectory
        $env:TMP = $testDirectory
        $env:TMPDIR = $testDirectory
        $env:GH_TOKEN = 'fixture-token'
        $script:operations = [System.Collections.Generic.List[string]]::new()
        $script:downloadPath = ''

        $archiveRoot = Join-Path $testDirectory 'archive'
        foreach ($folder in @('repo-sha', 'repo-sha\Templates\PTE')) {
            $settingsFolder = Join-Path (Join-Path $archiveRoot $folder) '.github'
            New-Item -Path $settingsFolder -ItemType Directory -Force | Out-Null
            '{"type":"PTE"}' | Set-Content -Path (Join-Path $settingsFolder 'AL-Go-Settings.json') -Encoding UTF8
        }
        $script:templateZip = Join-Path $testDirectory 'template.zip'
        [System.IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot, $script:templateZip)

        Mock Start-Sleep -ModuleName e2eTestHelper {}
        Mock Get-Random -ModuleName e2eTestHelper { 0 }
        Mock Write-Host -ModuleName e2eTestHelper {}
        Mock RefreshToken -ModuleName e2eTestHelper {}
        Mock invoke-git -ModuleName e2eTestHelper {
            $script:operations.Add($command)
        }
        Mock invoke-gh -ModuleName e2eTestHelper {
            if ($command -ne 'repo' -or $remaining[0] -ne 'create') {
                throw 'Unexpected GitHub CLI operation'
            }
            $repoName = ($remaining[1] -split '/')[-1]
            New-Item -Path $repoName -ItemType Directory | Out-Null
        }
        Mock InvokeWebRequest -ModuleName e2eTestHelper {
            $script:downloadPath = $outFile
            Copy-Item -LiteralPath $script:templateZip -Destination $outFile
        }
        Mock SetRepositorySecret -ModuleName e2eTestHelper {
            $script:operations.Add("secret:$name")
        }

        SetTokenAndRepository -github -githubOwner 'fixture-org' -repository 'fixture-org/test' -appId '123' -appKey 'fixture-key' -ghTokenWorkflow 'workflow-credential'
        $script:operations.Clear()
    }

    It 'creates a private repository and authenticates a branch archive before provisioning the workflow secret and pushing' {
        CreateAlGoRepository -github -template 'https://github.com/fixture-org/template@feature/test'

        Should -Invoke invoke-gh -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $command -eq 'repo' -and $remaining[1] -eq 'fixture-org/test' -and '--private' -in $remaining
        }
        Should -Invoke InvokeWebRequest -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://api.github.com/repos/fixture-org/template/zipball/feature%2Ftest' -and
            $headers.Authorization -eq 'token fixture-token'
        }
        Should -Invoke SetRepositorySecret -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $repository -eq 'fixture-org/test' -and $name -eq 'GHTOKENWORKFLOW' -and $value -eq 'workflow-credential'
        }
        $script:operations.IndexOf('secret:GHTOKENWORKFLOW') | Should -BeLessThan $script:operations.IndexOf('push')
        Test-Path -LiteralPath $script:downloadPath | Should -BeFalse
    }

    It 'retains public historical template references and explicit visibility overrides' {
        CreateAlGoRepository -github -private:$false -template 'https://github.com/microsoft/AL-Go-PTE@v8.0'

        Should -Invoke invoke-gh -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $command -eq 'repo' -and '--public' -in $remaining
        }
        Should -Invoke InvokeWebRequest -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://api.github.com/repos/microsoft/AL-Go-PTE/zipball/v8.0'
        }
    }

    It 'extracts a direct-source template subfolder' {
        CreateAlGoRepository -github -template 'https://github.com/source/AL-Go@main|Templates/PTE'

        Test-Path -LiteralPath '.github\AL-Go-Settings.json' | Should -BeTrue
        Test-Path -LiteralPath 'Templates' | Should -BeFalse
        Should -Invoke InvokeWebRequest -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://api.github.com/repos/source/AL-Go/zipball/main'
        }
    }

    It 'provisions a configured secret alias before the first push' {
        CreateAlGoRepository -github -template 'https://github.com/fixture-org/template' -addRepoSettings @{ ghTokenWorkflowSecretName = 'E2EWORKFLOW' }

        Should -Invoke SetRepositorySecret -ModuleName e2eTestHelper -Times 1 -Exactly -ParameterFilter {
            $name -eq 'E2EWORKFLOW' -and $value -eq 'workflow-credential'
        }
        $script:operations.IndexOf('secret:E2EWORKFLOW') | Should -BeLessThan $script:operations.IndexOf('push')
    }

    It 'does not provision an explicitly disabled workflow secret' {
        CreateAlGoRepository -github -template 'https://github.com/fixture-org/template' -addRepoSettings @{ ghTokenWorkflowSecretName = '' }

        Should -Invoke SetRepositorySecret -ModuleName e2eTestHelper -Times 0 -Exactly
    }

    It 'fails before creating a repository when workflow credentials are missing' {
        SetTokenAndRepository -github -githubOwner 'fixture-org' -repository 'fixture-org/test' -appId '123' -appKey 'fixture-key'

        { CreateAlGoRepository -github -template 'https://github.com/fixture-org/template' } | Should -Throw '*ALGOAUTHAPP is required*'

        Should -Invoke invoke-gh -ModuleName e2eTestHelper -Times 0 -Exactly
    }

    It 'propagates download failures and removes incomplete archives without pushing' {
        Mock InvokeWebRequest -ModuleName e2eTestHelper {
            $script:downloadPath = $outFile
            'incomplete archive' | Set-Content -LiteralPath $outFile -Encoding UTF8
            throw '404 repository not accessible'
        }

        { CreateAlGoRepository -github -template 'https://github.com/fixture-org/template' } | Should -Throw '*404 repository not accessible*'

        Test-Path -LiteralPath $script:downloadPath | Should -BeFalse
        Should -Invoke SetRepositorySecret -ModuleName e2eTestHelper -Times 0 -Exactly
        Should -Invoke invoke-git -ModuleName e2eTestHelper -Times 0 -Exactly -ParameterFilter { $command -eq 'push' }
    }

    It 'does not push workflows when secret provisioning fails' {
        Mock SetRepositorySecret -ModuleName e2eTestHelper { throw 'Secret access denied' }

        { CreateAlGoRepository -github -template 'https://github.com/fixture-org/template' } | Should -Throw '*Secret access denied*'

        Should -Invoke invoke-git -ModuleName e2eTestHelper -Times 0 -Exactly -ParameterFilter { $command -eq 'push' }
    }
}

Describe 'E2E secret failure propagation' {
    It 'reports a failed GitHub CLI secret write' {
        Mock gh -ModuleName e2eTestHelper { $global:LASTEXITCODE = 1 }
        try {
            { SetRepositorySecret -repository 'fixture-org/test' -name 'GHTOKENWORKFLOW' -value 'fixture-credential' } | Should -Throw '*Failed to set secret GHTOKENWORKFLOW*'
        }
        finally {
            $global:LASTEXITCODE = 0
        }
    }
}

Describe 'Private E2E template deployment' {
        BeforeAll {
        $env:TEMP = $TestDrive
        $env:TMP = $TestDrive
        $env:TMPDIR = $TestDrive
            Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -DisableNameChecking
            $deploymentScript = GetActionScript -scriptRoot (Join-Path $PSScriptRoot '..\Internal') -scriptName 'Deploy.ps1'
            Invoke-Expression $deploymentScript
        }

        BeforeEach {
            $testDirectory = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
            New-Item -Path $testDirectory -ItemType Directory | Out-Null
            $env:TEMP = $testDirectory
            $env:TMP = $testDirectory
            $env:TMPDIR = $testDirectory
            $env:GITHUB_WORKSPACE = Join-Path $testDirectory 'source'
            foreach ($template in @('Per Tenant Extension', 'AppSource App')) {
                New-Item -Path (Join-Path $env:GITHUB_WORKSPACE "Templates\$template") -ItemType Directory -Force | Out-Null
            }
            Mock Import-Module {}
            Mock Start-Sleep {}
            Mock Write-Host {}
            Mock invoke-git {
                switch ($command) {
                    'clone' { throw 'Fixture repository does not exist yet' }
                    'branch' { 'main' }
                    'rev-parse' { 'fixture-sha' }
                    'config' {
                        if ($remaining[0] -eq '--get') {
                            'https://github.com/source/AL-Go'
                        }
                    }
                }
            }
            Mock invoke-gh {
                if ($command -eq 'auth') {
                    return
                }
                if ($command -ne 'repo' -or $remaining[0] -ne 'create') {
                    throw 'Unexpected GitHub CLI operation'
                }
                New-Item -Path (($remaining[1] -split '/')[-1]) -ItemType Directory | Out-Null
            }
        }

        It 'creates missing templates with <visibility> without changing normal publication' -TestCases @(
            @{ private = $true; visibility = '--private' }
            @{ private = $false; visibility = '--public' }
        ) {
            Param($private, $visibility)

            $expectedVisibility = $visibility
            $parameters = @{
                config = @{
                    githubOwner = 'fixture-org'
                    perTenantExtensionRepo = 'template-PTE'
                    appSourceAppRepo = 'template-AppSource'
                    branch = 'main'
                }
                directCommit = $true
            }
            if ($private) {
                $parameters.private = $true
            }
            Deploy @parameters

            Should -Invoke invoke-gh -Times 2 -Exactly -ParameterFilter {
                $command -eq 'repo' -and $expectedVisibility -in $remaining -and '--clone' -in $remaining
            }
            Should -Invoke invoke-gh -Times 0 -Exactly -ParameterFilter {
                $remaining[1] -like '*Actions'
            }
        }

        Describe 'Private E2E Actions access' {
            BeforeAll {
                $setupRoot = Join-Path $TestDrive 'setup'
                $setupScripts = Join-Path $setupRoot 'e2eTests'
                $deploymentScripts = Join-Path $setupRoot 'Internal'
                New-Item -Path $setupScripts, $deploymentScripts -ItemType Directory | Out-Null
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\e2eTests\SetupRepositories.ps1') -Destination $setupScripts
                'Param($config, $DirectCommit, [switch] $private)' |
                    Set-Content -LiteralPath (Join-Path $deploymentScripts 'Deploy.ps1') -Encoding UTF8
                Invoke-Expression (GetActionScript -scriptRoot $setupScripts -scriptName 'SetupRepositories.ps1')
            }

            BeforeEach {
                $env:GITHUB_OUTPUT = Join-Path $TestDrive "$([Guid]::NewGuid()).output"
                $script:originalExitCode = $global:LASTEXITCODE
                Mock Import-Module {}
                Mock Write-Host {}
                Mock gh { $global:LASTEXITCODE = 0 }
            }

            AfterEach {
                $global:LASTEXITCODE = $script:originalExitCode
            }

            It 'shares the private Actions repository with organization workflows' {
                SetupRepositories -githubOwner 'microsoft'

                Should -Invoke gh -Times 1 -Exactly -ParameterFilter {
                    $args[3] -like '/repos/microsoft/*-Actions/actions/permissions/access' -and
                    $args[5] -eq 'access_level=organization'
                }
                Should -Invoke gh -Times 3 -Exactly -ParameterFilter {
                    $args[3] -like '/repos/microsoft/*/actions/permissions' -and
                    $args[5] -eq 'enabled=false'
                }
            }

            It 'does not configure a nonexistent Actions repository for fork deployments' {
                SetupRepositories -githubOwner 'fixture-org'

                Should -Invoke gh -Times 2 -Exactly
                Should -Invoke gh -Times 0 -Exactly -ParameterFilter {
                    $args[3] -like '*-Actions/*'
                }
            }

            It 'fails setup if organization Actions access cannot be enabled' {
                Mock gh { $global:LASTEXITCODE = 1 }

                { SetupRepositories -githubOwner 'microsoft' } | Should -Throw '*Failed to enable organization Actions access*'

                Should -Invoke gh -Times 1 -Exactly
                Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
            }
        }
    }
}
