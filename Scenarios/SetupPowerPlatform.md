# Connect your GitHub repository to Power Platform

There are 2 steps to connect your GitHub repository to your Power Platform tenant and environments:

1. Setup the authentication context
1. Setup the AL-Go Repository settings (.github/AL-Go-Settings.json)

## Authentication Context

The authentication context is a JSON object that you save in your GitHub secrets with the following naming convention: `<GitHubEnvironmentName>_AUTHCONTEXT`

The authentication context specifies how the GitHub Environment you have created authenticates against your Power Platform and Business Central environments. You can use UserName/Password to create the authentication context or create a service principal account and use a client secret to connect (see a [Setting up service principal](./SetupServicePrincipalForPowerPlatform.md) for detailed steps).

> **NOTE:** Username/password authentication is only supported for tenants that do NOT have 2-factor authentication enabled.
> The recommended way to get the auth context is to use the BCContainerHelper to generate the JSON - open a PowerShell window and run the following commands:

### Getting service principal authentication context

```powershell
# If not already installed, install latest BcContainerHelper
Install-Module BcContainerHelper -force
$ppClientId = Read-Host -Prompt "Enter client id"
$ppClientSecret = Read-Host -AsSecureString -Prompt 'Enter client secret'
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext -ppClientSecret $ppClientSecret -ppApplicationId $ppClientId | Set-Clipboard
```

### Getting username/password authentication context:

```powershell
# If not already installed, install latest BcContainerHelper
Install-Module BcContainerHelper -force
$ppUserName = Read-Host -Prompt "Enter Power Platform user name"
$ppPassword = Read-Host -AsSecureString -Prompt 'Enter Power Platform password'
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext -ppUsername $ppUserName -ppPassword $ppPassword | Set-Clipboard
```

## AL-Go Repository settings

The AL-Go repository settings are used to define what resources you have in your repository and which GitHub environment you want to deploy to.

The settings are located at:  `.github/AL-Go-Settings.json`

**Example of the AL-Go settings format:**

```json
{
  "type": "PTE",
  "templateUrl": "https://github.com/microsoft/AL-Go-PTE@main",
  "powerPlatformSolutionFolder": "<PowerPlatformSolutionName>",
  "environments": [
    "<GitHubEnvironmentName>"
  ],
  "DeployTo<GitHubEnvironmentName>": {
    "environmentName": "<BusinessCentralEnvironmentName>",
    "companyId": "<BusinessCentralCompanyId>",
    "ppEnvironmentUrl": "<PowerPlatformEnvironmentUrl>"
  }
}
```

> **NOTE:** GitHubEnvironmentName is the name of the environment you are creating in GitHub to represent the Business Central and Power Platform environments you are deploying to. The GitHub environment must have a corresponding authentication context.

______________________________________________________________________

[back](../README.md)
