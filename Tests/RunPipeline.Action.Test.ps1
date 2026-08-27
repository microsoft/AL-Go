Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "RunPipeline Action Tests" {
    BeforeAll {
        $actionName = "RunPipeline"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # ConvertFrom-Json returns a plain string, not a one-element array, when the source JSON array has
    # exactly one entry. installAppsJson/installTestAppsJson can legitimately contain just one app (e.g. a
    # single cross-project dependency), so the script must wrap the result in @(...) - otherwise a single
    # app whose publisher name contains a comma gets handed to Run-AlPipeline as a bare string, which then
    # re-splits it on commas and reports the app as two nonexistent files.
    It 'installAppsJson with a single entry stays an array after parsing' {
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $scriptContent | Should -Match ([regex]::Escape('$install.Apps = @(Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json)'))

        $tempJson = Join-Path $TestDrive 'DownloadedApps.json'
        $appPath = 'C:\deps\Stoneridge Software, LLC_Longhorn Midstream BC Extension_25.2.2147483647.2.app'
        ConvertTo-Json @($appPath) -Compress | Out-File -Encoding UTF8 -FilePath $tempJson

        $install = @(Get-Content -Path $tempJson -Raw | ConvertFrom-Json)
        $install.Count | Should -Be 1
        $install[0] | Should -Be $appPath
    }

    It 'installTestAppsJson with a single entry stays an array after parsing' {
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $scriptContent | Should -Match ([regex]::Escape('$install.TestApps = @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)'))
    }

    # Call action

}
