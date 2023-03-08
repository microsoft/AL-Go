# Determine projects to build
Scans for AL-Go projects and determines which one to build.
If the action 
The action also computes build dimensions, based on the projects and the build modes for each of them

## Outputs
### ProjectsJson:
An array of AL-Go projects in compressed JSON format

### ProjectDependenciesJson:
An object that holds the project dependencies in compressed JSON format
  
### BuildOrderJson: 
An array of objects that determine that build order, including build dimensions
