Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/Github-Helper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "GetGitHubEnvironments Action Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

        $actionName = "GetGitHubEnvironments"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        $ENV:GITHUB_API_URL = "apiForGitHub"

        Mock GetHeaders { return @{} }
        Mock GetReleases {
            return @(
                @{ "prerelease" = $false; "draft" = $false; "tag_name" = "v1.0.0"; "id" = 1 }
            )
        }
        Mock DownloadRelease { }
        Mock GetArtifacts { return @{} }
        Mock DownloadArtifact { return ([System.IO.Path]::GetTempPath()) }
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "GitHubEnvironments" = "GitHub Environments in compressed Json format"
        }

        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }
}
