# Deliver

Deliver App to deliveryTarget (AppSource, Storage, or...)

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with delivery target context secrets must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| projects | | Comma-separated list of projects to deliver | * |
| deliveryTarget | Yes | Delivery target (AppSource, Storage, GitHubPackages,...) | |
| artifacts | Yes | The artifacts to deliver or a folder in which the artifacts have been downloaded | |
| type | | Type of delivery (CD or Release) | CD |
| atypes | | Artifact types to deliver | Apps,Dependencies,TestApps |
| goLive | | Only relevant for AppSource delivery type. Promote AppSource App to Go Live? | false |

## OUTPUT

none
