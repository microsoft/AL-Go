# TRASER On-Premise Customer Deployment - extracted from TraserBCHelper

Param(
    [Parameter(Mandatory)][string]$ServerInstance,
    [Parameter(Mandatory)][string]$ArtifactsFolder,
    [Parameter(Mandatory)][string]$NuGetToken,
    [string]$SyncMode = 'Add',
    [string]$TargetBCVersion = '',
    [string]$Tenant = ''
)

# Import NAV module
$navModule = Get-ChildItem "C:\Program Files\Microsoft Dynamics 365 Business Central\*\Service\Microsoft.Dynamics.Nav.Management.psm1" -ErrorAction SilentlyContinue | Select-Object -Last 1
if (-not $navModule) { $navModule = Get-ChildItem "C:\Program Files (x86)\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Management.psm1" -ErrorAction SilentlyContinue | Select-Object -Last 1 }
if ($navModule) { Import-Module $navModule.FullName -Force -DisableNameChecking } else { Write-Error "NAV module not found"; return }

$orderedApps = Get-AppDependencyTree -Path $ArtifactsFolder
Write-Host "Resolved $($orderedApps.Count) apps in dependency order"

$tenants = if ($Tenant) { @($Tenant) } else { @(Get-NAVTenant -ServerInstance $ServerInstance | Select-Object -ExpandProperty Id) }
if ($tenants.Count -eq 0) { $tenants = @('default') }

foreach ($app in $orderedApps) {
    Write-Host "`n--- $($app.Name) $($app.Version) ---"
    $installed = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -ErrorAction SilentlyContinue
    Publish-NAVApp -ServerInstance $ServerInstance -Path $app.Path -SkipVerification
    foreach ($t in $tenants) {
        Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -Tenant $t -Mode $SyncMode
        if ($installed -and [Version]$app.Version -gt [Version]$installed.Version) {
            Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -Tenant $t
        } else {
            Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -Tenant $t
        }
    }
    if ($installed -and [Version]$app.Version -gt [Version]$installed.Version) {
        Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $installed.Version -ErrorAction SilentlyContinue
    }
}
Write-Host "`nDeployment complete"
