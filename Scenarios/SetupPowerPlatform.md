# (preview) Connect your GitHub repository to Power Platform

There are 2 steps to connect your GitHub repository to your Power Platform tenant and environments:

1. Setup the authentication context
2. Setup the AL-Go-Settings

## Authentication Context

The authentication context specifies how the GitHub Environment you have created authenticates against your Power Platform and Business Central environments. You can use UserName/Password to create the authentication context or create a service principal account and use a client secret to connect (see a [Setting up service principal](./SetupServicePrincipal.md) for detailed steps).

<br>

> **NOTE:** Username/password authentication is only supported for tenants that do NOT have 2-factor authentication enabled.

<br>

The authentication context is a JSON object that you save in your GitHub secrets with the following naming convention: `<GitHubEnvironmentName>_AUTHCONTEXT`



The recommended way to get the auth context is to use the BCContainerHelper to generate the JSON - open a PowerShell window and run the following commands:

**Getting service principal authentication context:**
```powershell
Install-Module BcContainerHelper -force -allowPrerelease;

$ppClientId = Read-Host -Prompt "Enter client id";
$ppClientSecret = Read-Host -AsSecureString -Prompt 'Enter client secret';
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext -ppClientSecret $ppClientSecret -ppApplicationId $ppClientId
```

**Getting username/password authentication context:**
```powershell
Install-Module BcContainerHelper -force -allowPrerelease;

$ppUserName = Read-Host -Prompt "Enter userName";
$ppPassword = Read-Host -AsSecureString -Prompt 'Enter password';
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext -ppUsername $ppUserName -ppPassword $ppPassword
```

If you get an error while trying to install the module you'll need to update your PowerShellGet module to the latest version:

```powershell
Install-Module -Name PowerShellGet -Repository PSGallery -Force
```
> **NOTE:** You have to restart the PowerShell window after updating the PowerShellGet module.


<br>


## AL-Go-Settings

The AL-Go-settings are used to define what resources you have in your repository and which GitHub environment you want to deploy to.

<br>

The settings are located at:  `.github/AL-Go-Settings.json`

<br>


**Example of the Al-go settings format:**

```json
{
  "type": "PTE",
  "templateUrl": "https://github.com/BusinessCentralDemos/AL-Go-PTE@main",
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
Please note that GitHubEnvironmentName is the name of the environment you are creating in GitHub to represent the Business Central and Power Platform environments you are deploying to. The GitHub environment must have a corresponding authentication context.

