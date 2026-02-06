# Check Auth Context

Check if Admin Center Api Credentials / AuthContext are provided in secrets. If not, initiate device code flow for authentication.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets must be set to the secrets output from ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| secretName | Yes | Name of the secret to check (comma-separated list to check multiple in order) | |
| environmentName | | Environment name (for error messages when deploying to environments) | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| deviceCode | Device code for authentication (only set if device login is required) |
