# Sign

Sign apps with a certificate stored in Azure Key Vault

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| azureCredentialsJson | Yes | Azure Credentials secret (Base 64 encoded) | |
| timestampService | | The URI of the timestamp server | http://timestamp.digicert.com |
| digestAlgorithm | | The digest algorithm to use for signing and timestamping | SHA256 |
| pathToFiles | Yes | The path to the files to be signed |

## OUTPUT

none
