# Read settings

Read settings for AL-Go workflows

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | Project name if the repository is setup for multiple projects | . |
| buildMode | | Build mode. Only set when called from \_BuildALGoProject | Default |
| get | | Specifies which properties to get from the settings file, default is all | |
| environmentName | | Environment name for current deployment. Should only be set when environmentDeployToVariableValue is also set. | |
| environmentDeployToVariableValue | | Value of the DeployTo settings variable defined in the github environment. If this is set, the environmentName should also be set. | |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | A compressed JSON structure with ALL AL-Go settings, independent of the get parameter. If project was not specified, this will only include repository settings. |

> [!NOTE]
> This method creates individual environment variables for every setting specified in the get parameter.

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| GitHubRunnerJson | GitHubRunner in compressed Json format |
| GitHubRunnerShell | Shell for GitHubRunner jobs |
