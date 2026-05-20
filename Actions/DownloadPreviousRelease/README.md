# Download Previous Release

Downloads the latest release apps for the current branch, for use as a baseline in AppSourceCop validation and upgrade testing.
The release is determined based on the target branch (for pull requests) or the current branch (for pushes).

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| project | | The AL-Go project for which to download previous release apps | '.' |

## OUTPUT

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| PreviousAppsPath | Path to the folder containing the downloaded previous release apps. |
