# Check downgrade

Checks whether the apps that the [Deploy](../Deploy/README.md) action will deploy to a Business Central environment have lower versions than the corresponding installed apps. The apps are selected using the same logic and resolved environment settings (`DeployTo<environment>`, including `Projects`, `excludeAppIds` and `buildMode`) as the Deploy action. Test apps and dependencies are never checked, even when `includeTestAppsInSandboxEnvironment` is enabled.

If the repository contains a custom deployment script (`.github/DeployTo<EnvironmentType>.ps1`) for the environment type, the check is skipped, since the environment is not deployed using the built-in deployment.

## INPUT

### ENV variables

| Name | Required | Description |
| :-- | :-: | :-- |
| Settings | Yes | Settings from repository in compressed Json format |
| Secrets | Yes | JSON object containing the base64-encoded environment AuthContext secret |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| environmentName | Yes | Name of environment to validate | |
| artifactsFolder | Yes | Path to the downloaded artifacts to validate | |
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |
| artifactsVersion | | Artifacts version. Used to check if this is a deployment from a PR | |
| failOnAppVersionDowngrade | | Fail when an artifact app version is lower than the installed version | false |

## OUTPUT

none
