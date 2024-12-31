# Calculate Artifact Names

Calculate Artifact Names for AL-Go workflows

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | Yes | Name of the built project or . if the repository is setup for single project | |
| buildMode | Yes |Build mode used when building the artifacts | |
| suffix | | A suffix to add to artifacts names. **Note:** if a suffix is specified, the current date will be added extra | Build version |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| AppsArtifactsName | Artifacts name for Apps |
| PowerPlatformSolutionArtifactsName | Artifacts name for PowerPlatform Solution |
| DependenciesArtifactsName | Artifacts name for Dependencies |
| TestAppsArtifactsName | Artifacts name for TestApps |
| TestResultsArtifactsName | Artifacts name for TestResults |
| BcptTestResultsArtifactsName | Artifacts name for BcptTestResults |
| PageScriptingTestResultsArtifactsName | Artifacts name for PageScriptingTestResults |
| PageScriptingTestResultDetailsArtifactsName | Artifacts name for PageScriptingTestResultDetails |
| BuildOutputArtifactsName | Artifacts name for BuildOutput |
| ContainerEventLogArtifactsName | Artifacts name for ContainerEventLog |
| BuildMode | Build mode used when building the artifacts |
