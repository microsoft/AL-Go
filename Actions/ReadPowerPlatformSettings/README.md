# Read Power Platform Settings

Read settings for Power Platform deployment from settings and secrets

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
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |
| environmentName | Yes | Name of environment to deploy to | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| ppEnvironmentUrl | Power Platform Environment URL |
| ppUserName | Power Platform Username |
| ppPassword | Power Platform Password |
| ppApplicationId | Power Platform Application Id |
| ppTenantId | Power Platform Tenant Id |
| ppClientSecret | Power Platform Client Secret |
| companyId | Business Central Company Id |
| environmentName | Business Central Environment Name |
