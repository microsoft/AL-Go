# Determine secrets

Determine the secrets needed for the workflow

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| getSecrets | Yes | Comma-separated list of secrets to get (add appDependencySecrets to request secrets needed for resolving dependencies in AppDependencyProbingPaths and TrustedNuGetFeeds, add TokenForPush in order to request a token to use for pull requests and commits). Secrets preceded by an asterisk are returned encrypted | |
| useGhTokenWorkflowForPush | false | Determines whether you want to use the GhTokenWorkflow secret for TokenForPush | false |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| FORMATSTR | A format string to be used when transferring the secrets to ReadSecrets |
| S0,S1,S2,...,S31 | The actual names of the GitHub secrets to look for |
