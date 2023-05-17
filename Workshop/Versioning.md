# Versioning
Understanding how AL-Go for GitHub is doing **versioning** and **naming** is important for your day to day use of AL-Go for GitHub.

As we saw earlier, the **artifacts** from the first successful build in my repository was called version **repo1-main-Apps-1.0.2.0**.
Downloading the artifact and unpacking reveals the app inside. The app inside is using the same naming strategy as VS Code: `<publisher>_<name>_<version>`

| ![image](https://user-images.githubusercontent.com/10775043/231545533-be33a8f6-88ea-4b05-b343-d71aaf9ee5d4.png) |
|-|

Here, the app has the same version number as the artifact, but is it always like that?

As you know, the build number consists of 4 tuples: **major.minor.build.revision**.
- The version number of the build artifact is 100% controlled by AL-Go for GitHub. The **major.minor** are taken from a setting called **RepoVersion** (default is 1.0) and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The version number of the app (inside the build artifact) is controlled by **app.json** and **AL-Go for GitHub**. The **major.minor** part is taken from **app.json** and the **build.revision** part is auto-calculated by AL-Go for GitHub.
- The **build** tuple is (by default) the GITHUB_RUN_NUMBER, which is a unique number for each time the CI/CD workflow is run, starting with 1.
- The **revision** typle is (by default) the GITHUB_RUN_ATTEMPT, which is the number of attempts, starting with 0. In my example above, I did re-run the CI/CD workflow once to end up with .1.

In order to better understand this, select **Code** and navigate to the **app.json** file under the **app1** folder. Edit the file and change the version number to **1.2.5.6**.

| ![image](https://user-images.githubusercontent.com/10775043/231559564-43683818-c540-4ba3-86b4-832c67545ae4.png) |
|-|

**Commit** the changes, select **Actions** and wait for the build to complete.

| ![image](https://user-images.githubusercontent.com/10775043/231547295-accc7f9d-7c19-472f-80df-71d1897d91a5.png) |
|-|

Select the **Update app.json** workflow, **scroll down** to the artifacts and **download** the new apps artifact.

| ![image](https://user-images.githubusercontent.com/10775043/231559045-1e071522-80c3-456c-9379-9b51a550f60a.png) |
|-|

Now the project (in this case the repository), which really is a collection of apps, is still version **1.0** (RepoVersion never changed - is still 1.0 = default) and **app1** is **1.2** (major and minor from app.json). Build is **3** (3rd build) and revision is still **0**.

Scroll back up, locate the **Re-run all jobs** button and click it. Wait for the **2nd attempt** to complete and inspect the artifact for the re-run.

| ![image](https://user-images.githubusercontent.com/10775043/231560877-bc9354ff-40e9-4705-91d4-6217133a1e73.png) |
|-|

Now revision became **1** as we had another attempt at building the app.

Next, let's create another app in the same repo. **app2** with ID range **56000..56100** and enter **Y** in **Direct COMMIT**.

| ![image](https://user-images.githubusercontent.com/10775043/231561391-7350981e-e20d-49a1-9479-4271a7e6ddd8.png) |
|-|

When the **Create a new app workflow** is done, select the **CI/CD** workflow and click **Run workflow** to run the workflow manually. When the workflow is complete, download and inspect the artifacts generated

| ![image](https://user-images.githubusercontent.com/10775043/231564490-b8c414a8-cf6b-4660-bd81-4c98571812a6.png) |
|-|

**App2** still has version **1.0** in **app.json**, hence the **1.0.4.0** version number.

If we want to increment the version number of the project and all apps, you can run the **Increment Version Number** workflow.

| ![image](https://user-images.githubusercontent.com/10775043/231565483-5f92751e-ed59-40c9-ba80-c90effc9a4e3.png) |
|-|

Specifying **+0.1** will add 1 to the minor version of all apps and to the repo version number. Wait for the workflow to complete, select **Pull requests** and select the **Increment Version Number by 0.1** Pull request and inspect what the workflow is trying to change for you. At this time, we will **NOT** merge the Pull request as changing version numbers like this is typically done during a release.

| ![image](https://user-images.githubusercontent.com/10775043/231566085-3fd6ae4a-e88e-4dfd-be60-3ac95767d14a.png) |
|-|

Select **Conversation**, click **Close pull request** and **delete the branch**.

It is possible to modify the behavior of versioning (not alter it totally) by adding a setting called **versioningStrategy** in your repository settings file. More about that later.

Release? Let's try to release the project and create a release branch...

---
[Index](Index.md)&nbsp;&nbsp;[next](Releasing.md)
