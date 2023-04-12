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

| ![image](https://user-images.githubusercontent.com/10775043/231437591-4f73e366-ab40-4310-8074-ff432f5ce499.png) |
|-|

Wait a few minutes until the workflow completes and click **Pull requests** to see that there is a Pull request open for review.

| ![image](https://user-images.githubusercontent.com/10775043/231438634-dcd2d7c4-8db3-4d50-8396-fd7f0b9e74b3.png) |
|-|

Open the **Pull request** and click **Files changed** to see what the Pull request will add to your repository.

| ![image](https://user-images.githubusercontent.com/10775043/231438970-afe8087a-6305-463a-97fe-4b6f47eca839.png) |
|-|

The changes made by the workflow includes adding the new app path to the **al.code-workspace**, and adding an app folder with **app.json**, **HelloWorld.al** (sample code) and **.vscode/launch.json**.
The **Create a new app** workflow doesn't do anything else than just adding these changes, no magic behind the scenes.

Select **Conversation** and merge the pull request by clicking **Merge the pull request** and remove the temporary branch created for the pull request, by clicking **Delete branch**.

| ![image](https://user-images.githubusercontent.com/10775043/231440700-1416519c-742c-4fb9-a094-5ec253e242c5.png) |
|-|

Select **Actions** and see that a merge commit workflow was kicked off:

| ![image](https://user-images.githubusercontent.com/10775043/231440982-ccaa8437-6b1f-4f77-a3a5-df9ca382dc49.png) |
|-|

When the merge commit is **done**, click the workflow and **scroll down** to see the artifacts created by this build:

| ![image](https://user-images.githubusercontent.com/10775043/231449015-9ce85efd-dde1-442b-97da-748b1db33ddb.png) |
|-|

Note that my artifacts are created with version **1.0.2.1** - that might not be the same in your repository.

---
[Index](Index.md)&nbsp;&nbsp;[next](Versioning.md)
