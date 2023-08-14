# #7 Use Azure KeyVault for secrets with AL-Go
*Prerequisites: A completed [scenario 6](UpdateAlGoSystemFiles.md), an Azure KeyVault and you will need to follow the guidelines on how to connect to an Azure KeyVault as specified [here](https://go.microsoft.com/fwlink/?linkid=2217417&clcid=0x409). Add your KeyVault name to the the JSON construct from this walkthrough (using **“keyVaultName” : “{your keyvault name}”**) and add this JSON construct as a repository secret called AZURE_CREDENTIALS. You can also specify the KeyVault name in the AL-Go settings file if you do not wait to mess with the JSON construct.*

*If you need to use Hardware Security Modules, you'll need to use a Premium SKU key vault. For more information on this, see [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/keys/about-keys)*

*Please note that the name specified in the app registration should use a verified domain of the organization (f.ex. the login from your office 365 account) and could be https://myapp.mydomainname.com)*

1. Add the **authContext** secret (see scenario 3) and the **ghTokenWorkflow** secret (see scenario 6) as secrets in your KeyVault. Remove the secrets from repository secrets and environment secrets.
1. Run the CI/CD pipeline to see that the deployment still works, reading the **authContext** secret from the KeyVault.
![runpipeline](https://github.com/microsoft/AL-Go/assets/10775043/0dd31eb9-e135-46e3-a526-d47873f08b63)
1. Redo scenario 6 to see that Update AL-Go System files still works.

---
[back](../README.md)
