# BuildReferenceDocumentation

Build documentation using [ALDoc](https://go.microsoft.com/fwlink/?linkid=2247728) and [DocFx](https://dotnet.github.io/docfx)

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| artifacts | Yes | The artifacts to build documentation for or a folder in which the artifacts have been downloaded | |

## OUTPUT

none
