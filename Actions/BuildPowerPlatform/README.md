# Build Power Platform
Build the Power Platform solution
## Parameters
### shell (default powershell)
Shell in which you want to run the action (powershell or pwsh)
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### solutionFolder (default '')
The Power Platform solution path
### outputFolder (default '')
Output folder where the Power platform solution zip file will be placed
### outputFileName (default '.')
The name of the Power Platform solution zip file
### companyId (default '')
The Business Central company ID
### environmentName (default '')
The Business Central environment name
### appVersion (required)
Major and Minor part of app Version number
### appBuild (required)
Build part of app Version number
### appRevision (required)
Revision part of app Version number
