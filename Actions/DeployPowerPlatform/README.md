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
| artifacts | Yes | The artifacts to deploy or a folder in which the artifacts have been downloaded | |
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |

## OUTPUT
| Name | Description |
| :-- | :-- |
| environmentUrl | The URL for the environment. This URL is presented in the Deploy Step in summary under the environment name |