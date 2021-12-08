# AL-Go Template
## Per Tenant Extension Project
This template repository can be used for managing Per Tenant Extensions for Business Central.

Process:
1. Click **Use this template** to create a new repository based on this template
2. Under Actions, use the **Add existing** or **add new** workflows to add your apps and test apps
3. Continuous Integration (**CI**) pipeline is automatically started
4. **Register a customer environment** using an AAD app for authentication. (Remember to register the AAD app in the Business Central environment as well)
5. When **CI** pipeline finishes, Continuous Deployment pipeline is automatically started.
6. **CD** pipeline published latest CI build to sandbox environments setup for CD
7. **Create Release** to create a release and deploy to environments
8. **CD** pipeline is automatically started, deploying released app to all environments setup for CD

## Workflows
The following workflows are using to manage the repository
### Add existing app or test app
This workflow will ask for a URL to a .zip file or an .app file. If you specify an .app file it is extracted and added to the repository as source. If you specify a .zip file it will be extracted and all source directories or .app files will be added as apps to the repository as source.
### Add new app
This workflow will add a new app to the repository. You need to specify publisher name, app name and ID range. The workflow will create an app (Hello World like AL Go) with these info in app.json.
### Add new test app
This workflow will add a new test app to the repository. You need to specify publisher name, app name and ID range. The workflow will create an app (Hello World Test App) with these info in app.json.
### CD
The Continuous Deployment (CD) workflow will run after a successful CI or Create Release pipeline. The CD workflow will enumerate the registered customer environments and deploy the newly build app to the environments selected for continuous deployment. Completed builds after a CI pipeline will be deployed to registed sandbox environments only, completed releases will be deployed to all environments registered for continuous deployment.
### CI
The Continuous Integration (CI) workflow will run with every checkin to the repository. This workflow will compile all apps and test apps, publish all apps and test apps to a Business Central test environment and run all tests in the test apps. Test results will be published and if everything passes, the apps and testapps will be available as build artifacts on this build. A successful CI pipeline will kick off the CD pipeline and publish this version to all sandbox environments, which are setup for continuous deployment.
### Create release
The Create release workflow will (as the name indicates) create a release. This workflow will (like CI) compile all apps and test apps, publish all apps and test apps to a Business Central test environment and run all tests in the test apps. Test results will be published and if everything passes, the apps and testapps will be published and tagged as a release on GitHub. A successful Create Release pipeline will kick off the CD pipeline and publish this version to all (sandbox and production) environments, which are setup for continuous deployment.
Finally, the latest release is also used as the "previous version" in CI pipelines for upgrade tests and breaking changes tests.
### Register customer environment
The Register customer environment workflow will allow you to register a customer environment for automatic deployment of the apps in this repository. You have to specify tenant ID, name and environment name of the customer environment. For authentication, you need to create an AAD App and register this AAD App in the customer environment with permissions for automation and extension management. The Client Secret for this AAD App should be stored in a GitHub or KeyVault secret. The Client ID and the name of the secret needs to be specified when registering the customer environment. Finally, you can specify whether the environment is a sandbox environment and whether you want continuous deployment of the apps from the repository.
### Update AL-Go system files
Update AL-Go system files. This step requires you to create a GitHub secret called GHTOKENWORKFLOW with a personal access token, which has permissions to update workflow files in the repository. Go to https://github.com/settings/tokens, generate a new token and check the workflow scope.
