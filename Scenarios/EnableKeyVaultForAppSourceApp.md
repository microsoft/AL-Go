# #12 Enable KeyVault access for your AppSource App during development and/or tests
For AppSource apps, if you want to enable KeyVault access for your app (as described [here](https://go.microsoft.com/fwlink/?linkid=2217058&clcid=0x409) you can add the access to this keyvault in your local development environment or your pipelines (for running tests) by adding 3 secrets to either the GitHub repo or your KeyVault. Based on [this walkthrough](https://go.microsoft.com/fwlink/?linkid=2216856&clcid=0x409) you will need to create 3 secrets:
- A **KeyVaultClientId**, which is the Client ID for the AAD App with access to the KeyVault.
- A **KeyVaultCertificateUrl**, pointing to a certificate which gives you access to the AAD App.
- A **KeyVaultCertificatePassword**, which is the password for this certificate.

In the case of KeyVault access for apps, it is not enough to just add the secrets, you will also have to add information in the **.AL-Go\settings.json** that this app uses this KeyVault. Add these three settings

```json
"KeyVaultCertificateUrlSecretName": "KeyVaultCertificateUrl",
"KeyVaultCertificatePasswordSecretName": "KeyVaultCertificatePassword",
"KeyVaultClientIdSecretName": "KeyVaultClientId",
```

With this, containers set up for build pipelines or development environments will have access to this keyvault.

---
[back](../README.md)
