# Create a release of your application

*Prerequisites: A completed [scenario 3](RegisterSandboxEnvironment.md)*

1. On github.com, open **Actions** in your project and select **Create Release**. Choose **Run workflow**. Enter `v1.0` as **name** and `1.0.0` as **tag** of the release, type `+0.1` in new version number and then choose **Run workflow**.

   ![Create Release](https://github.com/user-attachments/assets/748537f5-781f-4e96-bb8f-79b7294dbca5)

1. When the **create release** workflow completes, choose the **Code** section to see the releases.

   ![Releases](https://github.com/user-attachments/assets/71de15de-1d29-49cf-a593-85b0c5041f4c)

1. Choose the release (v1.0) and you will see the release. The release notes are pulled from all changes checked in since the last release. The auto-generated release note also contains a list of the new contributers and a link to the full changelog. Choose the **Edit** button (the pencil) to modify the release notes. At the bottom, you can see the artifacts published, both the apps and the source code. A tag is created in the repository for the release number to always keep this.

   ![Release](https://github.com/user-attachments/assets/ad9088c7-dfad-4a5e-9a20-c168b1311eee)

1. Under **Pull requests** you should also see the pull request created for the updated version number.

   ![Increment version number](https://github.com/user-attachments/assets/77a0c94d-d365-4d5d-ac4e-57d3841e8f25)

> [!NOTE]
> In AL-Go for GitHub every release should be followed by an update to the version number in order to be able to create hotfixes for the release and not clash with version numbers in the main branch.

5. Inspecting the pull request reveals that it just changes the minor version number in the main branch. Under the conversation tab, merge the pull request and delete the branch.

   ![Inspect PR](https://github.com/user-attachments/assets/f7855aaa-3233-4028-91ed-ffba9de797ae)

1. Under **Actions** you should now see that a new CI/CD workdlow have been started.

   ![New CI/CD](https://github.com/user-attachments/assets/442930f6-508d-4e0f-8130-2ccc39099fef)

1. After the CI/CD workflow finishes, you can inspect the workflow output to see that the latest release was used as a baseline for the upgrade tests in the pipeline. You will also see that the new build, just created was deployed to the QA environment automatically.

   ![Success](https://github.com/user-attachments/assets/639851f5-fab2-4cc9-a43c-e4cdea974536)

______________________________________________________________________

[back](../README.md)
