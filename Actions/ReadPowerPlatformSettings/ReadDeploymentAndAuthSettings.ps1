param(
    [Parameter(Mandatory = $true)]
    [string]$deployToSettings,
    [Parameter(Mandatory = $true)]
    [string]$authContext
)

function Read-DeployToSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$deployToSettingString
    )
    # Convert the JSON string to a PowerShell object
    $deployToSettings = ConvertFrom-Json $deployToSettingString

    foreach ($property in $deployToSettings.PSObject.Properties) {
        $propertyName = $property.Name
        $propertyValue = $property.Value

        if ($propertyValue) {
            Write-Host "$propertyName : $propertyValue"
            Add-Content -Path $env:GITHUB_ENV -Value "$propertyName=$propertyValue"
        } else {
            Write-Host "$propertyName property not found"
        }
    }
}

function Read-AuthContext {
    param(
        [Parameter(Mandatory=$true)]
        [string]$authContextData
    )
    
    $authContextString = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($authContextData))
    $authContextObject = ConvertFrom-Json $authContextString

    # Check which set of properties is present and assign to local variables accordingly
    if ($authContextObject.UserName -and $authContextObject.Password) {
        Write-Host "Authenticating with user name and password";
        
        $userName = $authContextObject.UserName
        Add-Content -Path $env:GITHUB_ENV -Value "userName=$userName"        
        $password = $authContextObject.Password
        Add-Content -Path $env:GITHUB_ENV -Value "password=$password"
        $tenantId = $authContextObject.TenantID
        Add-Content -Path $env:GITHUB_ENV -Value "tenantId=$tenantId"

    } elseif ($authContextObject.ppApplicationId -and $authContextObject.ppClientSecret) {
        write-host "Authenticating with application ID and client secret";

        $ppApplicationId = $authContextObject.ppApplicationId
        Add-Content -Path $env:GITHUB_ENV -Value "ppApplicationId=$ppApplicationId"        
        $ppClientSecret = $authContextObject.ppClientSecret
        Add-Content -Path $env:GITHUB_ENV -Value "ppClientSecret=$ppClientSecret"
        $tenantId = $authContextObject.TenantID
        Add-Content -Path $env:GITHUB_ENV -Value "tenantId=$tenantId"

    } else {
        Write-Warning "Invalid input: JSON object must contain either 'userName' and 'password' properties or 'ppApplicationId' and 'ppClientSecret' properties"
        throw "Invalid input: JSON object must contain either 'userName' and 'password' properties or 'ppApplicationId' and 'ppClientSecret' properties"
    }
}

Write-Host "*******************************************************************************************"
Write-Host "Read deployment settings"
Write-Host "*******************************************************************************************"
Read-DeployToSettings -deployToSettingString $deployToSettings

Write-Host "*******************************************************************************************"
Write-Host "Read authentication context"
Write-Host "*******************************************************************************************"
Read-AuthContext -authContextData $authContext
