# Deploy Power Platform

Deploy the Power Platform solution from the artifacts folder

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with delivery target context secrets must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| environmentName | Yes | Name of environment to deploy to |
| artifactsFolder | | Path to the downloaded artifacts to deploy (when deploying from a build) | |
| solutionFolder | | Path to the unpacked solutions to deploy (when deploying from branch) | |
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |

Either artifactsFolder or solutionFolder needs to be specified

## OUTPUT

| Name | Description |
| :-- | :-- |
| environmentUrl | The URL for the environment. This URL is presented in the Deploy Step in summary under the environment name |
