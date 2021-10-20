Get-Module YamlTestHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'YamlTestHelper.psm1')

Describe 'Deploy Action Tests' {
    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $global:actionScript = YamlTest -scriptPath "..\Actions\Deploy\Deploy.ps1" -permissions $permissions
    }

    It 'Compile Action' {
        Invoke-Expression $global:actionScript
    }
}
