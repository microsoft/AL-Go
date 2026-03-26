# Download Previous Release

Downloads the latest release apps for use as a baseline in AppSourceCop validation and upgrade testing.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | The AL-Go project for which to download previous release apps | '.' |

## OUTPUT

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| PreviousAppsPath | Path to the folder containing the downloaded previous release apps. Empty if no release was found. |
