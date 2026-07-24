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
}
