# Determine artifactUrl

Determines the artifactUrl to use for a given project

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | | Project folder if repository is setup for multiple projects | . |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| artifact | The ArtifactUrl to use for the build |
| artifactCacheKey | The Cache Key to use for caching the artifacts when using CompilerFolder |
