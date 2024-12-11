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
| Use workflow from | `Branch: main` |
| App version | `latest` |
| Name of this release | `v1.0` |
| Tag of this release | `1.0.4` |
| Prerelease | :black_square_button: |
| Draft | :black_square_button: |
| Create Release Branch | :ballot_box_with_check: |
| New Version Number | `+1` |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/8ae1628e-0368-4af3-8c01-16e3e8a62917) |
|-|

After completion of the **Create release** workflow, you can select **Code** and see that you have 1 release:

![image](https://github.com/microsoft/AL-Go/assets/10775043/c23b0d4f-9476-462d-ace6-788337164f88)

Also, you have a Pull request waiting, which increments version number by 1.0.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/83c9ea64-f3df-4bd1-8fd1-5a2b2c85e9e2) |
|-|

**Merge the Pull request**, **delete the temporary branch** and select **Actions** to see that a Merge Pull request was kicked off.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/79704699-7cd4-4589-a7ff-d7a98cd29cca) |
|-|

Inspecting the build from the Pull request, you will see that the artifacts are now **2.0.7.0**, **app1** is **2.2.7.0** and **app2** is **2.0.7.0** (in my repository)

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/22d28d32-b826-450f-af6c-77982235b57d) |
|-|

> \[!NOTE\]
> All subsequent builds from main will now be 2.x. You will also see that the annotation stating that **No previous release found** has now gone and all builds from main will use the latest release version for upgrade testing.

Inspecting the **build** step in the workflow, reveals that AL-Go for GitHub was able to locate the previous release

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/0b6cdefb-c379-4392-b11c-b714f19f75fb) |
|-|

Now, if you at some point in time need to create a hotfix for version **1.0.6**, you can simply select **Code** and switch to the release branch.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e4a3b1fd-9c66-4558-aa6a-48b410e26cc9) |
|-|

In the release branch, navigate to the **HelloWorld.al** file in the **app2** app, make a simple change and commit the changes directory to the release branch

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/addda836-1cd4-478d-b33a-f62f46084851) |
|-|

Select **Actions** and see that a build was kicked off in the release branch.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5ae406bc-31e0-4433-ac5d-f9d3b12f7668) |
|-|

> \[!NOTE\]
> This build will use the latest released build, which has a version number lower than the one you are building as previous release and will use the version numbers from the release branch for versioning.
> After the build is completed, you will need to release this new build in order for subsequent CI/CD builds from main to see the new bits as a release.

The artifacts in the hotfix build looks like this:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/54dda4c3-4510-4b48-8437-24a0bece09a1) |
|-|

where the branch name main has been replaced by the release branch name and if you want to release this hotfix, you can run the **Create Release** and specify these parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: release/1.0.6` |
| App version | `latest` |
| Name of this release | `v1.0.8` |
| Tag of this release | `1.0.8` |
| Prerelease | :black_square_button: |
| Draft | :black_square_button: |
| Create Release Branch | :black_square_button: |
| New Version Number | |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

> \[!NOTE\]
> You must select to use workflow from the release branch. Else the create release workflow cannot locate the build in the release branch.
> In this case, we select to not create a new release branch. We can just create any future hotfixes from the existing release branch if needed. We can also always create a release branch from a release later.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e65f7a48-8c4d-426f-a6c4-97bb0d14b34d) |
|-|

After the release has been created we can (under Code) see that we have 2 releases:

![image](https://github.com/microsoft/AL-Go/assets/10775043/ff0719ac-5510-4fca-9f54-10e19c3aaa4e)

and clicking Releases will show the content of the releases:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/6e52727e-bff3-431c-88ac-264965ad911f) |
|-|

> \[!NOTE\]
> GitHub sorts the releases after the tag and sorting only works correctly if the tag is SemVer compatible (i.e. 3 segments). This is the reason why AL-Go for GitHub forces you to enter a SemVer compatible version number in the tag when creating a new release.

OK, so that is clear, versioning and releasing, pretty smart - but what is this project concept?

______________________________________________________________________

[Index](Index.md)  [next](Projects.md)
