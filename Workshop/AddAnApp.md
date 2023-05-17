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
| Include Sample Code | `Y` |
| Direct COMMIT | `N` |

| ![image](https://user-images.githubusercontent.com/10775043/231540732-4a1ef920-abe2-4611-a2b0-9ac9a8310e3b.png) |
|-|

Wait a few minutes until the workflow completes and click **Pull requests** to see that there is a Pull request open for review.

| ![image](https://user-images.githubusercontent.com/10775043/231541168-7f38a62a-84a3-4d31-9e44-4836f51ec9c0.png) |
|-|

Open the **Pull request** and click **Files changed** to see what the Pull request will add to your repository.

| ![image](https://user-images.githubusercontent.com/10775043/231541315-9c738120-3b16-4746-b066-1e22345fb1a8.png) |
|-|

The changes made by the workflow includes adding the new app path to the **al.code-workspace**, and adding an app folder with **app.json**, **HelloWorld.al** (sample code) and **.vscode/launch.json**.
The **Create a new app** workflow doesn't do anything else than just adding these changes, no magic behind the scenes.

Select **Conversation** and merge the pull request by clicking **Merge the pull request**, **Confirm merge** and then delete the temporary branch created for the pull request, by clicking **Delete branch**. Select **Actions** and see that a merge commit workflow was kicked off:

| ![image](https://user-images.githubusercontent.com/10775043/231541665-e9a29056-e681-42fc-b272-ff0fd0ce3d94.png) |
|-|

When the merge commit is **done**, click the workflow line and **scroll down** to see the artifacts created by this build:

| ![image](https://user-images.githubusercontent.com/10775043/231544822-71bf956d-a050-4d18-b429-69fdb08083f9.png) |
|-|

Note that my artifacts are created with version **1.0.2.0** - that might not be the same in your repository.

Let's talk about versioning and naming...

---
[Index](Index.md)&nbsp;&nbsp;[next](Versioning.md)
