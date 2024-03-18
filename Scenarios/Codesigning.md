# Codesigning in AL-Go
On June 1, 2023 the industry standards for storing code signing certificates changed. Certificate Authorities now require code signing certificates to be stored on Hardware Security Modules (HSM) or Hardware Tokens that are certified with FIPS 140-2 Level 2 or equivalent. Code signing certificates issued after this date are therefore only issued via physical USB tokens, into on-premises HSM services, or cloud HSM services such as Azure Key Vault. In AL-Go we have decided to opt for using Azure Key Vaults to store code signing certificates and .NET Sign to sign files. 

This guide will take you through how to set up your AL-Go project with an Azure Key Vault and how to use a certificate in the Key Vault to perform code signing. Before you get started, please make sure you've set up your AL-Go project with an Azure Key Vault by following [Scenario 7: Use Azure KeyVault for secrets with AL-Go](./UseAzureKeyVault.md). 

**Note** If your code signing certificate was issued after June 1st 2023 you will most likely need to create a Premium SKU Key Vault. You can [learn more about the differences between Standard and Premium SKU here](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

## Setting up your Azure Key Vault for code signing
1. Import your certificate into the Key Vault.
2. Configure an Azure Key Vault access policy for the service principal that will be used for signing. At minimum, the account needs the following permissions:

* Cryptographic Operations: Sign
* Certificate Management Operations: Get

![Key Vault Access Policies](https://raw.githubusercontent.com/microsoft/AL-Go/main/Scenarios/images/keyvaultaccesspolicies.png)

## Setting up AL-Go for Code Signing
Once you have an Azure Key Vault with your certificate in it and a Service Principal with access to the Key Vault you are ready to set up AL-Go for codesigning.

1. Update your AL-Go settings with
```json
"keyVaultCodesignCertificateName": "<Name of your Codesigning certificate>"
```
