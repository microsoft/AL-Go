# Determine artifacts retention days

Determines how many days artifacts should be kept for this build

Normal CI/CD builds should stay for the amount of days given in GitHub settings for builds
All other builds will be kept for 1 day

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| ArtifactsRetentionDays | Retention days for the artifacts produced by this build. -1 means generate no artifacts, 0 means use default, else it is # of days.  |
