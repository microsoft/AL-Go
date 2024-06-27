# Determine projects to build

Scans for AL-Go projects and determines which one to build

The action also computes build dimensions, based on the projects and the build modes for each of them

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| maxBuildDepth | | Specifies the maximum build depth suppored by the workflow running the action | 0 |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| ProjectsJson | An array of AL-Go projects in compressed JSON format |
| ProjectDependenciesJson | An object that holds the project dependencies in compressed JSON format |
| BuildOrderJson | An array of objects that determine that build order, including build dimensions |
| BuildAllProjects | A flag that indicates whether to build all projects or only the modified ones |
| BaselineWorkflowRunId | The ID of the workflow run from where to fetch artifacts in case when not all projects are built |
