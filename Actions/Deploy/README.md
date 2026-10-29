# Deploy

Deploy Apps to online environment

## PTE publishing

PTE deployment installs apps in dependency order and skips app versions that are already installed or superseded by a newer installed version. Deployment waits for installation to complete; installation failures fail the deployment.

BC 30+ S2S deployments require `AdminCenter.ReadWrite.All` application permission, tenant admin consent, and registration in the administration center's Authorized Microsoft Entra apps. Existing AUTHCONTEXT structures stay unchanged, and environment API permissions remain necessary. See [deployment authorization](../../Workshop/ContinuousDeployment.md#pte-deployment-authorization) for full requirements.

`unpublishOldVersions` is an optional boolean in `DeployTo<environment>` (default `false`). It runs only after successful Scope PTE publishing. On BC 25.4 through 29, only selected apps' uninstalled versions older than the currently installed version are unpublished. On BC 30+, Business Central manages cleanup in the background, which may be delayed; timing and retained versions are not guaranteed. The setting does not control that background cleanup: AL-Go warns and skips explicit unpublish without failing deployment. Scope Dev, custom deployments, and container behavior are unchanged.

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
