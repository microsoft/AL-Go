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
| get | | Specifies which properties to get from the settings file, default is all | |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | A compressed JSON structure with ALL AL-Go settings, independent of the get parameter. If project was not specified, this will only include repository settings. |

> \[!NOTE\]
> This method creates individual environment variables for every setting specified in the get parameter.

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| GitHubRunnerJson | GitHubRunner in compressed Json format |
| GitHubRunnerShell | Shell for GitHubRunner jobs |
