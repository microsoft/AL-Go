# Code Signing in AL-GO 
Code signing is an essential step in ensuring the integrity and authenticity of software applications. In AL-GO, you have two available mechanisms for code signing: Keyvault Signing (recommended) and PFX Signing. This guide will walk you through the process of setting up code signing with AL-GO using both mechanisms.

## Keyvault Signing
Keyvault Signing is the recommended code signing mechanism in AL-GO, as it leverages Azure Keyvault for performing the signing process. This allows you to utilize certificates stored in Hardware Security Modules (HSMs) for enhanced security. In order to sign you should therefore set up AL-GO with a Keyvault with a valid certificate. 

*Please note that if you are planning to store your secrets/certificates in a Hardware Security Module you need to use the Premium Keyvault SKU.*

### 1a - Creating a new Keyvault setup
To get started with signing in AL-GO you will first have set up a connection to your Keyvault by following the [UseAzureKeyvault](UseAzureKeyvault.md) guide.

### 1b Configuring an existing Keyvault

If you already have AL-GO set up with a Keyvault, it is crucial to ensure that you have the necessary GitHub secrets in place for code signing to work seamlessly. The AZURE_CREDENTIALS secret, previously used for Keyvault connection, is not applicable for codesigning purposes. Instead, you need to create and provide the following secrets:

* AZURE_CLIENT_ID: This secret should contain the Client ID associated with the Azure service principal or application that has access to the Keyvault.

* AZURE_CLIENT_SECRET: Include the Client Secret corresponding to the service principal or application mentioned in the previous step. This secret allows AL-GO to authenticate and access the Keyvault.

* AZURE_TENANT_ID: Specify the Azure AD Tenant ID associated with your Azure subscription. This secret helps AL-GO identify the correct Azure AD directory during authentication.

* AZURE_KEYVAULT_URI: Provide the URI or URL of the Keyvault you have set up in Azure. AL-GO will utilize this information to establish a connection and perform code signing operations.

* AZURE_KEYVAULT_SUBSCRIPTION_ID: This secret should contain the Subscription ID of the Azure subscription where the Keyvault is hosted. It ensures that AL-GO accesses the correct subscription.

Once you have created and populated these secrets in your GitHub repository, they will replace the need for the AZURE_CREDENTIALS secret in AL-GO.

### 2 Granting your Service Principal the right permissions

Grant your service principal (App Registration) the following permissions to your Keyvault:

```json
    Key: Sign
    Certificate: Get
```

### 3 - Generating / Importing your certificate 
To create or import a certificate into Azure Keyvault, you can follow the provided guides:

 Create a certificate in Azure Keyvault:

* [Create a certificate in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/certificates/create-certificate): This guide explains how to create a certificate directly within Azure Keyvault. It covers the process of generating a self-signed certificate or using a certificate signing request (CSR) to create a certificate signed by a certificate authority (CA).

Import a certificate into an existing Keyvault:

* [Tutorial: Import a certificate in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/certificates/tutorial-import-certificate?tabs=azure-portal): This tutorial provides step-by-step instructions on how to import an existing certificate into an Azure Keyvault. It covers importing a certificate in various formats like PFX, PEM, or CER.

* [Import HSM-protected keys to Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/keys/hsm-protected-keys): If you are importing HSM-protected keys into Keyvault, this guide will walk you through the process.


Once you have created or imported the certificate into your Keyvault, make sure to note down the Certificate Name. This name uniquely identifies the certificate within the Keyvault and will be used during the code signing setup with AL-GO.

### 4 - Updating your AL-GO Settings

In your AL-GO settings file provide the following setting using the name of your certificate from the previous step: 

```json
"keyVaultCodesignCertificateName": "myCodeSignCertName",
```


## PFX Signing 

To sign with a PFX file and password, you need to supply the following two settings:

```json
"CodeSignCertificateUrlSecretName": "myCodeSignCertUrl",
"CodeSignCertificatePasswordSecretName": "myCodeSignCertPassword",
```

These settings define the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. 

When supplying the settings, specify the secret names (NOT the secrets) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword.