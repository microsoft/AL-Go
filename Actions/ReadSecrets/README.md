# Read secrets
Read secrets from GitHub secrets or Azure Keyvault for AL-Go workflows

## INPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| parentTelemetryScopeJson | | Specifies the parent telemetry scope for the telemetry signal | {} |
| getSecrets | Yes | Comma separated list of secrets to get | |

## OUTPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Secrets | A compressed json construct with all secrets base64 encoded. The secret value + the base64 value of the secret value are masked in the log |
| Settings | ReadSecrets makes changes to the Settings environment variables if there are appDependencyProbingPaths defined |

> **NOTE:** This method will also create individual environment variables for every secret encoded with base64.

### OUTPUT variables
none
