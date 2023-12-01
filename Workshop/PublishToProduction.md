# Publish To Production
In [this](ContinuousDeployment.md) section you learned how to setup a QA environment for continuous deployment.

If you follow the same process and setup an environment called PROD:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/98d4a06f-05cb-489b-afcf-4a46d9a06020) |
|-|

By default, all environments will be picked up for **continuous deployment**, but production environments will be skipped unless you add the ContinuousDeployment setting from the previous chapter. The Deployment job will succeed, but looking into the step, you will see that the PROD environment is ignored:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4b4f70ec-b503-44d9-b417-5c0ba3e65c0d) |
|-|

By adding a setting like:

```json
  "DeployToPROD": {
    "continuousDeployment": false
  }
```

The PROD environment is not even included in the CI/CD workflow, and again, setting the ContinuousDeployment to true will enable continuous deployment to the production environment.

## Publish to Environment

Menually publishing to environments is done by running the **Publish To Environment** workflow and specifying which version to publish.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/57f8441b-d414-4225-9cf4-dc2f7ce185a0) |
|-|

> [!NOTE]
> The default version is **current**. This will deploy the **current release**, which is the release tagged with *Latest* in your repository
> 
> ![image](https://github.com/microsoft/AL-Go/assets/10775043/236f1eac-3045-4b19-90a1-1f81e2ad26a6)

If you want to deploy the latest *build*, you would specify "latest" and if you want to deploy a specific version, you should specify the project version number to deploy.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ab6878fb-3480-46ec-948e-2f55efc572a5) |
|-|

Investigating the **Publish To Environment** workflow run, you will see a Deploy step like the one in CI/CD, which also includes a link to the environment.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/de8958a5-c9fb-4c9b-912c-bf037096c0bd) |
|-|

But... - would you do that without running automated tests?

So... - let's look at adding some tests.

---
[Index](Index.md)&nbsp;&nbsp;[next](AutomatedTests.md)
