# Single-project vs. Multi-project
In AL-Go for GitHub, a project is defined as a collection of apps, who are build, tested, shipped and installed together.

Every repository can have any number of projects, which each can have any number of apps.

Up until now we have worked with a repository which contained 2 apps. This is called a single-project repository.

Things that are determined at the app level:
- Version of the app
- Dependencies to other apps
- Functionality of the app (obviously)

Things that are determined at the project level:
- Version and localization of Business Central to use during build
- Dependencies to other projects
- Deployments are done on the project level - you cannot deploy a single app to a customer

Things that are determined at the repository level:
- Which version of AL-Go for GitHub to use
- Schedule for various workflows (Test Next Major, Next Minor etc.)
- Project settings can also be overridden at the repository level and thus work for all projects in the repository
- Releases are created on the repository level - you cannot release a single project in a multi-project repository

A multi-project repository could look like this:

![image](https://user-images.githubusercontent.com/10775043/231688802-4d08e4f2-6bbc-4677-902b-0bef9ed068d8.png)

So, let's setup a multi-project repository like this. Navigate to **https://aka.ms/algopte** to create a new repository. Click **Use this template** and select **Create a new repository**. Select your **organization** as owner, specify a **name** and select **Public**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7e66ca01-0850-4031-8b80-616ee819ebde) |
|-|

You can locate the **Create a new app** workflow in the list of workflows and run it with the following parameters:

| Name | Value |
| :-- | :-- |
| Project name | `US` |
| Name | `mysolution.us` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `50000..50100` |
| Include Sample Code | `Y` |
| Direct COMMIT | `N` |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/04f69e2c-de5f-45ae-89fc-48c543d14c60) |
|-|

When the **Create a new app in [main]** workflow has completed, select **Pull requests**, click the **New PTE** pull request and select **Files changed** to inspect what changes was done to the repo:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/8db3c739-674f-4172-9c92-52c6a0edadb3) |
|-|

Notice that:
1. The .AL-Go folder was moved from the root of the repo and into the US folder.
2. A new US.code-workspace was created as a workspace for this project
3. An app was added under the US folder called mysolution.us

Go ahead click **Conversation**, **merge the pull request** and **delete** the temporary branch.

You don't have to wait for the **CI/CD workflow** to complete, just go ahead and run the **Create a new app** again. This time with the following parameters:

| Name | Value |
| :-- | :-- |
| Project name | `DK` |
| Name | `mysolution.dk` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `51000..51100` |
| Include Sample Code | `Y` |
| Direct COMMIT | `N` |

and run the same workflow again with these parameters:

| Name | Value |
| :-- | :-- |
| Project name | `W1` |
| Name | `mysolution.w1` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `52000..52100` |
| Include Sample Code | `Y` |
| Direct COMMIT | `N` |

When the **New PTE (mysolution.dk)** and **New PTE (mysolution.w1)** pull requests are created, merge both pull request and delete the temporary branches.

Now select Actions and see that a number of workflows have been kicked off. Some are completed, some might still be running.

Click the latest CI/CD commit workflow and notice the 3 jobs (you can expand the jobs by clicking show all jobs):

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/19707351-d77c-4a46-8082-c0fcf6f7fc3a) |
|-|

At this time, all apps will be using US as localization and use the same Business Central version as we entered when setting up prerequisites.

After the build completes, you can inspect the artifacts created from this multi-project repository, by clicking Summary and scrolling down:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/aad8cbed-26ba-4155-8d3f-55aa14655a7c) |
|-|

DK, US and W1 all have an artifact of the type **Apps** generated, but they are wrong, since they are all build using the US localization. We need **DK** to be build using the danish localization and **W1** using W1.

Note also the CheckForUpdates annotation. AL-Go says that there are system files updates. This is because when creating a new project, AL-Go will (at the next system file update) place scripts in the .AL-Go folder for creating local and cloud development environments.

Before running **Update AL-Go System Files** however, let's make some changes to the repository and we will do this from VS Code. Select **Code** and click the **Code** dropdown to copy the GIT URL for the repo:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d169c50a-ccc6-4236-8816-bde96036beae) |
|-|

 Open **VS Code** and run **Git Clone** to clone your repository to your local machine:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ce2c8991-a371-4fd8-9c0e-05854f885cbc) |
|-|

Open the repository (do not open the workspace) and perform the following changes:
- in **DK/.AL-Go/settings.json**, add **"artifact": "https://bcartifacts.azureedge.net/sandbox/23.0.12034.13450/dk"**
- in **DK/.AL-Go/settings.json**, change **country** to **"dk"**
- in **DK/mysolution.dk/HelloWorld.al**, add DK to the pageextension name (i.e. CustomerListExt to **CustomerListExtDK**)
- in **US/.AL-Go/settings.json**, add **"artifact": "https://bcartifacts.azureedge.net/sandbox/22.0.54157.55210/us"**
- in **US/mysolution.ud/HelloWorld.al**, add US to the pageextension name (i.e. CustomerListExt to **CustomerListExtUS**)
- in **W1/.AL-Go/settings.json**, add **"artifact": "https://bcartifacts.azureedge.net/sandbox/22.0.54157.55210/w1"**
- in **W1/.AL-Go/settings.json**, change **country** to **"w1"**
- in **W1/mysolution.w1/HelloWorld.al**, add W1 to the pageextension name (i.e. CustomerListExt to **CustomerListExtW1**)

**Stage the changes** in **VS Code**, **Commit** the changes and **Sync**. Wait for the **CI/CD** workflow to complete:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/99eb407c-497b-428a-a376-6e5cdb6f3db6) |
|-|

Now, we can create a release and inspect that. Run the **Create release** workflow and release v1.0 like this:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/541bd90c-b60b-485f-9c10-c7947cfaaade) |
|-|

After this is done, select **Code** and click the newly created release to see the artifacts. In the auto generated release notes, you will see all merged Pull Requests under **What's Changed** and by clicking the **Full Changelog** link you will find all commits.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/446616b6-a464-4721-bd58-08270a18e3f8) |
|-|

OK - so that's fine, but normally in a solution like this, DK and US have a dependency on W1 or a common app - you don't have all code duplicated 3 times - how does AL-Go handle dependencies?

---
[Index](Index.md)&nbsp;&nbsp;[next](Dependencies1.md)
