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

$ppUserName = Read-Host -Prompt "Enter userName";
$ppPassword = Read-Host -AsSecureString -Prompt 'Enter password';
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


1. In Azure AD, create the service principal.

   To create a service principle, you'll have to register an app with Azure AD and set it up for password-based authentication (with a client secret).

   You can do this step using the Azure portal or PowerShell. For more information, see one the following articles:

   - [Create an Azure AD application and service principal \(using Azure portal\)](/azure/active-directory/develop/howto-create-service-principal-portal)
   - [Create service principal and client secret using PowerShell](/power-platform/alm/devops-build-tools#create-service-principal-and-client-secret-using-powershell)

<br>

2. In Power Platform, add the service principal as an app user on the environment.

   Using Power Platform admin center, add the service principal as an application user of the environment and assign it either the **System admin** or **Super** role. **Super** is recommended.  

   For more information, see [Manage app users in Power Platform](/power-platform/admin/manage-application-users).
