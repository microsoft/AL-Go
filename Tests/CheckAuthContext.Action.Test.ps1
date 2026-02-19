Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "CheckAuthContext Action Tests" {
    BeforeAll {
        $actionName = "CheckAuthContext"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    BeforeEach {
        $env:GITHUB_STEP_SUMMARY = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
    }

    AfterEach {
        Remove-Item $env:GITHUB_STEP_SUMMARY -ErrorAction SilentlyContinue
        Remove-Item $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "deviceCode" = "Device code for authentication (if device login is required)"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Should find first matching secret' {
        $env:Settings = '{"adminCenterApiCredentialsSecretName": "adminCenterApiCredentials"}'
        $env:Secrets = '{"adminCenterApiCredentials": "someCredentials"}'

        Invoke-Expression $actionScript
        CheckAuthContext -secretName 'adminCenterApiCredentials'

        # Should NOT output deviceCode when secret is found
        $output = Get-Content $env:GITHUB_OUTPUT -Raw
        $output | Should -Not -Match "deviceCode="
    }

    It 'Should find secret when checking multiple names - first match wins' {
        $env:Settings = '{"adminCenterApiCredentialsSecretName": "adminCenterApiCredentials"}'
        $env:Secrets = '{"TestEnv-AuthContext": "firstSecret", "AuthContext": "secondSecret"}'

        Mock Write-Host {}

        Invoke-Expression $actionScript
        CheckAuthContext -secretName 'TestEnv-AuthContext,TestEnv_AuthContext,AuthContext'

        # Should NOT output deviceCode when secret is found
        $output = Get-Content $env:GITHUB_OUTPUT -Raw
        $output | Should -Not -Match "deviceCode="

        # Should use the first matching secret, not a later one
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "Using TestEnv-AuthContext secret" }
    }

    It 'Should find fallback secret when primary not found' {
        $env:Settings = '{"adminCenterApiCredentialsSecretName": "adminCenterApiCredentials"}'
        $env:Secrets = '{"AuthContext": "fallbackSecret"}'

        Invoke-Expression $actionScript
        CheckAuthContext -secretName 'TestEnv-AuthContext,TestEnv_AuthContext,AuthContext'

        # Should NOT output deviceCode when secret is found
        $output = Get-Content $env:GITHUB_OUTPUT -Raw
        $output | Should -Not -Match "deviceCode="
    }

    It 'Should initiate device login when no secret is found' {
        $env:Settings = '{"adminCenterApiCredentialsSecretName": "adminCenterApiCredentials"}'
        $env:Secrets = '{}'

        # Import AL-Go-Helper to get the functions defined, then mock them
        . (Join-Path $scriptRoot "..\AL-Go-Helper.ps1")
        Mock DownloadAndImportBcContainerHelper { }
        Mock New-BcAuthContext {
            return @{ deviceCode = "TESTDEVICECODE"; message = "Enter code to authenticate" }
        }

        Invoke-Expression $actionScript
        CheckAuthContext -secretName 'nonExistentSecret'

        # Should invoke New-BcAuthContext to get device code
        Should -Invoke New-BcAuthContext -Exactly -Times 1

        # Should output deviceCode when no secret is found
        $output = Get-Content $env:GITHUB_OUTPUT -Raw
        $output | Should -Match "deviceCode=TESTDEVICECODE"

        # Should write device login message to step summary
        $summary = Get-Content $env:GITHUB_STEP_SUMMARY -Raw
        $summary | Should -Match "could not locate a secret"
    }
}
