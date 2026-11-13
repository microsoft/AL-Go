# Pull Request Status Check

Check the status of a pull request build and fail if any required jobs have failed. Matching optional build-matrix failures emit warnings instead. Other job conclusions retain their existing behavior.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| GITHUB_TOKEN | GITHUB_TOKEN must be set as an environment variable when calling this action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| optionalPatternForPrValidationJson | | JSON array of case-insensitive PowerShell wildcard patterns matching full build job names | `[]` |

The PTE and AppSource Pull Request Build workflows read settings in the StatusCheck job after checking out the build ref. The patterns are passed as JSON from the ReadSettings action's standard `Settings` environment variable. Only jobs whose API names match `Build * (*) / * (*)` can be optional, and they must also match a configured pattern. Custom jobs using this naming convention also qualify. Jobs outside this convention remain required even with a broad wildcard. Invalid JSON or input shapes fail explicitly.

Optional jobs and the workflow run may remain failed while this aggregate status check succeeds. See [optional PR builds](../../Scenarios/settings.md#optional-pr-builds).

## OUTPUT

none
