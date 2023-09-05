Param(
    [Hashtable]$parameters
)

New-BcContainer @parameters

$installedApps = Get-BcContainerAppInfo -containerName $containerName -tenantSpecificProperties -sort DependenciesLast
$installedApps | % {
    Write-Host "Removing $($_.Name)"
    Unpublish-BcContainerApp -containerName $parameters.ContainerName -name $_.Name -unInstall -doNotSaveData -doNotSaveSchema -force
}

Invoke-ScriptInBcContainer -containerName $parameters.ContainerName -scriptblock { $progressPreference = 'SilentlyContinue' }
