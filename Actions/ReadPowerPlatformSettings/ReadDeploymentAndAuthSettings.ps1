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
    if ($authContextObject.ppUserName -and $authContextObject.ppPassword) {
        Write-Host "Authenticating with user name and password";
        
        $ppUserName = $authContextObject.ppUserName
        Add-Content -Path $env:GITHUB_ENV -Value "ppUserName=$ppUserName"        
        $ppPassword = $authContextObject.ppPassword
        Add-Content -Path $env:GITHUB_ENV -Value "ppPassword=$ppPassword"
        $ppTenantId = $authContextObject.ppTenantId
        Add-Content -Path $env:GITHUB_ENV -Value "ppTenantId=$ppTenantId"

    } elseif ($authContextObject.ppApplicationId -and $authContextObject.ppClientSecret) {
        write-host "Authenticating with application ID and client secret";

        $ppApplicationId = $authContextObject.ppApplicationId
        Add-Content -Path $env:GITHUB_ENV -Value "ppApplicationId=$ppApplicationId"        
        $ppClientSecret = $authContextObject.ppClientSecret
        Add-Content -Path $env:GITHUB_ENV -Value "ppClientSecret=$ppClientSecret"
        $ppTenantId = $authContextObject.ppTenantId
        Add-Content -Path $env:GITHUB_ENV -Value "ppTenantId=$ppTenantId"

    } else {
        Write-Warning "Invalid input: JSON object must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId' and 'ppClientSecret' properties"
        throw "Invalid input: JSON object must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId' and 'ppClientSecret' properties"
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
