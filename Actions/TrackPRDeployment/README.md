# TrackPRDeployment

Track PR deployments against the PR branch instead of the trigger branch (e.g. main).

When deploying a PR build via PublishToEnvironment, the workflow runs on main but deploys artifacts built from a PR branch. GitHub's `environment:` key auto-creates a deployment record against main, which is misleading. This action deactivates that record and creates a new deployment against the actual PR branch, so the deployment shows correctly on the PR.

## INPUT

### ENV variables

None

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| environmentsMatrixJson | Yes | JSON string with the environments matrix from Initialization | |
| deployResult | Yes | The result of the Deploy job (success or failure) | |
| artifactsVersion | Yes | Artifacts version (PR\_\<number>) | |

## OUTPUT

None
