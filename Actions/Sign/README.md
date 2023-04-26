# Sign
Sign files with a certificate stored in Azure Key Vault
## Parameters
### azureKeyVaultURI
The URI of the Azure Key Vault the certificate is stored in
### azureKeyVaultClientID
The Client ID of the service principal used to access the keyvault 
### azureKeyVaultClientSecret
The Client ID of the service principal used to access the keyvault 
### azureKeyVaultTenantID
The tenant id used to authenticate to Azure
### azureKeyVaultCertificateName
The name of the certificate used to perform the signing
### pathToFiles
The path to the files to be signed
### timestampService
The URI of the timestamp server
### digestAlgorithm
The digest algorithm to use for signing and timestamping
