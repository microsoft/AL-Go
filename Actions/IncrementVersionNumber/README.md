# Increment version number
Increment version number in AL-Go repository

## INPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actor | | The GitHub actor running the action | github.actor |
| token | | The GitHub token running the action | github.token |
| parentTelemetryScopeJson | | Specifies the parent telemetry scope for the telemetry signal | {} |
| projects | | List of project names if the repository is setup for multiple projects (* for all projects) | * |
| versionNumber | Yes | Updated Version Number. Use Major.Minor for absolute change, use +Major.Minor for incremental change | |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT
none
