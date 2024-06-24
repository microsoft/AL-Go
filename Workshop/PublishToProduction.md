# Publish To Production

In [this](ContinuousDeployment.md) section you learned how to setup a QA environment for continuous deployment.

If you follow the same process and setup an environment called PROD and add the same AUTHCONTEXT secret to that environment.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1008fcf4-ed2a-4cc1-a786-3b5cf6692266) |
|-|

> \[!NOTE\]
> You can add protection rules to environments in GitHub, like which branches can deploy to this environment and which users should review every deployment to this environment as well.

By default, all environments will be picked up for **continuous deployment**, but production environments will be skipped unless you add the ContinuousDeployment setting from the previous chapter. The Deployment job will succeed, but looking into the step, you will see that the PROD environment is ignored:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/205e4eed-919c-4cb0-bb54-924857b53898) |
|-|

By adding a setting like this to your repository settings file (.github/AL-Go-Settings.json)

```json
  "DeployToPROD": {
    "continuousDeployment": false
  }
```

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a0822808-f773-49dc-ba4d-753a5677ca38) |
|-|

Then the PROD environment is not even included in the CI/CD workflow, and again, setting the ContinuousDeployment to true will enable continuous deployment to the production environment.

## Publish to Environment

Menually publishing to environments is done by running the **Publish To Environment** workflow and specifying which version to publish.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/57f8441b-d414-4225-9cf4-dc2f7ce185a0) |
|-|

> \[!NOTE\]
> The default version is **current**. This will deploy the **current release**, which is the release tagged with *Latest* in your repository.
>
> ![image](https://github.com/microsoft/AL-Go/assets/10775043/5c653d70-106e-4d0a-9684-ae91275abb77)

If you want to deploy the latest *build*, you would specify "latest" and if you want to deploy a specific version, you should specify the project version number to deploy.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ab6878fb-3480-46ec-948e-2f55efc572a5) |
|-|

Investigating the **Publish To Environment** workflow run, you will see a Deploy step like the one in CI/CD, which also includes a link to the environment.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/9bbfac60-e191-412f-9ff0-313ce4cd7379) |
|-|

But... - would you do that without running automated tests?

So... - let's look at adding some tests.

______________________________________________________________________

[Index](Index.md)  [next](AutomatedTests.md)
