# Deploy

Deploy Apps to online environment

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with delivery target context secrets must be read by a prior call to the ReadSecrets Action |
| deviceCode | When deploying to a single environment which doesn't have an AuthContext, we will wait for the user to finalize the deviceflow with this deviceCode |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| environmentName | Yes | Name of environment to deploy to |
| artifactsFolder | Yes | Path to the downloaded artifacts to deploy | |
| type | | Type of delivery (CD or Release) | CD |
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |

## OUTPUT

| Name | Description |
| :-- | :-- |
| environmentUrl | The URL for the environment. This URL is presented in the Deploy Step in summary under the environment name |
