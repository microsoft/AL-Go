# #7 Use Azure KeyVault for secrets with AL-Go
*Prerequisites: A completed [scenario 6](UpdateAlGoSystemFiles.md), an Azure KeyVault and a service principal. You can follow the guide [here](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal) on how to set up a service principal for your keyvault* 

1. Create an application secret for your service principal
2. Note the Client ID and the Tenant ID for your service principal 
3. Go to the KeyVault you want to connect to your AL-GO project and note the KeyVault URI and Subscription ID
4. Create the following secrets in your AL-GO project:

* AZURE_CLIENT_ID: The client ID of your service principal 
* AZURE_CLIENT_SECRET: The secret created in step 1
* AZURE_TENANT_ID: The tenant ID
* AZURE_KEYVAULT_URI: The URI for your KeyVault
* AZURE_KEYVAULT_SUBSCRIPTION_ID: The subscription your KeyVault is in

*Please note that the name specified in the app registration should use a verified domain of the organization (f.ex. the login from your office 365 account) and could be https://myapp.mydomainname.com)*

1. Add the **authContext** secret (see scenario 3) and the **ghTokenWorkflow** secret (see scenario 6) as secrets in your KeyVault. Remove the secrets from repository secrets and environment secrets.
1. Run the CI/CD pipeline to see that the deployment still works, reading the **authContext** secret from the KeyVault.
![runpipeline](images/7a.png)
1. Redo scenario 6 to see that Update AL-Go System files still works.

---
[back](../README.md)
