# Run AL-Go Hook

Runs an AL-Go hook script from the project's `.AL-Go` folder.

This action provides a generic mechanism for invoking customer-supplied
hook scripts at well-known extension points in AL-Go workflows. It is
independent of BcContainerHelper and the `Run-AlPipeline` script overrides
(which are still applied internally by the `RunPipeline` action).

If the project does not contain a hook script for the requested
`hookName`, the action is a silent no-op so that workflows can call it
unconditionally.

## How to author a hook

Add a PowerShell script named `<hookName>.ps1` to your project's
`.AL-Go` folder. The script is invoked with a single `[Hashtable] $parameters`
argument.

The hashtable always contains at least the following context key, which is
populated automatically:

| Key | Description |
| :-- | :-- |
| `project` | The project folder, relative to the repository root. |

Any keys supplied via `parametersJson` are merged on top of these defaults
(caller-supplied values win on key collision).

Example `.AL-Go/BuildInitialize.ps1`:

```powershell
Param(
    [Hashtable] $parameters
)
Write-Host "BuildInitialize hook running for project '$($parameters.project)'"
```

## Supported hook names

| Hook name | Where it runs | Notes |
| :-- | :-- | :-- |
| `BuildInitialize` | Build workflow (`_BuildALGoProject.yaml`), immediately after `Read settings` | AL-Go settings are available as environment variables; secrets are not yet read at this point. |

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | Project folder (relative to repository root) | . |
| hookName | Yes | Name of the hook to run. Must be one of the supported hook names. | |
| parametersJson | | Compressed JSON object with parameters to pass to the hook script as a hashtable | `{}` |

## OUTPUT

### ENV variables

none

### OUTPUT variables

none
