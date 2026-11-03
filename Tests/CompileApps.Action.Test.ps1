$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'CompileApps action startup' {
    It 'Keeps the shared resolver and native command helper available after the actual action imports' {
        $actionPath = Join-Path $PSScriptRoot '..\Actions\CompileApps\Compile.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($actionPath, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $imports = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Import-Module'
        }, $false)

        & {
            param($actionRoot, $imports)
            foreach ($statement in $imports) {
                $command = $statement.Extent.Text.Replace('$PSScriptRoot', "'$($actionRoot.Replace("'", "''"))'")
                . ([scriptblock]::Create($command))
            }
            Get-Command GetAlToolPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
            & (Get-Module CompileFromWorkspace) {
                Get-Command Invoke-AlNativeCommand -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        } (Split-Path (Resolve-Path $actionPath)) $imports
    }
}
