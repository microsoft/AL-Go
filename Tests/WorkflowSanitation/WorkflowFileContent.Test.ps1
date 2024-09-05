Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-Go workflows should have similar content" {
    It 'All workflows existing in both templates should have similar content' {
        . (Join-Path $PSScriptRoot '..\..\Actions\CheckForUpdates\yamlclass.ps1')
        . (Join-Path $PSScriptRoot '..\..\Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1')
        $pteWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $appSourceWorkflows = ((Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath).Name
        $pteWorkflows | Where-Object { $appSourceWorkflows -contains $_.Name } | ForEach-Object {
            $pteWorkflowContent = (Get-Content -Path $_.FullName -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
            $appSourceWorkflowContent = (Get-Content -Path (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\$($_.Name)") -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
            if ($_.Name -eq 'CICD.yaml') {
                # CICD.yaml is a special case, as it contains a buildPP section that is not present in the AppSource App template
                $yaml = [Yaml]::Load($_.FullName)
                ModifyBuildWorkflows -yaml $yaml -depth 1 -includeBuildPP $false
                $pteWorkflowContent = $yaml.content -join "`n"
            }
            Write-Host "Comparing $($_.Name)"
            $pteWorkflowContent | Should -Be $appSourceWorkflowContent
        }
    }
}

Describe "PreGateCheck in PullRequestHandler should use runs-on: windows-latest" {
    It 'Check PullRequestHandler.yaml for runs-on: windows-latest' {
        # Check that PullRequestHandler.yaml in both templates uses runs-on: windows-latest, which doesn't get updated by the Update AL-Go System Files action
        $ScriptRoot = $PSScriptRoot
        . (Join-Path $ScriptRoot "../../Actions/CheckForUpdates/yamlclass.ps1")
        foreach($template in @('Per Tenant Extension','AppSource App')) {
            $yaml = [Yaml]::load((Join-Path $ScriptRoot "..\..\Templates\$template\.github\workflows\PullRequestHandler.yaml" -Resolve))
            $yaml.Get('jobs:/PregateCheck:/runs-on').content | Should -Be 'runs-on: windows-latest' -Because "PreGateCheck in $template/PullRequestHandler.yaml should use runs-on: windows-latest"
        }
    }
}
