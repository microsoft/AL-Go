# Read settings

Read settings for AL-Go workflows

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| GITHUB_TOKEN | Optional token used to read repository custom properties when `githubToken` is not supplied. |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | Project name if the repository is setup for multiple projects | . |
| buildMode | | Build mode. Only set when called from \_BuildALGoProject | Default |
| workflowName | | Workflow name for which the settings are to be read | github.workflow |
| get | | Specifies which properties to get from the settings file, default is all | |
| githubToken | | Token used to read repository custom properties. Defaults to `GITHUB_TOKEN` or the workflow token. | |

Repository custom properties are fetched only when a matching `ConditionalSettings` block uses the `customProperties` condition. The token must have read access to the target repository; API and permission errors fail the action instead of being treated as missing properties.

Actions that re-read settings internally (for example, `DetermineProjectsToBuild`) provide the workflow token through their step's `GITHUB_TOKEN` environment variable. An existing `GITHUB_TOKEN` environment variable takes precedence. The token is not persisted to later steps.

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
