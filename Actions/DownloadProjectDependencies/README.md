# Download project dependencies

Downloads artifacts from AL-Go projects, that are dependencies of a given AL-Go project

The action constructs arrays of paths to .app files, that are dependencies of the apps in an AL-Go project

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets must be read by a prior call to the ReadSecrets Action with appDependencySecrets in getSecrets |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | Yes | The AL-Go project for which to download dependencies | |
| buildMode | Yes | The build mode to use to downloaded to most appropriate dependencies. If a dependency project isn't built in the provided build mode, then the artifacts from the default mode will be used | |
| projectsDependenciesJson | Yes | A JSON-formatted object that maps a project to an array of its dependencies | |
| baselineWorkflowRunId | No | The ID of the workflow run that was used as baseline for the current build | '0' |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| appFolders | A JSON-formatted array of appFolders |
| testFolders | A JSON-formatted array of testFolders |
| bcptTestFolders | A JSON-formatted array of bcptTestFolders |

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| DownloadedApps | A JSON-formatted list of paths to .app files, that dependencies of the apps |
| DownloadedTestApps | A JSON-formatted list of paths to .app files, that dependencies of the test apps |
