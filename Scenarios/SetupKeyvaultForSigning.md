In order to use the AL-GO Sign action, it is necessary to set up a key vault with a certificate. This guide will provide an explanation of the steps required to do so.

## Required Setup
### 1 - Service Principal
1. To get started, set up an App Registration in Azure. You can find detailed instructions on how to do this by visiting [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal).

2. Once you've created your App Registration, generate a client secret for it.

3. Note the **Client ID** and **Client Secret** of the service principal as well as the **Tenant ID**

### 2 - Azure Key Vault Setup 
1. Create a key vault in Azure. You can find step-by-step instructions on how to do this by visiting [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/general/quick-create-portal). If you need to use Hardware Security Modules, you'll need to set up a Premium SKU key vault instead. For more information on this, see [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/keys/about-keys).

2. Once you've created your key vault, take note of the **Key Vault URI**.

3. Finally, grant your service principal the following permissions:

    Key: Sign

    Certificate: Get

### 3 - Generating / Importing your certificate 
1. Follow the guides on how to create a certificate into Azure Key Vault (https://learn.microsoft.com/en-us/azure/key-vault/certificates/create-certificate) or import a certificate into an existing keyvault (https://learn.microsoft.com/en-us/azure/key-vault/keys/hsm-protected-keys). 

2. Note down the **Certificate Name**