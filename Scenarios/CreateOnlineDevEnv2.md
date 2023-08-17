# #9 Create Online Development Environment from GitHub
*Prerequisites: A completed [scenario 7](UseAzureKeyVault.md).*

*To create an online development environment, we need to authenticate to our Business Central Admin API using OAuth. The Create Online Dev. Environment workflow works unattended if you provide a secret called **AdminCenterApiCredentials** (either as a GitHub Secret or in a keyvault).
At the time when writing this, the Admin Center API does not yet support S2S, meaning that the `AdminCenterApiCredentials` cannot be formatted like explained in section 3, but needs to be formatted as:*

`{"refreshtoken":"refreshtoken"}`

*Getting the refreshtoken can be done using this command on a machine with BcContainerHelper installed:*

`New-BcAuthContext -includeDeviceLogin | ConvertTo-GitHubGoCredentials | Set-Clipboard`

*If you do NOT provide an **AdminCenterApiCredentials** secret, the workflow will initiate a device code flow and you can login using [https://aka.ms/devicelogin](https://aka.ms/devicelogin) using this code and have the workflow continue. In order to get the code, you will have to inspect the details of the workflow and open the job called **Check AdminCenterApiCredentials / Initiate Device Login (open to see code)***

![Run Workflow](https://github.com/microsoft/AL-Go/assets/10775043/40f186a3-f6fe-4a67-8a21-ef50c8714b9c)

![Devicecode](https://github.com/microsoft/AL-Go/assets/10775043/5c898ee3-3ad9-4a0b-8ed5-5cdbbc0c802c)

1. On github.com, under **Actions** select the **Create Online Dev. Environment** workflow, choose **Run workflow** and specify the requested **environment name** and whether you want to **reuse the environment** if it already exists and choose **Run workflow**.
![Run Workflow](https://github.com/microsoft/AL-Go/assets/10775043/34386824-c4ca-4dab-8a81-6fa8868e2dfc)
1. When the workflow is complete, inspect the pull request to see the changes in **launch.json**. This environment can now be used from a developer but **note** that two developers cannot share one online environment.
![launch.json](https://github.com/microsoft/AL-Go/assets/10775043/797260fc-9a4b-4980-a5f1-2af3ba177c50)
1. Merge the pull request and you are ready to do rapid application development (RAD).

---
[back](../README.md)
