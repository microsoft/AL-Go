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

After completion of the **Create release** workflow, you can select **Code** and see that you have 1 releases:
![image](https://user-images.githubusercontent.com/10775043/231591177-d2a85451-a717-4f87-a2ae-55e26c19a17f.png)

Also, you have a Pull request waiting, which increments version number by 1.0.

| ![image](https://user-images.githubusercontent.com/10775043/231591451-040c40d7-75d0-43c2-af8f-744ae29f36e8.png) |
|-|

**Merge the Pull request**, **delete the temporary branch** and select **Actions** to see that a Merge Pull request was kicked off.

| ![image](https://user-images.githubusercontent.com/10775043/231591751-b2ebe08a-689c-446b-84d5-3c7c285e754c.png) |
|-|

Inspecting the build from the Pull request, you will see that the artifacts are now **2.0.5.0**, **app1** is **2.2.5.0** and **app2** is **2.0.5.0**.

| ![image](https://user-images.githubusercontent.com/10775043/231592915-f1f7e4d7-061c-42cd-9f37-dfd06c11b09d.png) |
|-|

And all subsequent builds from main will now be 2.x. You will also see that the annotation stating that **No previous release found** has now gone.
All builds from main will use the latest release version for upgrade testing. Inspecting the build step in the workflow, reveals that AL-Go for GitHub was able to locate the previous release

| ![image](https://user-images.githubusercontent.com/10775043/231593914-0f83255e-d027-4826-b23a-17625ee3c2fb.png) |
|-|

Now, if you at some point in time need to create a hotfix for version **1.0.4**, you can simply select **Code** and switch to the release branch.

| ![image](https://user-images.githubusercontent.com/10775043/231594145-f18ae77d-895b-41db-a04b-711028486896.png) |
|-|

Now you can navigate to the **HelloWorld.al** file, make a **simple change** and **commit the changes**.

| ![image](https://user-images.githubusercontent.com/10775043/231594386-fbde022d-a53c-4eef-928d-92b2b2dace66.png) |
|-|

Select **Actions** and see that a build was kicked off in the release branch.

| ![image](https://user-images.githubusercontent.com/10775043/231594500-1d86a0f5-a001-4244-9005-7275e1b72278.png) |
|-|

This version will use the **latest released build**, which has a version number lower than the one you are building as previous release and will use the version numbers from the release branch for versioning.
After the build is completed, you will need to release this new build in order for CI/CD to see the new bits as a release.

The artifacts in the hotfix build looks like this:

| ![image](https://user-images.githubusercontent.com/10775043/231595957-cd61fc0e-f7c7-4dc3-8fe7-dccad3de32a0.png) |
|-|

where the branch name main has been replaced by the release branch name.

OK, so that is clear, versioning and releasing, pretty smart - but what is this project concept?

---
[Index](Index.md)&nbsp;&nbsp;[next](Projects.md)

