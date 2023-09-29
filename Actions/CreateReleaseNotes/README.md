# Creates release notes
Creates release notes for a release, based on a given tag and the tag from the latest release

## INPUT

### ENV variables
none

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| parentTelemetryScopeJson | | Specifies the parent telemetry scope for the telemetry signal | {} |
| tag_name | Yes | This release tag name | |
| target_commitish | | Last commit to include in release notes | Latest |

## OUTPUT

### ENV variables
none

### OUTPUT variables
| Name | Description |
| :-- | :-- |
| ReleaseBranch | Name of the release branch |
| ReleaseNotes | Release notes generated based on the changes |
