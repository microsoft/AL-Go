# Power Platform Repository Setup

There are 2 steps to connect your build system with your Power Platform tenant and environments:

1. Setup Authentication context
2. Setup AL-Go-Settings

## Authentication Context

The authentication context specifies how you want to authenticate against your Power Platform environment. You can use UserName/Password or create a service principal and use a client secret to connect.

<br>

> **NOTE:** Username/password authentication is only supported for tenants that do NOT have 2-factor authentication enabled.

<br>

The authentication context is a JSON object that you save in your GitHub secrets with the following naming convention: `<environmentName>_AUTHCONTEXT`


> **NOTE:** The JSON object cannot have any spaces.

<br>

The recommended way to get the auth context is to use the BCContainerHelper to generate the JSON:
> **NOTE:** You need to use the preview version to get the new parameters to ALGoAuthContext.

```powershell
Install-Module BcContainerHelper -force -allowPrerelease;

$ppUserName = Read-Host -Prompt "Enter userName:";
$ppPassword = Read-Host -AsSecureString -Prompt 'Enter password:';
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext -ppUsername $ppUserName -ppPassword $ppPassword
```

## AL-Go-Settings

The AL-Go-Settings specify which Power Platform environment GitHub should deploy to and when. You can also add information about the Business Central Environment and company you want to connect to. If provided, this information is used at deployment time to ensure that your Power Platform artifacts are connected to the correct Business Central environment and company.

<br>

The Al-Go-Settings are located at:  `<repoRoot>/.github/AL-Go-Settings.json`

<br>

**Example of the deployTo settings format:**

```json
"DeployTo<GitEnvironment>": {
  "environmentName": "<Bc Environment name>",
  "companyId": "<Bc Company GUID>",
  "ppEnvironmentUrl": "<Power platform environment URL>"
}
```
```json
"DeployToStaging": {
  "environmentName": "Sandbox",
   "companyId": "dc50d5e8-f9c9-ed11-94cc-000d3a220b2f",
   "ppEnvironmentUrl": "https://orgc791aad2.crm.dynamics.com/"
},
```


## Set up Service Principal

Setting up a service principal can be done in 2 steps: setting up the principal and adding appropriate roles to the Power Platform environment.

### 1. Set up service principal

    a. Create App registration
    b. Create Client Secret

### 2. Add roles in Power Platform (Super is recommended)

    a. In PPAC, find the environment you want to use
    b. Go to settings, Application users, and add the new principal and give it the "System admin" role.

### Learn more

- [How to: Use the portal to create an Azure AD application and service principal that can access resources](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
- [Microsoft Power Platform Build Tools for Azure DevOps - Power Platform | Microsoft Learn](https://docs.microsoft.com/en-us/learn/modules/introduction-power-platform-build-tools/)
