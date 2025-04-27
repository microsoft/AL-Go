# Determine artifacts for release

Determine artifacts for a release based on build version and projects.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| buildVersion | Yes | Build version to find artifacts for | |
| GITHUB_TOKEN | Yes | The GitHub token | |
| TOKENFORPUSH | Yes | The GhTokenWorkflow or the GitHub token (based on UseGhTokenWorkflow for PR/Commit) | |
| ProjectsJson | Yes | Json structure containing projects to search for | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| artifacts | The artifacts to publish on the release |
| commitish | The target commitish for the release |
