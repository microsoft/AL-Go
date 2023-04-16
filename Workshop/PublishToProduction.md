# Publish To Production
In [this](ContinuousDeployment.md) section you just learned how to setup a QA environment for continuous deployment.

If you follow the same process for setting up an environment, but postfix your environment name with **(Production)**, like:

| ![image](https://user-images.githubusercontent.com/10775043/232310956-96179562-e101-4b90-9a01-12c8c316cfd3.png) |
|-|

Then the environment will not be picked up for **continuous deployment**, but can only be deployed to using the **Publish To Environment** workflow.

**Note** that there are plans to update the mechanism for when an environment is picked up for deployment and support some settings to allow this, but if these settings are not present, we will still support the current supported mechanism.

Publish to the production environment by running the workflow and specifying which version to deploy and what environment to deploy to.

| ![image](https://user-images.githubusercontent.com/10775043/232312134-0028a08d-1004-43f2-8127-aeeee8ed1a5e.png) |
|-|

Note that the default version is current - meaning it will use the **current release**. If you want to just use the latest build, you need to use **latest**.


But... - would you do that without running automated tests?

---
[Index](Index.md)&nbsp;&nbsp;[next](AutomatedTests.md)
