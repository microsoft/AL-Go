
Param(
    [Hashtable]$parameters
)

New-BcContainer @parameters

Get-Location | Out-Host
Write-Host "Removing companies"
$keepCompany = "CRONUS Danmark A/S"
Get-CompanyInBcContainer -containerName $parameters.ContainerName | Where-Object { $_.CompanyName -ne $keepCompany } | ForEach-Object {
    Remove-CompanyInBcContainer -containerName $parameters.ContainerName -companyName $_.CompanyName
}
Clean-BcContainerDatabase `
    -containerName $parameters.ContainerName `
    -credential $parameters.credential `
    -saveData `
    -onlySaveBaseAppData `
    -keepBaseApp

Invoke-ScriptInBcContainer -containerName $parameters.ContainerName -scriptblock { $progressPreference = 'SilentlyContinue' }