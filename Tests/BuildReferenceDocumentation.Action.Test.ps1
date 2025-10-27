Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "BuildReferenceDocumentation Action Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        $actionName = "BuildReferenceDocumentation"
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

    It 'CalculateProjectsAndApps' {
        . (Join-Path $scriptRoot 'BuildReferenceDocumentation.HelperFunctions.ps1')

        Mock Get-ChildItem {
            if ($filter -eq '*.app') {
                $project = [System.IO.Path]::GetFileName($path).Substring(0,2)
                $noOfApps = [int]$project.substring(1,1)
                $apps = @()
                for($i=1; $i -le $noOfApps; $i++) {
                    $apps += [PSCustomObject]@{ FullName = Join-Path $path "$($project)_app$i.app" }
                }
                return $apps
            }
            else {
                return @(
                    [PSCustomObject]@{ Name = 'P1-main-Apps-1.0.0.0'; FullName = Join-Path $path 'P1-main-Apps-1.0.0.0'; "PsIsContainer" = $true }
                    [PSCustomObject]@{ Name = 'P2-main-Apps-1.0.0.0'; FullName = Join-Path $path 'P2-main-Apps-1.0.0.0'; "PsIsContainer" = $true }
                    [PSCustomObject]@{ Name = 'P3-main-Apps-1.0.0.0'; FullName = Join-Path $path 'P3-main-Apps-1.0.0.0'; "PsIsContainer" = $true }
                    [PSCustomObject]@{ Name = 'P4-main-Apps-1.0.0.0'; FullName = Join-Path $path 'P4-main-Apps-1.0.0.0'; "PsIsContainer" = $true }
                )
            }
        }

        $allApps = CalculateProjectsAndApps -tempFolder (Get-Location).Path -includeProjects @('P1','P2') -excludeProjects @('P3')
        $allApps.Count | Should -Be 2
        $allApps[0].Keys.Count | Should -be 1
        $allApps[0].ContainsKey('dummy') | Should -be $true
        $allApps[0]."dummy".Count | Should -be 3

        $allApps = CalculateProjectsAndApps -tempFolder (Get-Location).Path -includeProjects @('*') -excludeProjects @('P3') -groupByProject
        $allApps.Count | Should -Be 2
        $allApps[0].Keys.Count | Should -be 3
        $allApps[0].ContainsKey('dummy') | Should -be $false
        $allApps[0]."P1".Count | Should -be 1
        $allApps[0]."P2".Count | Should -be 2
        $allApps[0]."P4".Count | Should -be 4
    }

    It 'Artifact URL generated if not provided' {
        . (Join-Path $scriptRoot 'BuildReferenceDocumentation.HelperFunctions.ps1')
        . (Join-Path -Path $scriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        Mock Get-BCArtifactUrl { return 'https://example.com/artifact.zip' }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock Expand-Archive { }
        Mock Remove-Item { }
        Mock Download-Artifacts { return 'c:/a/b/c'}
        Mock Join-Path { return 'c:/a/b/c' }
        Mock Test-Path { return $true }
        Mock CmdDo { }

        $ENV:aldocPath = ""
        DownloadAlDoc

        Assert-MockCalled -CommandName Get-BCArtifactUrl -Exactly 1 -Scope It
    }

    It 'Artifact URL country replaced if not core' {
        . (Join-Path $scriptRoot 'BuildReferenceDocumentation.HelperFunctions.ps1')
        . (Join-Path -Path $scriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        Mock Get-BCArtifactUrl { return 'https://example.com/artifact.zip' }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock Expand-Archive { }
        Mock Remove-Item { }
        Mock Download-Artifacts { return 'c:/a/b/c'}
        Mock Join-Path { return 'c:/a/b/c' }
        Mock Test-Path { return $true }
        Mock CmdDo { }

        $ENV:aldocPath = ""
        DownloadAlDoc -artifactUrl "https://example.com/sandbox/us"

        Assert-MockCalled -CommandName Get-BCArtifactUrl -Exactly 0 -Scope It
        Assert-MockCalled -CommandName Download-Artifacts -ParameterFilter { $artifactUrl -eq "https://example.com/sandbox/core" }
    }

    It 'Build modes handles correctly' {
        . (Join-Path $scriptRoot 'BuildReferenceDocumentation.HelperFunctions.ps1')
        . (Join-Path -Path $scriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        $settings = @{ "buildModes" = @('default','custom1','custom2','default','custom1'); "alDoc" = @{ "includeProjects" = @(); "excludeProjects" = @(); "maxReleases" = 2; "header" = ""; "footer" = ""; "defaultIndexMD" = ""; "defaultReleaseMD" = ""; "groupByProject" = $true } }
        $env:Settings = $settings | ConvertTo-Json -Compress
        $ENV:GITHUB_WORKSPACE = ([System.IO.Path]::GetTempPath())

        Mock GetArtifacts { param($mask) return $null }
        Mock DownloadArtifact { return ([System.IO.Path]::GetTempPath()) }
        Mock Expand-Archive { }
        Mock Remove-Item { }
        Mock GetReleases { return @() }
        Mock New-Item { }
        Mock Get-ChildItem { }
        Mock CalculateProjectsAndApps { return @(), @() }

        . (Join-Path $scriptRoot $scriptName) -token 'token' -artifacts 'placeholder'

        Assert-MockCalled -CommandName GetArtifacts -Exactly 1 -Scope It -ParameterFilter { $mask -eq 'Apps'}
        Assert-MockCalled -CommandName GetArtifacts -Exactly 1 -Scope It -ParameterFilter { $mask -eq 'custom1Apps'}
        Assert-MockCalled -CommandName GetArtifacts -Exactly 1 -Scope It -ParameterFilter { $mask -eq 'custom2Apps'}
    }
}
