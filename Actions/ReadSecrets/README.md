# Read secrets

Read secrets from GitHub secrets or Azure Keyvault for AL-Go workflows
The secrets read and added to the output are the secrets specified in the getSecrets parameter
Additionally, the secrets specified by the authTokenSecret in AppDependencyProbingPaths and TrustedNuGetFeeds are read if appDependencySecrets is specified in getSecrets
All secrets included in the Secrets output are Base64 encoded to avoid issues with national characters

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| gitHubSecrets | Yes | A JSON structure with all secrets needed. The structure already contains the existing GitHub secrets | |
| useGhTokenWorkflowForPush | false | Determines whether you want to use the GhTokenWorkflow secret for TokenForPush | false |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| Secrets | A compressed json construct with all requested secrets base64 encoded. The secret value + the base64 value of the secret value are masked in the log |
| TokenForPush | The token to use when workflows are pushing changes (either directly, or via pull requests). This is either the GITHUB_TOKEN or the GhTokenWorkflow secret (based on the env variable useGhTokenWorkflowForPush) |
