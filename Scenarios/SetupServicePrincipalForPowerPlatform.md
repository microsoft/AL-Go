# How to set up Service Principal for Power Platform

Setting up a service principal can be done in 2 steps: setting up the principal and adding appropriate roles to the Power Platform environment.

1. In Azure AD, create the service principal.

   To create a service principal, you'll have to register an app with Azure AD and set it up for password-based authentication (with a client secret).

   You can do this step using the Azure portal or PowerShell. For more information, see one the following articles:

   - [Create an Azure AD application and service principal (using Azure portal)](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
   - [Create service principal and client secret using PowerShell](https://learn.microsoft.com/en-us/power-platform/alm/devops-build-tools#create-service-principal-and-client-secret-using-powershell)

<br>

2. In Power Platform, add the service principal as an app user on the environment.

   Using Power Platform admin center, add the service principal as an application user of the environment and assign it either the **System admin** or **Super** role. **System admin** is recommended.

   For more information, see [Manage app users in Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users).
