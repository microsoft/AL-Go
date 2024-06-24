# Get artifacts for deployment

Download artifacts for deployment

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| artifactsVersion | Yes | Artifacts version to download (current, prerelease, draft, latest or version number) | |
| artifactsFolder | Yes | Folder in which the artifacts will be downloaded | |

## OUTPUT

none

### ENV variables

none

### OUTPUT variables

none
