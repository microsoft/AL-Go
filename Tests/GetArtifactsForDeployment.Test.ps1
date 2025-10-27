Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/Github-Helper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "GetArtifactsForDeployment Action Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

        $actionName = "GetArtifactsForDeployment"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        $ENV:GITHUB_API_URL = "apiForGitHub"

        Mock GetHeaders { return @{} }           
        Mock InvokeWebRequest {
            param($headers, $Uri)
            if ($Uri -like "ggez*") {
                return @{
                    Content = @{
                        head = @{
                            ref = "feature/test-branch"
                        }
                    } | ConvertTo-Json
                }
            } elseif ($Uri -like "*/releases") {
                return @(
                    @{ "pre-release" = $false; "draft" = $false }
                )
            } else {
                throw 'nah..'
            }
            return @{ Content = "{}" }
        } -ModuleName Github-Helper
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
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript
    }

    It 'Version is current, releases exist' {
        $settings = @{ "DeployToenv1" = @{ "buildMode" = '' } }
        $env:Settings = $settings | ConvertTo-Json -Compress
        
        . (Join-Path $scriptRoot $scriptName) -artifactsVersion 'current' -artifactsFolder '.artifacts' -environmentName 'env1'

        # DownloadRelease called 4 times (Apps, TestApps, Dependencies, PowerPlatformSolution)
        Assert-MockCalled -CommandName DownloadRelease -Exactly 4
    }

    It 'Version is current, releases does not exist' {
        $settings = @{ "DeployToenv1" = @{ "buildMode" = '' } }
        $env:Settings = $settings | ConvertTo-Json -Compress

        Mock GetReleases {
            return @()
        }
        
        . (Join-Path $scriptRoot $scriptName) -token 'token' -artifactsVersion 'current' -artifactsFolder '.artifacts' -environmentName 'env1'

        Assert-MockCalled -CommandName DownloadRelease -Exactly 0
        Assert-MockCalled -CommandName GetArtifacts -Exactly 4
        Assert-MockCalled -CommandName DownloadArtifact -Exactly 4
    }
}