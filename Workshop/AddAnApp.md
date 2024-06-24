# Add An App

There are several ways you can add an app to your repository:

- You can use the **Create a new app** workflow in AL-Go for GitHub to create a new app and start coding.
- You can use the **Add existing app or test app** workflow to upload an .app file (or multiple) and have AL-Go for GitHub extract the source.
- You can **upload the source files** directly into GitHub
- You can **clone** the repository and add your source files from **VS Code** (possibly using the AL:Go in VS Code)

All in all - it is just a matter of adding the source files of your app to the repository.

In this workshop, we will use the **Create a new app** workflow.

In your repository, click **Actions**. Locate the **Show more workflows...** and click that to reveal the hidden workflows. Select the **Create a new app** workflow and click **Run workflow**.
Enter the following values in the form:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `.` |
| Name | `app1` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `55000..55100` |
| Include Sample Code | :ballot_box_with_check: |
| Direct Commit | :black_square_button: |
| Use GhTokenWorkflow | :black_square_button: |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b556ae00-469c-4156-9b1b-925ee4632e4d) |
|-|

Wait a few minutes until the workflow completes and click **Pull requests** to see that there is a Pull request open for review.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/295d2d32-1101-4471-af30-9192e63c1a3d) |
|-|

Open the **Pull request** and click **Files changed** to see what the Pull request will add to your repository.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/79081ae2-2d98-41e0-9abd-25e5da4cfec8) |
|-|

> \[!NOTE\]
> The changes made by the workflow includes adding the new app path to the `al.code-workspace`, and adding an app folder with **app.json**, **HelloWorld.al** (sample code) and **.vscode/launch.json**.
> The **Create a new app** workflow doesn't do anything else than just adding these changes, no magic behind the scenes.

> \[!NOTE\]
> If you have renamed the `al.code-workspace` file to `<anothername>.code-workspace` to be able to better distinguish the workspaces, it will still be updated.

Select **Conversation** and merge the pull request by clicking **Merge the pull request**, **Confirm merge** and then delete the temporary branch created for the pull request, by clicking **Delete branch**. Select **Actions** and see that a merge commit workflow was kicked off:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/80b1c400-7ce2-4511-a9e2-febb7da9f171) |
|-|

When the merge commit is **done**, click the workflow line and **scroll down** to see the artifacts created by this build:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ba90341f-75f5-47f3-be7f-b00e49e4ba19) |
|-|

> \[!NOTE\]
> My artifacts are created with version **1.0.4.0** - that might not be the same in your repository.

Let's talk about versioning and naming...

______________________________________________________________________

[Index](Index.md)  [next](Versioning.md)
