# Codesigning in AL-Go

If you've already set up your AL-Go repository with an Azure Key Vault (e.g. by following [Scenario 7: Use Azure KeyVault for secrets with AL-Go](./UseAzureKeyVault.md)) you can likely go straight to the [Setting up AL-Go for Code Signing](#setting-up-al-go-for-code-signing) section. If not, please start from [Setting up a Service principal](#setting-up-a-service-principal)

## Setting up a Service principal

1. The first thing you need to do is to set up a service principal in Microsoft Entra. If you're not familiar with setting up service principals you can follow this guide on [registering an application with Microsoft Entra ID and create a service principal](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal#register-an-application-with-microsoft-entra-id-and-create-a-service-principal). 
2. [Create a new client secret for the service principal](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal#option-3-create-a-new-client-secret)
3. Note the **Client Secret** as well as the **Client Id** and the **Tenant Id**.

## Setting up an Azure Key Vault

1. [Create an Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/quick-create-portal) for your code signing certificate if you don't already have one.

**_NOTE:_**  If your certificate was issued after June 2023 your certificate will need to be stored on a Hardware Security Module. Only the Premium SKU of Azure Key Vault supports this (the Standard SKU does not). You can [learn more about the differences here](https://azure.microsoft.com/en-us/pricing/details/key-vault/)
 
2. Configure an Azure Key Vault access policy for the service principal that will be used for signing. At minimum, the account needs the following permissions:

* Cryptographic Operations: Sign
* Certificate Management Operations: Get

![Key Vault Access Policies](https://raw.githubusercontent.com/microsoft/AL-Go/main/Scenarios/images/keyvaultaccesspolicies.png)

3. Import your certificate into the Key Vault.

4. Note the **Key Vault Name**, the **Subscription Id** for the subscription your key vault is in and the **name of your certificate in Azure Key Vault**.

## Setting up AL-Go for Code Signing
Once you have an Azure Key Vault with your certificate in it and a Service Principal with access to the Key Vault you are ready to set up AL-Go for codesigning.

1. Update your AL-Go settings with
```json
"keyVaultName": "<Name of your Key Vault>",
"keyVaultCodesignCertificateName": "<Name of your Codesigning certificate>"
```

2. Add a repository secret called AZURE_CREDENTIALS that contains:

{"clientId":"Client Id","clientSecret":"Client Secret","subscriptionId":"Subscription Id","tenantId":"Tenant Id"}

Where you replace Client Id, Client Secret, Subscription Id and Tenant Id with the values noted earlier in the guide.