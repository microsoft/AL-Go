# Releasing the apps
Releasing an app is an integral part of DevOps and it is important to understand how you release the apps in a repository, how this affects versioning and how you can create a hotfix to an already released set of apps.

The recommended branching strategy for AL-Go for GitHub is shown here:

| ![image](https://user-images.githubusercontent.com/10775043/231577806-6ba0657e-ba8e-46c2-99e2-710e30ebec88.png) |
|-|

Every time you release a version of the apps, you increment the version of the apps at the same time.
This means that a hotfix created from the release branch will still have a version number, which is lower than the next version from the main branch.
Let's see this in action.

Select **Actions**, select the **Create Release** workflow and click **Run workflow**. Enter the following values in the form:

| Name | Value |
| :-- | :-- |
| App version | `latest` |
| Name of this release | `v1.0` |
| Tag of this release | `1.0.4` |
| Prerelease | `N` |
| Draft | `N` |
| Create Release Branch | `Y` |
| New Version Number | `+1.0` |
| Direct COMMIT | `N` |

After completion of the **Create release** workflow, you can select **Code** and see that you have 1 release:

![image](https://user-images.githubusercontent.com/10775043/231591177-d2a85451-a717-4f87-a2ae-55e26c19a17f.png)

Also, you have a Pull request waiting, which increments version number by 1.0.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/3955d853-fc6a-447a-a5e0-8a56983462d2) |
|-|

**Merge the Pull request**, **delete the temporary branch** and select **Actions** to see that a Merge Pull request was kicked off.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/96ff7600-ec05-411f-9335-aa389feabbd7) |
|-|

Inspecting the build from the Pull request, you will see that the artifacts are now **2.0.5.0**, **app1** is **2.2.5.0** and **app2** is **2.0.5.0**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d5382e5d-ac65-44f2-bb58-69b148764e1a) |
|-|

And all subsequent builds from main will now be 2.x. You will also see that the annotation stating that **No previous release found** has now gone.
All builds from main will use the latest release version for upgrade testing. Inspecting the build step in the workflow, reveals that AL-Go for GitHub was able to locate the previous release

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/2d404467-9311-4cc4-97fc-99961c29f7d0) |
|-|

Now, if you at some point in time need to create a hotfix for version **1.0.4**, you can simply select **Code** and switch to the release branch.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1169ef76-dd23-49c5-8f02-098021f8951e) |
|-|

Now you can navigate to the **HelloWorld.al** file in the **app2** app, make a **simple change** and **commit the changes**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/0e44c89b-041e-4260-abe0-cbf9bb59affa) |
|-|

Select **Actions** and see that a build was kicked off in the release branch.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/06b8e92b-21e7-424c-9208-e17722feeb15) |
|-|

This version will use the **latest released build**, which has a version number lower than the one you are building as previous release and will use the version numbers from the release branch for versioning.
After the build is completed, you will need to release this new build in order for subsequent CI/CD builds from main to see the new bits as a release.

The artifacts in the hotfix build looks like this:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a53fbe6a-0ec3-4e2d-a5d6-fe89a9cb3fdd) |
|-|

where the branch name main has been replaced by the release branch name.

OK, so that is clear, versioning and releasing, pretty smart - but what is this project concept?

---
[Index](Index.md)&nbsp;&nbsp;[next](Projects.md)

