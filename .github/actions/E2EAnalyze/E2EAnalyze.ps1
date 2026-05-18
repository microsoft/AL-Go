Param(
    [Parameter(HelpMessage = "Maximum parallel jobs", Mandatory = $true)]
    [int] $maxParallel,
    [Parameter(HelpMessage = "Test upgrades from version", Mandatory = $false)]
    [string] $testUpgradesFromVersion = 'v5.0',
    [Parameter(HelpMessage = "Filter to run specific scenarios (separated by comma, supports wildcards)", Mandatory = $false)]
    [string] $scenariosFilter = '*'
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

$scenariosFilterArr = $scenariosFilter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$allScenarios = @(Get-ChildItem -Path (Join-Path $ENV:GITHUB_WORKSPACE "e2eTests/scenarios/*/runtest.ps1") | ForEach-Object { $_.Directory.Name })
$filteredScenarios = $allScenarios | Where-Object { $scenario = $_; $scenariosFilterArr | ForEach-Object { $scenario -like $_ } }

# Load disabled scenarios from config file (optional)
$disabledScenariosConfigPath = Join-Path $ENV:GITHUB_WORKSPACE "e2eTests/disabled-scenarios.json"
$disabledScenariosConfig = @()
if (Test-Path -Path $disabledScenariosConfigPath) {
    $disabledScenariosContent = Get-Content -Path $disabledScenariosConfigPath -Encoding UTF8 -Raw
    if (-not [string]::IsNullOrWhiteSpace($disabledScenariosContent)) {
        $disabledScenariosConfig = $disabledScenariosContent | ConvertFrom-Json
    }
}
else {
    Write-Host "No disabled-scenarios.json found; proceeding with all scenarios enabled."
}
$disabledScenarios = @()
if ($disabledScenariosConfig -and $disabledScenariosConfig.Count -gt 0) {
    $disabledScenarios = @($disabledScenariosConfig | ForEach-Object { $_.scenario })
}
Write-Host "Disabled scenarios from config: $($disabledScenarios -join ', ')"

# Filter out disabled scenarios
$scenariosBeforeDisabledFilter = $filteredScenarios
$beforeFilter = $filteredScenarios.Count
$filteredScenarios = $filteredScenarios | Where-Object { $disabledScenarios -notcontains $_ }
$afterFilter = $filteredScenarios.Count
if ($beforeFilter -ne $afterFilter) {
    Write-Host "Filtered out $($beforeFilter - $afterFilter) disabled scenario(s)"
    $disabledScenariosConfig | Where-Object { ($scenariosBeforeDisabledFilter -contains $_.scenario) -and ($filteredScenarios -notcontains $_.scenario) } | ForEach-Object {
        Write-Host "  - $($_.scenario): $($_.reason)"
    }
}
Write-Host "Scenarios to run: $($filteredScenarios -join ', ')"

$scenariosJson = @{
    "matrix" = @{
        "include" = @($filteredScenarios | ForEach-Object { @{ "Scenario" = $_ } })
    };
    "max-parallel" = $maxParallel
    "fail-fast" = $false
} | ConvertTo-Json -depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "scenarios=$scenariosJson"
Write-Host "scenarios=$scenariosJson"
