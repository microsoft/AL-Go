# Pull Docker Image

Starts a background Docker pull of the Business Central generic image. The pull runs as a detached OS process so subsequent workflow steps execute in parallel. The RunPipeline action waits for the pull to complete (with retry on failure) before creating the container.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| dockerPullPid | The process ID of the background Docker pull |
| dockerPullImage | The name of the Docker image being pulled |
