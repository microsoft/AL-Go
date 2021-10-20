Get-Module YamlTestHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'YamlTestHelper.psm1')

Describe 'ReadSettings Action Tests' {
    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $global:actionScript = YamlTest -scriptPath "..\Actions\ReadSettings\ReadSettings.ps1" -permissions $permissions -outputs @{ "Settings" = "Settings in compressed Json format" }
    }

    It 'Compile Action' {
        Invoke-Expression $global:actionScript
    }
}
