Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe "E2ECalculateTestParams Action Tests" {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $PSScriptRoot "../.github/actions/E2ECalculateTestParams/E2ECalculateTestParams.ps1" -Resolve
        # Dot-source the script to load Get-E2ECalculatedTestParams without executing the main block.
        # The mandatory parameters are satisfied with placeholders; the main block is guarded to only run
        # when the script is invoked directly (InvocationName -ne '.').
        . $scriptPath -githubOwner 'placeholder' -appSourceAppRepo 'placeholder' -perTenantExtensionRepo 'placeholder'
    }

    It 'Get-E2ECalculatedTestParams is defined' {
        Get-Command Get-E2ECalculatedTestParams -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    Context 'Template calculation' {
        It 'appSourceApp uses the AppSource app repository template' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'appSourceApp' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.template | Should -Be 'contoso/appSourceRepo'
        }

        It 'PTE uses the per-tenant extension repository template' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'PTE' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.template | Should -Be 'contoso/pteRepo'
        }

        It 'Empty matrixType yields an empty template' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.template | Should -Be ''
        }
    }

    Context 'adminCenterApiCredentials forwarding' {
        # Credentials must only be forwarded for the PTE / singleProject / windows cell
        $forwardCases = @(
            @{ type = 'PTE'; style = 'singleProject'; os = 'windows'; expected = 'the-secret' }
            @{ type = 'PTE'; style = 'multiProject'; os = 'windows'; expected = '' }
            @{ type = 'PTE'; style = 'singleProject'; os = 'linux'; expected = '' }
            @{ type = 'appSourceApp'; style = 'singleProject'; os = 'windows'; expected = '' }
            @{ type = 'appSourceApp'; style = 'multiProject'; os = 'linux'; expected = '' }
        )

        It 'Forwards credentials only for PTE/singleProject/windows (type=<type> style=<style> os=<os>)' -TestCases $forwardCases {
            param($type, $style, $os, $expected)
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType $type -matrixStyle $style -matrixOs $os -adminCenterApiCredentialsSecret 'the-secret' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.adminCenterApiCredentials | Should -Be $expected
        }
    }

    Context 'contentPath calculation' {
        It 'Defaults to appsourceapp for appSourceApp when not provided' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'appSourceApp' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.contentPath | Should -Be 'appsourceapp'
        }

        It 'Defaults to pte for PTE when not provided' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'PTE' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.contentPath | Should -Be 'pte'
        }

        It 'Preserves an explicitly provided contentPath' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'appSourceApp' -contentPath 'customPath' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.contentPath | Should -Be 'customPath'
        }

        It 'Leaves contentPath empty when matrixType is not provided' {
            $result = Get-E2ECalculatedTestParams -githubOwner 'contoso' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo'
            $result.contentPath | Should -Be ''
        }
    }

    Context 'Action entry point GITHUB_OUTPUT serialization' {
        # These tests invoke the script directly (via the call operator) so the guarded main block runs
        # and writes to $env:GITHUB_OUTPUT. The action's bug fix removed literal wrapper quotes from those
        # records, so we assert the exact key=value lines are emitted with no surrounding quotes. Dot-sourced
        # unit tests above never exercise this serialization and would not catch a quoting regression.
        BeforeEach {
            $script:outputFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType File -Path $script:outputFile -Force | Out-Null
            $env:GITHUB_OUTPUT = $script:outputFile
        }

        AfterEach {
            Remove-Item -Path $script:outputFile -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }

        It 'Writes unquoted key=value records for the PTE/singleProject/windows cell' {
            & $scriptPath -githubOwner 'contoso' -matrixType 'PTE' -matrixStyle 'singleProject' -matrixOs 'windows' -adminCenterApiCredentialsSecret 'the-secret' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo' | Out-Null
            $lines = @(Get-Content -Path $script:outputFile)

            $lines | Should -Contain 'adminCenterApiCredentials=the-secret'
            $lines | Should -Contain 'template=contoso/pteRepo'
            $lines | Should -Contain 'contentPath=pte'

            $repoNameLine = $lines | Where-Object { $_ -like 'repoName=*' }
            $repoNameLine | Should -Not -BeNullOrEmpty
            # The repoName value must not be wrapped in quotes.
            ($repoNameLine -replace '^repoName=', '') | Should -Not -Match '"'

            # No output record may wrap its value in quotes.
            foreach ($line in $lines) {
                $line | Should -Not -Match '^[^=]+="'
            }
        }

        It 'Writes unquoted template/contentPath for the appSourceApp cell and no forwarded credentials' {
            & $scriptPath -githubOwner 'contoso' -matrixType 'appSourceApp' -matrixStyle 'multiProject' -matrixOs 'linux' -adminCenterApiCredentialsSecret 'the-secret' -appSourceAppRepo 'appSourceRepo' -perTenantExtensionRepo 'pteRepo' | Out-Null
            $lines = @(Get-Content -Path $script:outputFile)

            $lines | Should -Contain 'template=contoso/appSourceRepo'
            $lines | Should -Contain 'contentPath=appsourceapp'
            # Credentials are not forwarded for this cell, so an empty (unquoted) value is written.
            $lines | Should -Contain 'adminCenterApiCredentials='

            foreach ($line in $lines) {
                $line | Should -Not -Match '^[^=]+="'
            }
        }
    }
}
