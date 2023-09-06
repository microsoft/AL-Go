Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '../TestActionsHelper.psm1')

Describe "All AL-GO workflows should have similar content" {
    BeforeEach {
        $errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
    }

    It 'All workflows existing in both templates should have similar content' {
        $pteWorkflows = (Join-Path $PSScriptRoot "..\..\Templates\Per Tenant Extension\.github\workflows\" -Resolve) | GetWorkflowsInPath
        $appSourceWorkflows = ((Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\" -Resolve) | GetWorkflowsInPath).Name
        $pteWorkflows | Where-Object { $appSourceWorkflows -contains $_.Name } | ForEach-Object {
            $pteWorkflowContent = Get-ContentLF -Path $_.FullName
            $appSourceWorkflowContent = Get-ContentLF -Path (Join-Path $PSScriptRoot "..\..\Templates\AppSource App\.github\workflows\$($_.Name)")
            Write-Host "Comparing $($_.Name)"
            $pteWorkflowContent | Should -Be $appSourceWorkflowContent
        }
    }
}
