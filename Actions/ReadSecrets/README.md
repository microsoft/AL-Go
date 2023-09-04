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
| getSecrets | Yes | Comma separated list of secrets to get (add appDependencyProbingPathsSecrets to request secrets needed for resolving dependencies in AppDependencyProbingPaths, add TokenForPush in order to request a token to use for pull requests and commits) | |
| useGhTokenWorkflowForPush | false | Determines whether you want to use the GhTokenWorkflow secret for TokenForPush | |
| tempGhTokenWorkflow | false | Temporary Access Token, which overrides GhTokenWorkflow if present | |

## OUTPUT

### ENV variables
none

### OUTPUT variables
| Name | Description |
| :-- | :-- |
| Secrets | A compressed json construct with all requested secrets base64 encoded. The secret value + the base64 value of the secret value are masked in the log |
| TokenForPush | The token to use when workflows are pushing changes (either directly, or via pull requests). This is either the GITHUB_TOKEN or the GhTokenWorkflow secret (based on the env variable useGhTokenWorkflowForPush)  |

