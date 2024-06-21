# Pull Request Status Check

Check the status of a pull request build and fail the build if any jobs have failed.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| GITHUB_TOKEN | GITHUB_TOKEN must be set as an environment variable when calling this action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

none
