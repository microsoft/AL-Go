# Add An App
There are several ways you can add an app to your repository:
- You can use the **Create a new app** workflow in AL-Go for GitHub to create a new app and start coding.
- You can use the **Add existing app or test app** workflow to upload an .app file (or multiple) and have AL-Go for GitHub extract the source.
- You can **upload the source files** directly into GitHub
- You can **clone** the repository and add your source files from **VS Code** (possibly using the AL:Go)

All in all - it is just a matter of adding the source files of your app to the repository.

In this workshop, we will use the **Create a new app** workflow.

In your repository, click **Actions**. Locate the **Show more workflows...** and click that to reveal the hidden workflows. Select the **Create a new app** workflow and click **Run workflow**.
Enter the following values in the form:

| Name | Value |
| :-- | :-- |
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

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b1dd7d78-d8e0-4d19-99bf-8a555a076071) |
|-|

Open the **Pull request** and click **Files changed** to see what the Pull request will add to your repository.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/af9ffee2-ebae-46b0-ae81-6bffb51ddd08) |
|-|

The changes made by the workflow includes adding the new app path to the **al.code-workspace**, and adding an app folder with **app.json**, **HelloWorld.al** (sample code) and **.vscode/launch.json**.
The **Create a new app** workflow doesn't do anything else than just adding these changes, no magic behind the scenes.

Select **Conversation** and merge the pull request by clicking **Merge the pull request**, **Confirm merge** and then delete the temporary branch created for the pull request, by clicking **Delete branch**. Select **Actions** and see that a merge commit workflow was kicked off:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b4cc814a-6ed4-4730-ab53-81a88a4b54b3) |
|-|

When the merge commit is **done**, click the workflow line and **scroll down** to see the artifacts created by this build:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/09b8013e-0cd7-46f7-b45c-a4dcaccfb788) |
|-|

Note that my artifacts are created with version **1.0.2.0** - that might not be the same in your repository.

Let's talk about versioning and naming...

---
[Index](Index.md)&nbsp;&nbsp;[next](Versioning.md)
