# Read secrets
Read secrets from GitHub secrets or Azure Keyvault for AL-Go workflows
The secrets read and added to the output are the secrets specified in the getSecrets parameter
Additionally, the secrets specified by the authToken secret in AppDependencyProbingPaths are read if appDependencyProbingPathsSecrets is specified in getSecrets

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
| getSecrets | Yes | Comma separated list of secrets to get (add appDependencyProbingPathsSecrets to request secrets needed for resolving dependencies in AppDependencyProbingPaths) | |

## OUTPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Secrets | A compressed json construct with all secrets base64 encoded. The secret value + the base64 value of the secret value are masked in the log |

### OUTPUT variables
none
