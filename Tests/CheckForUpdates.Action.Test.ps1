Get-Module YamlTestHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'YamlTestHelper.psm1')

Describe 'CheckForUpdates Action Tests' {
    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
            "workflows" = "write"
        }
        $global:actionScript = TestYaml -scriptPath "..\Actions\CheckForUpdates\CheckForUpdates.ps1" -permissions $permissions
    }

    It 'Compile Action' {
        Invoke-Expression $global:actionScript
    }
}
