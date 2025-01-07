# Versioning

Understanding how AL-Go for GitHub is doing **versioning** and **naming** is important for your day to day use of AL-Go for GitHub.

As we saw earlier, the **artifacts** from the first successful build in my repository was called version **repo1-main-Apps-1.0.4.0**.
Downloading the artifact and unpacking reveals the app inside. The app inside is using the same naming strategy as VS Code: `<publisher>_<name>_<version>`

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/907ff953-6496-46ff-b3bc-fc934da7bb50) |
|-|

Here, the app has the same version number as the artifact, but is it always like that?

As you know, the version number consists of 4 segments: **major.minor.build.revision**.

- The version number of the build artifact is 100% controlled by AL-Go for GitHub. The **major.minor** are taken from a setting called **RepoVersion** (default is 1.0) and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The version number of the app (inside the build artifact) is controlled by **app.json** and **AL-Go for GitHub**. The **major.minor** part is taken from **app.json** and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The **build** segment is (by default) the GITHUB_RUN_NUMBER, which is a unique number for each time the CI/CD workflow is run, starting with 1.
- The **revision** segment is (by default) the GITHUB_RUN_ATTEMPT, which is the number of attempts, starting with 0. In my example above, I did re-run the CI/CD workflow once to end up with .1.

> \[!NOTE\]
> Using VersioningStrategy 3, the **build** segment is also controlled by **app.json** and the revision segment is the GITHUB_RUN_NUMBER.

In order to better understand this, select **Code** and navigate to the **app.json** file under the **app1** folder. Edit the file and change the version number to **1.2.3.4**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/df24b30b-df74-4def-9134-49f8bc8e13f1) |
|-|

**Commit** the changes directly, select **Actions** and wait for the build to complete.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/c2c45e8d-aeb0-4da1-8b23-85eee843a25a) |
|-|

Select the **Update app.json** workflow, **scroll down** to the artifacts and **download** the new apps artifact and open it.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f5009c5f-2cf6-45ec-9de5-c7473722e092) |
|-|

> \[!NOTE\]
> The project (in this case the repository), which really is a collection of apps, is still version **1.0** (RepoVersion never changed - is still 1.0 = default) and **app1** is **1.2** (major and minor from app.json). Build is **5** (5th build in my repo) and revision is still **0**.

Scroll back up, locate the **Re-run all jobs** button and click it. Wait for the **2nd attempt** to complete and inspect the artifact for the re-run.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4a20ed83-8fb7-4a0a-b030-e1c1cb392a27) |
|-|

Now revision became **1** as we had a 2nd attempt at building the app.

Next, let's create another app, by running the **Create a new app** workflow again in the same repo and specify:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `.` |
| Name | `app2` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `56000..56100` |
| Include Sample Code | :ballot_box_with_check: |
| Direct Commit | :ballot_box_with_check: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/fc7e3131-8ac3-4054-a131-c4e8da023fec) |
|-|

When the **Create a new app** workflow is done, navigate to Code and modify the name of the object in the **app2/HelloWorld.al** file to **CustomerListExt2**. This will kick off another CI/CD workflow.

> \[!NOTE\]
> You might wonder why the **Create a new app** workflow with direct commit didn't kick off a new CI/CD build. This is due to a GitHub security feature that one workflow cannot by default kick off another workflow. Checking the **Use GhTokenWorkflow for PR/Commit** checkbox will allow GitHub to run CI/CD from the workflow.

When the CI/CD workflow is complete, download and inspect the artifacts generated

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/54d8ea19-d17e-4538-917f-661a921d474b) |
|-|

**App2** still has version **1.0** in **app.json**, hence the **1.0.6.0** version number.

If we want to increment the version number of the project and all apps, you can run the **Increment Version Number** workflow and specify the following values

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name patterns | `*` |
| Updated Version Number | `+0.1` |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/dbba8aa8-6a8b-446d-8bac-42b07dc79c36) |
|-|

> \[!NOTE\]
> Specifying **+0.1** will add 1 to the minor version of all apps and to the repo version number, specifying **+1.0** will add 1 to the major version and if you specify **2.0** (without the +), it will set major.minor to 2.0 no matter what value was earlier set, but... you cannot set a version number, which is lower than was already set.

Wait for the workflow to complete, select **Pull requests** and select the **Increment Version Number by 0.1** Pull request and inspect what the workflow is trying to change for you.

At this time, we will **NOT** merge the Pull request as changing version numbers like this is typically done during a release.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/70f761c0-4ae6-42de-84ba-fe67d4a98264) |
|-|

Select **Conversation**, click **Close pull request** and **delete the branch**.

It is possible to modify the behavior of versioning (not alter it totally) by adding a setting called **versioningStrategy** in your repository settings file. More about that later.

Release? Let's try to release the project and create a release branch...

______________________________________________________________________

[Index](Index.md)  [next](Releasing.md)
