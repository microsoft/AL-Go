# Publish To Production
In [this](ContinuousDeployment.md) section you learned how to setup a QA environment for continuous deployment.

If you follow the same process and setup an environment called PROD:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/98d4a06f-05cb-489b-afcf-4a46d9a06020) |
|-|

By default, all environments will be picked up for **continuous deployment**, but production environments will be skipped unless you add the ContinuousDeployment setting from the previous chapter. The Deployment job will succeed, but looking into the step, you will see:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4b4f70ec-b503-44d9-b417-5c0ba3e65c0d) |
|-|

By adding a setting like:

```json


```

should be but can only be deployed to using the **Publish To Environment** workflow.

**Note** that there are plans to update the mechanism for when an environment is picked up for deployment, to allow deployment to environments postfixed with **(Production)**. This will be done by including some settings. But until those settings are present, the mechanism will work as described here.

Publish to the production environment by running the workflow and specifying which version to deploy, and which environment to deploy to.

**Note** that the default version is "current". This will deploy the **current release**. If you specify *latest* you will get the **latest build**

> Current is the **current release**, which is the release tagged with *Latest* in your repository
> 
> ![image](https://github.com/microsoft/AL-Go/assets/10775043/236f1eac-3045-4b19-90a1-1f81e2ad26a6)

And... again, if you want to just use the latest *build*, you would specify "latest":

| ![image](https://user-images.githubusercontent.com/10775043/232312134-0028a08d-1004-43f2-8127-aeeee8ed1a5e.png) |
|-|

But... - would you do that without running automated tests?

So... - let's look at adding some tests.

---
[Index](Index.md)&nbsp;&nbsp;[next](AutomatedTests.md)
