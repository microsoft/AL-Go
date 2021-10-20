Get-Module YamlTestHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'YamlTestHelper.psm1')

Describe 'IncrementVersionNumber Action Tests' {
    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
        }
        $global:actionScript = YamlTest -scriptPath "..\Actions\IncrementVersionNumber\IncrementVersionNumber.ps1" -permissions $permissions
    }

    It 'Compile Action' {
        Invoke-Expression $global:actionScript
    }
}
