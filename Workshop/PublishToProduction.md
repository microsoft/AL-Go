# Publish To Production
In [this](ContinuousDeployment.md) section you learned how to setup a QA environment for continuous deployment.

If you follow the same process for setting up an environment, but postfix your environment name with **(Production)**, like:

| ![image](https://user-images.githubusercontent.com/10775043/232310956-96179562-e101-4b90-9a01-12c8c316cfd3.png) |
|-|

Then that environment will not be picked up for **continuous deployment**, but can only be deployed to using the **Publish To Environment** workflow.

**Note** that there are plans to update the mechanism for when an environment is picked up for deployment, to allow deployment to environments postfixed with **(Production)**. This will be done by including some settings. But until those settings are present, the mechanism will work as described here.

Publish to the production environment by running the workflow and specifying which version to deploy, and which environment to deploy to.

**Note** that the default version is "current" - this will deploy the **release** with the name "current". If you want to just use the latest *build*, you would specify "latest":

| ![image](https://user-images.githubusercontent.com/10775043/232312134-0028a08d-1004-43f2-8127-aeeee8ed1a5e.png) |
|-|

But... - would you do that without running automated tests?

---
[Index](Index.md)&nbsp;&nbsp;[next](AutomatedTests.md)
