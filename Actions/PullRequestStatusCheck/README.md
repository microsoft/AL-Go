# Pull Request Status Check
Check the status of a pull request build and fail the build if any jobs have failed.

## INPUT

### ENV variables
GITHUB_TOKEN

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| repository | | The repository to check the status of the pull request | github.repository |
| runId | | The run id of the pull request to check | github.run_id |

## OUTPUT
none