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

So, let's setup a multi-project repository like this. Navigate to **https://aka.ms/algopte** to create a new repository. Click **Use this template** and select **Create a new repository**. Select your **organization** as owner, specify a **name**,select **Public** and click **Create repository**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ecbdaa03-1cd2-4043-8ec0-a7f4d87bb819) |
|-|

Locate the **Create a new app** workflow in the list of workflows and run it with the following parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `US` |
| Name | `mysolution.us` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `50000..50100` |
| Include Sample Code | :ballot_box_with_check: |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/683a4ebd-364a-4373-81f9-512faa195391) |
|-|

When the **Create a new app in [main]** workflow has completed, select **Pull requests**, click the **New PTE** pull request and select **Files changed** to inspect what changes was done to the repo:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/557661dd-587f-43cc-8ff8-d71a38a55638) |
|-|

> [!NOTE]
>
> 1. The .AL-Go folder was moved from the root of the repo and into the US folder.
> 1. A new US.code-workspace was created as a workspace for this project
> 1. An app was added under the US folder called mysolution.us

> [!NOTE]
> You can rename the `US.code-workspace` file to `<anothername>.code-workspace` to be able to better distinguish the workspaces.

Go ahead click **Conversation**, **merge the pull request** and **delete** the temporary branch.

You don't have to wait for the **CI/CD workflow** to complete, just go ahead and run the **Create a new app** again. This time with the following parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `DK` |
| Name | `mysolution.dk` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `51000..51100` |
| Include Sample Code | :ballot_box_with_check: |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

and run the same workflow again with these parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `W1` |
| Name | `mysolution.w1` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `52000..52100` |
| Include Sample Code | :ballot_box_with_check: |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

When the **New PTE (mysolution.dk)** and **New PTE (mysolution.w1)** pull requests are created, merge both pull request and delete the temporary branches.

Now select Actions and see that a number of workflows have been kicked off. Some are completed, some might still be running.

Click the latest CI/CD commit workflow and notice the 3 jobs (you can expand the jobs by clicking show all jobs):

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/bae168e5-bc9e-4f32-9ac8-05a4b94a4a41) |
|-|

> [!NOTE]
> At this time, all apps will be using US as localization and use the same Business Central version as we entered when setting up prerequisites, but you can change this in the settings file for each individual project.

After the build completes, you can inspect the artifacts created from this multi-project repository, by clicking Summary and scrolling down:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/60973d66-bf60-4b38-9776-fa720fbd3e52) |
|-|

DK, US and W1 all have an artifact of the type **Apps** generated, but as already stated, they are all build using the US localization. We need **DK** to be build using the Danish localization and **W1** using W1.

> [!NOTE]
> AL-Go states that there are system files updates (the CheckForUpdates annotation). This is because when creating a new project, AL-Go will (at the next system file update) place scripts in the .AL-Go folder for creating local and cloud development environments.

Before running **Update AL-Go System Files** however, let's make some changes to the repository and we will do this from VS Code. Select **Code** and click the **Copy** button to copy the GIT URL for the repo:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b5d0ce1b-084b-44b6-bccc-a486f7a72ecc) |
|-|

Open **VS Code** and run **Git Clone** to clone your repository to your local machine:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a911144c-fad7-4c18-bdad-2332aa74df5f) |
|-|

Open the repository (do not open the workspace) and perform the following changes:

- in **DK/.AL-Go/settings.json**, add **"artifact": "bcartifacts/sandbox/23.0.12034.13450/dk/closest"**
- in **DK/.AL-Go/settings.json**, change **country** to **"dk"**
- in **DK/mysolution.dk/HelloWorld.al**, add DK to the pageextension name (i.e. CustomerListExt to **CustomerListExtDK**)
- in **US/.AL-Go/settings.json**, add **"artifact": "bcartifacts/sandbox/22.0.54157.55210/us/closest"**
- in **US/mysolution.ud/HelloWorld.al**, add US to the pageextension name (i.e. CustomerListExt to **CustomerListExtUS**)
- in **W1/.AL-Go/settings.json**, add **"artifact": "bcartifacts/sandbox/22.0.54157.55210/w1/closest"**
- in **W1/.AL-Go/settings.json**, change **country** to **"w1"**
- in **W1/mysolution.w1/HelloWorld.al**, add W1 to the pageextension name (i.e. CustomerListExt to **CustomerListExtW1**)

**Stage the changes** in **VS Code**, **Commit** the changes and **Sync**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5ae5b03a-bc15-45b2-89d9-d96468755879) |
|-|

In GitHub, wait for the **CI/CD** workflow to complete:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/87d64b0e-a930-4cfc-80d7-e3e8769a50d4) |
|-|

Now, we can create a release and inspect that. Run the **Create release** workflow and release v1.0 with these parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| App version | `latest` |
| Name of this release | `v1.0` |
| Tag of this release | `1.0.0` |
| Prerelease | :black_square_button: |
| Draft | :black_square_button: |
| Create Release Branch | :black_square_button: |
| New Version Number | `+0.1` |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/9b69803c-8133-47ef-a9a8-f1681a988907) |
|-|

After this is done, select **Code** and click the newly created release to see the artifacts.

> [!NOTE]
> In the auto generated release notes, you will see all merged Pull Requests under **What's Changed** and by clicking the **Full Changelog** link you will find all commits.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/15c67508-33c1-4592-a227-05262651dcd6) |
|-|

You will see that every project has it's own release artifact.

OK - so that's fine, but normally in a solution like this, DK and US have a dependency on W1 or a common app - you don't have all code duplicated 3 times - how does AL-Go handle dependencies?

______________________________________________________________________

[Index](Index.md)  [next](Dependencies1.md)
