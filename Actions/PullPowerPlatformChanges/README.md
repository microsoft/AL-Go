# Pull Power Platform Changes
Pull the Power Platform solution from the specified Power Platform environment
## Parameters
### shell (default powershell)
Shell in which you want to run the action (powershell or pwsh)
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### solutionName
The Power Platform solution to get the changes from.
### deploySettings
The deploy settings
### authSettings
The auth settings
### directCommit
If true, the changes will be committed directly to the branch. If not, the changes will be committed to a branch named after the solution.
