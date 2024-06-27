# Code signing in AL-Go

On June 1st 2023 the industry standards for storing code signing certificates changed. Certificate Authorities now require code signing certificates to be stored on Hardware Security Modules (HSM) or Hardware Tokens that are certified with FIPS 140-2 Level 2 or equivalent. Code signing certificates issued after this date are therefore only issued via physical USB tokens, into on-premises HSM services, or cloud HSM services such as Azure Key Vault. In AL-Go we have decided to opt for using Azure Key Vaults to store code signing certificates and .NET Sign to sign files.

This guide will take you through how to set up your AL-Go project with an Azure Key Vault and how to use a certificate in the Key Vault to perform code signing. Before you get started, please make sure you've set up your AL-Go project with an Azure Key Vault by following [Scenario 7: Use Azure KeyVault for secrets with AL-Go](./UseAzureKeyVault.md).

> \[!NOTE\]
> If your code signing certificate was issued after June 1st 2023 you will most likely need to create a Premium SKU Key Vault. You can [learn more about the differences between Standard and Premium SKU here](https://azure.microsoft.com/en-us/pricing/details/key-vault/)

## Setting up your Azure Key Vault for code signing

1. Import your certificate into the Key Vault.

How you do this might depend on which Certificate Authority you are getting your certificate from. DigiCert and GlobalSign have integrations with Azure Key Vault. You can follow [this guide](https://learn.microsoft.com/en-us/azure/key-vault/certificates/how-to-integrate-certificate-authority) on how to set up that integration if you are using one of those CAs. Once you have set up the integration, you can request a certificate from within your Azure Key Vault. If you are using another CA you can try following this guide to [Generate a CSR and Install a Certificate in Microsoft Azure Key Vault](https://www.ssl.com/how-to/generate-csr-install-certificate-microsoft-azure-key-vault/). If neither of those options work for you, please engage with your CA to get the certificate into the Key Vault.

2. An Azure Key Vault can be set up for two different security models: Role Based Access Control (RBAC) (recommended) and Vault Access Policy. In order for AL-Go for GitHub to use the Key Vault, the following roles/permissions need to be assigned to the app registration or Managed Identity, on which the authentication is performed:

Role Based Access Control, roles needed:

- Key Vault Crypto User
- Key Vault Certificate User

Vault Access Policy, permissions needed:

- Cryptographic Operations: Sign
- Certificate permissions: Get

See more [here](https://aka.ms/algosecrets#azure_credentials).

## Setting up AL-Go for Code Signing

Once you have an Azure Key Vault with your certificate in it and a Service Principal with access to the Key Vault you are ready to set up AL-Go for code signing.

1. Update your AL-Go settings with

```json
"keyVaultCodesignCertificateName": "<Name of your code signing certificate>"
```
