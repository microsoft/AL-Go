# Run AL-Go Override

Runs an AL-Go-native script override from the project's `.AL-Go` folder.

This action provides a generic mechanism for invoking customer-supplied
override scripts at well-known extension points in AL-Go workflows. It is
independent of BcContainerHelper and the `Run-AlPipeline` script overrides
(which are still applied internally by the `RunPipeline` action).

If the project does not contain an override script for the requested
`overrideName`, the action is a silent no-op so that workflows can call it
unconditionally.

## How to author an override

Add a PowerShell script named `<overrideName>.ps1` to your project's
`.AL-Go` folder. The script is invoked with a single `[Hashtable] $parameters`
argument (the same calling convention used by BCH script overrides).

Example `.AL-Go/BuildInitialize.ps1`:

```powershell
Param(
    [Hashtable] $parameters
)
Write-Host "BuildInitialize running for project '$($parameters.project)'"
```

## Supported override names

| Override name | Where it runs | Notes |
| :-- | :-- | :-- |
| `BuildInitialize` | First step of the build workflow (`_BuildALGoProject.yaml`), immediately after Checkout | Runs **before** `Read settings`, so AL-Go settings, secrets and most environment variables are not yet available. |

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | Project folder (relative to repository root) | . |
| overrideName | Yes | Name of the override to run. Must be one of the supported override names. | |
| parametersJson | | Compressed JSON object with parameters to pass to the override script as a hashtable | `{}` |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
