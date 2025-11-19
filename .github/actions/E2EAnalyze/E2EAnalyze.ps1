Param(
    [Parameter(HelpMessage = "Maximum parallel jobs", Mandatory = $true)]
    [int] $maxParallel,
    [Parameter(HelpMessage = "Test upgrades from version", Mandatory = $false)]
    [string] $testUpgradesFromVersion = 'v5.0'
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$modulePath = Join-Path "." "e2eTests/e2eTestHelper.psm1" -resolve
Import-Module $modulePath -DisableNameChecking

$publicTestruns = @{
    "max-parallel" = $maxParallel
    "fail-fast" = $false
    "matrix" = @{
        "include" = @()
    }
}
$privateTestruns = @{
    "max-parallel" = $maxParallel
    "fail-fast" = $false
    "matrix" = @{
        "include" = @()
    }
}
@('appSourceApp','PTE') | ForEach-Object {
    $type = $_
    @('linux','windows') | ForEach-Object {
        $os = $_
        @('multiProject','singleProject') | ForEach-Object {
            $style = $_
            $publicTestruns.matrix.include += @{ "type" = $type; "os" = $os; "style" = $style; "Compiler" = "Container" }
            $privateTestruns.matrix.include += @{ "type" = $type; "os" = $os; "style" = $style; "Compiler" = "Container" }
            if ($type -eq "PTE") {
                # Run end 2 end tests using CompilerFolder with Windows+Linux and single/multiproject
                $publicTestruns.matrix.include += @{ "type" = $type; "os" = $os; "style" = $style; "Compiler" = "CompilerFolder" }
            }
        }
    }
}
$publicTestrunsJson = $publicTestruns | ConvertTo-Json -depth 99 -compress
$privateTestrunsJson = $privateTestruns | ConvertTo-Json -depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "publictestruns=$publicTestrunsJson"
Write-Host "publictestruns=$publicTestrunsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "privatetestruns=$privateTestrunsJson"
Write-Host "privatetestruns=$privateTestrunsJson"

$releases = @(gh release list --repo microsoft/AL-Go | ForEach-Object { $_.split("`t")[0] }) | Where-Object { [Version]($_.trimStart('v')) -ge [Version]($testUpgradesFromVersion.TrimStart('v')) }
$releasesJson = @{
    "matrix" = @{
        "include" = @($releases | ForEach-Object { @{ "Release" = $_; "type" = 'appSourceApp' }; @{ "Release" = $_; "type" = 'PTE' } } )
    };
    "max-parallel" = $maxParallel
    "fail-fast" = $false
} | ConvertTo-Json -depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "releases=$releasesJson"
Write-Host "releases=$releasesJson"

$scenariosJson = @{
    "matrix" = @{
        "include" = @(Get-ChildItem -path (Join-Path $ENV:GITHUB_WORKSPACE "e2eTests/scenarios/*/runtest.ps1") | ForEach-Object { @{ "Scenario" = $_.Directory.Name } } )
    };
    "max-parallel" = $maxParallel
    "fail-fast" = $false
} | ConvertTo-Json -depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "scenarios=$scenariosJson"
Write-Host "scenarios=$scenariosJson"
