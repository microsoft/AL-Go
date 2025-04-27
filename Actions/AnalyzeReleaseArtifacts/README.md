# Creates release notes

Creates release notes for a release, based on a given tag and the tag from the latest release

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
| ReleaseVersion | The release version |
| ReleaseNotes | Release notes generated based on the changes |
