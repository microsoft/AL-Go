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
    if ($authContextObject.userName -and $authContextObject.password) {
        Write-Host "Authenticating with user name and password";
        
        $userName = $authContextObject.userName
        Add-Content -Path $env:GITHUB_ENV -Value "userName=$userName"        
        $password = $authContextObject.password
        Add-Content -Path $env:GITHUB_ENV -Value "password=$password"

    } elseif ($authContextObject.applicationId -and $authContextObject.clientSecret) {
        write-host "Authenticating with application ID and client secret";

        $applicationId = $authContextObject.applicationId
        Add-Content -Path $env:GITHUB_ENV -Value "applicationId=$applicationId"        
        $clientSecret = $authContextObject.clientSecret
        Add-Content -Path $env:GITHUB_ENV -Value "clientSecret=$clientSecret"

    } else {
        Write-Warning "Invalid input: JSON object must contain either 'userName' and 'password' properties or 'applicationId' and 'clientSecret' properties"
        return;
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
