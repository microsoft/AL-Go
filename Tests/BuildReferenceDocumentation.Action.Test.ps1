Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "BuildReferenceDocumentation Action Tests" {
    BeforeAll {
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
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
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
}
