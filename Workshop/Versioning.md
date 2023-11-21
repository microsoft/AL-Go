# Versioning
Understanding how AL-Go for GitHub is doing **versioning** and **naming** is important for your day to day use of AL-Go for GitHub.

As we saw earlier, the **artifacts** from the first successful build in my repository was called version **repo1-main-Apps-1.0.2.0**.
Downloading the artifact and unpacking reveals the app inside. The app inside is using the same naming strategy as VS Code: `<publisher>_<name>_<version>`

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a74da044-e6c4-4d96-8f75-6fbfa1bddaa2) |
|-|

Here, the app has the same version number as the artifact, but is it always like that?

As you know, the build number consists of 4 tuples: **major.minor.build.revision**.
- The version number of the build artifact is 100% controlled by AL-Go for GitHub. The **major.minor** are taken from a setting called **RepoVersion** (default is 1.0) and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The version number of the app (inside the build artifact) is controlled by **app.json** and **AL-Go for GitHub**. The **major.minor** part is taken from **app.json** and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The **build** tuple is (by default) the GITHUB_RUN_NUMBER, which is a unique number for each time the CI/CD workflow is run, starting with 1.
- The **revision** typle is (by default) the GITHUB_RUN_ATTEMPT, which is the number of attempts, starting with 0. In my example above, I did re-run the CI/CD workflow once to end up with .1.

In order to better understand this, select **Code** and navigate to the **app.json** file under the **app1** folder. Edit the file and change the version number to **1.2.5.6**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5c758cf1-6f52-4814-81ad-0c506e63324c) |
|-|

**Commit** the changes directly, select **Actions** and wait for the build to complete.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/912a32fa-6ca8-4ef0-8e38-cfded6eee44d) |
|-|

Select the **Update app.json** workflow, **scroll down** to the artifacts and **download** the new apps artifact.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e1df08a6-5516-4923-abe9-fee93f315ff0) |
|-|

Now the project (in this case the repository), which really is a collection of apps, is still version **1.0** (RepoVersion never changed - is still 1.0 = default) and **app1** is **1.2** (major and minor from app.json). Build is **3** (3rd build) and revision is still **0**.

Scroll back up, locate the **Re-run all jobs** button and click it. Wait for the **2nd attempt** to complete and inspect the artifact for the re-run.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4e4df417-e257-4a61-bc07-666f98413be1) |
|-|

Now revision became **1** as we had another attempt at building the app.

Next, let's create another app, by running the **Create a new app** workflow again in the same repo. **app2** with ID range **56000..56100** and enter **Y** in **Direct COMMIT**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/06d4a03c-f025-44d6-a317-b2a0a79f7e8e) |
|-|

When the **Create a new app** workflow is done, navigate to Code and modify the name of the object in the **HelloWorld.al** file to **CustomerListExt2**. This will kick off another CI/CD workflow. When the workflow is complete, download and inspect the artifacts generated

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d654b75c-2e63-4bd3-a39a-dce6bf835c30) |
|-|

**App2** still has version **1.0** in **app.json**, hence the **1.0.4.0** version number.

If we want to increment the version number of the project and all apps, you can run the **Increment Version Number** workflow, and keep the **N** in **Direct COMMIT**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d9da5fcc-3e57-42b1-92b4-23d17ccfbbf9) |
|-|

Specifying **+0.1** will add 1 to the minor version of all apps and to the repo version number. Wait for the workflow to complete, select **Pull requests** and select the **Increment Version Number by 0.1** Pull request and inspect what the workflow is trying to change for you. At this time, we will **NOT** merge the Pull request as changing version numbers like this is typically done during a release.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1b16ac1f-1717-4ea7-9bd0-b98e5df8bfe2) |
|-|

Select **Conversation**, click **Close pull request** and **delete the branch**.

It is possible to modify the behavior of versioning (not alter it totally) by adding a setting called **versioningStrategy** in your repository settings file. More about that later.

Release? Let's try to release the project and create a release branch...

---
[Index](Index.md)&nbsp;&nbsp;[next](Releasing.md)
