param(
    [Parameter(Mandatory = $true)]
    [string] $deploymentEnvironmentsJson
)

$deploymentEnvironments = $deploymentEnvironmentsJson | ConvertFrom-Json
$deploymentSettings = $deploymentEnvironments."$environmentName"
$envName = $environmentName.Split(' ')[0]
$secrets = $env:Secrets | ConvertFrom-Json

foreach($property in 'ppEnvironmentUrl','companyId','environmentName') {
    if ($deploymentSettings."$property") {
        Write-Host "Setting $property"
        Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$property=$($deploymentSettings."$property")"
    }
    else {
        throw "DeployTo$envName setting must contain '$property' property"
    }
}

$authContext = $null
foreach($secretName in "AuthContext","$($envName)-AuthContext","$($envName)_AuthContext") {
    if ($secrets."$secretName") {
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName")) | ConvertFrom-Json
    }
}

'ppTenantId','ppApplicationId','ppClientSecret','ppUserName','ppPassword' | ForEach-Object {
    if ($authContext.PSObject.Properties.Name -eq $_) {
        Write-Host "Setting $_"
        Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$_=$($authContext."$_")"
        Set-Variable -Name $_ -Value $authContext."$_"
    }
    else {
        Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$_="
        Set-Variable -Name $_ -Value ""
    }
}

if ($ppApplicationId -and $ppClientSecret -and $ppTenantId) {
    Write-Host "Authenticating with application ID and client secret"
}
elseif ($ppUserName -and $ppPassword -and $ppTenantId) {
    Write-Host "Authenticating with user name"
}
else {
    throw "Auth context must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId', 'ppClientSecret' and 'ppTenantId' properties"
}
