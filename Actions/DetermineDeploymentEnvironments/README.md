# Determine Deployment Environments

Determines the environments to be used for a build or a publish

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| GITHUB_TOKEN | GITHUB_TOKEN must be set as an environment variable when calling this action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| getEnvironments | Yes | Specifies the pattern of the environments you want to retrieve (\* for all) | |
| type | Yes | Type of deployment to get environments for (CD, Publish or All) | |

## OUTPUT

| EnvironmentsMatrixJson | The Environment matrix to use for the Deploy step in compressed JSON format |
| DeploymentEnvironmentsJson | Deployment Environments with settings in compressed JSON format |
| EnvironmentCount | Number of Deployment Environments |
| UnknownEnvironment | Flag determining whether we try to publish to an unknown environment (invoke device code flow) |
| GenerateALDocArtifact | Flag determining whether to generate the ALDoc artifact |
| DeployALDocArtifact | Flag determining whether to deploy the ALDoc artifact to GitHub Pages |

### ENV variables
