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

    It 'Restores compatibility manifest bytes in the action finally block after compilation failure' {
        $actionPath = Join-Path $PSScriptRoot '..\Actions\CompileApps\Compile.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($actionPath, [ref]$tokens, [ref]$errors)
        $actionTry = $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] } | Select-Object -Last 1
        $cleanup = [scriptblock]::Create(($actionTry.Finally.Statements.Extent.Text -join "`n"))
        $manifestPath = Join-Path $TestDrive 'app.json'
        $original = [System.Text.Encoding]::UTF8.GetBytes('{"application":"20.0.0.0"}')
        $compatibilityManifests = @{ $manifestPath = $original }
        Set-Content -LiteralPath $manifestPath -Value '{"application":"30.0.0.0"}' -Encoding UTF8
        $initialLocation = (Get-Location).Path
        {
            Push-Location $TestDrive
            try { throw 'Compilation failed' }
            finally { . $cleanup }
        } | Should -Throw 'Compilation failed'
        [System.IO.File]::ReadAllBytes($manifestPath) | Should -Be $original
        (Get-Location).Path | Should -Be $initialLocation
    }
}
