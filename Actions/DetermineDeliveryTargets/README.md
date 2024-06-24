# Determine Delivery Targets

Determines the delivery targets to use for the build

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with delivery target context secrets must be read by a prior call to the ReadSecrets Action (if checkContextSecrets is set to Y) |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| projectsJson | | Projects folder if repository is setup for multiple projects | . |
| checkContextSecrets | | Determines whether to check that delivery targets have a corresponding context secret defined | true |

## OUTPUT

| Name | Description |
| :-- | :-- |
| deliveryTargets | Compressed JSON array containing all delivery targets to use for the build |
| contextSecrets | A comma-separated string with the names of the secrets to pass to ReadSecrets |

### ENV variables
