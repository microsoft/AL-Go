Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "E2ECheckSecrets Action Tests" {
    BeforeAll {
        $actionName = "E2ECheckSecrets"
        $scriptRoot = Join-Path $PSScriptRoot "..\.github\actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'Used by the child-process invocation helper.')]
        $script:scriptPath = Join-Path $scriptRoot $scriptName -Resolve

        # The action calls 'exit 1' when a required secret is missing. Running it in-process would
        # terminate the whole Pester run, so the behavioral tests execute the script in a child
        # PowerShell process and inspect the exit code and the $GITHUB_OUTPUT file. We launch the
        # same PowerShell edition that is running the tests (powershell on PS5, pwsh on PS7).
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'powerShellExe', Justification = 'Used by the child-process invocation helper.')]
        $script:powerShellExe = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }

        function Invoke-E2ECheckSecrets {
            param(
                [hashtable] $Parameters = @{},
                [string] $RepositoryOwner = 'testrepoowner',
                [hashtable] $OrgMap = @{}
            )

            $workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -Path (Join-Path $workDir 'e2eTests') -ItemType Directory -Force | Out-Null
            ($OrgMap | ConvertTo-Json) | Set-Content -Path (Join-Path $workDir 'e2eTests/orgmap.json') -Encoding UTF8

            $outputFile = Join-Path $workDir 'github_output.txt'
            '' | Set-Content -Path $outputFile -Encoding UTF8

            # Provide non-empty defaults for all required secrets. A caller can set any of these to
            # an empty string to simulate a missing secret (an empty value is not passed to the
            # script, so the script falls back to its own empty default).
            $params = @{
                e2eAppId                  = 'testappid'
                e2ePrivateKey             = 'testprivatekey'
                algoAuthApp               = 'testalgoauthapp'
                adminCenterApiCredentials = 'testadmincreds'
                e2eGHPackagesPAT          = 'testpackagespat'
                e2eAzureCredentials       = 'testazurecreds'
            }
            foreach ($key in $Parameters.Keys) { $params[$key] = $Parameters[$key] }

            $argList = @('-NoProfile', '-File', $script:scriptPath)
            foreach ($key in $params.Keys) {
                if ("$($params[$key])" -ne '') {
                    $argList += @("-$key", [string]$params[$key])
                }
            }

            $previousOutput = $env:GITHUB_OUTPUT
            $previousOwner = $env:GITHUB_REPOSITORY_OWNER
            try {
                $env:GITHUB_OUTPUT = $outputFile
                $env:GITHUB_REPOSITORY_OWNER = $RepositoryOwner
                Push-Location $workDir
                try {
                    $output = & $script:powerShellExe @argList 2>&1
                    $exitCode = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                $env:GITHUB_OUTPUT = $previousOutput
                $env:GITHUB_REPOSITORY_OWNER = $previousOwner
            }

            return [PSCustomObject]@{
                ExitCode     = $exitCode
                Output       = ($output | Out-String)
                GitHubOutput = (Get-Content -Path $outputFile -Raw)
            }
        }
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    Context 'Secret validation' {
        It 'Fails with exit code 1 and an error message when <Missing> is missing' -ForEach @(
            @{ Missing = 'e2eAppId'; Pattern = 'E2E_APP_ID' }
            @{ Missing = 'e2ePrivateKey'; Pattern = 'E2E_PRIVATE_KEY' }
            @{ Missing = 'algoAuthApp'; Pattern = 'ALGOAUTHAPP' }
            @{ Missing = 'adminCenterApiCredentials'; Pattern = 'adminCenterApiCredentials' }
            @{ Missing = 'e2eGHPackagesPAT'; Pattern = 'E2E_GHPackagesPAT' }
            @{ Missing = 'e2eAzureCredentials'; Pattern = 'E2EAZURECREDENTIALS' }
        ) {
            $result = Invoke-E2ECheckSecrets -Parameters @{ $Missing = '' }
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match ([regex]::Escape($Pattern))
        }

        It 'Succeeds with exit code 0 when all required secrets are provided' {
            $result = Invoke-E2ECheckSecrets -RepositoryOwner 'contoso'
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'githubOwner and maxParallel calculation' {
        It 'Defaults githubOwner to the repository owner and sets maxParallel to 8' {
            $result = Invoke-E2ECheckSecrets -RepositoryOwner 'contoso'
            $result.ExitCode | Should -Be 0
            $result.GitHubOutput | Should -Match 'githubOwner=contoso'
            $result.GitHubOutput | Should -Match 'maxParallel=8'
        }

        It 'Remaps githubOwner via orgmap.json and sets maxParallel to 99 for a different owner' {
            $result = Invoke-E2ECheckSecrets -RepositoryOwner 'contoso' -OrgMap @{ contoso = 'mappedowner' }
            $result.ExitCode | Should -Be 0
            $result.GitHubOutput | Should -Match 'githubOwner=mappedowner'
            $result.GitHubOutput | Should -Match 'maxParallel=99'
        }

        It 'Keeps an explicit githubOwner that is not the repository owner and sets maxParallel to 99' {
            $result = Invoke-E2ECheckSecrets -Parameters @{ githubOwner = 'otherowner' } -RepositoryOwner 'contoso'
            $result.ExitCode | Should -Be 0
            $result.GitHubOutput | Should -Match 'githubOwner=otherowner'
            $result.GitHubOutput | Should -Match 'maxParallel=99'
        }
    }
}
