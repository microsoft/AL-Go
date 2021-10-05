# Add customer environment
Register customer environemnt for AL-Go continuous deployment
## Parameters
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### name (required)
Customer Name
### tenantId (required)
Customer Tenant ID
### environmentName (required)
Customer Environment Name
### aadAppClientId (default '')
AAD App Client Id or blank for RefreshToken
### aadAppClientSecretName (default '')
Name of Secret containing AAD App Client Secret or RefreshToken
### productionEnvironment (default N)
Production Environment (Y/N)
### continuousDeployment (default N)
Continuous Deployment (Y/N)
### directCommit (default N)
Direct Commit (Y/N)
