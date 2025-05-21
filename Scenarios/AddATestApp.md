# Add a test app to an existing project

*Prerequisites: A completed ["Create a new per-tenant extension (like AL Go) and start developing in VS Code"](GetStarted.md) scenario*

1. On **github.com**, open **Actions** on your solution, locate and select **Create a new test app** and then choose **Run workflow**. Enter values for **name**, **publisher**, and **ID range** and choose **Run workflow**

   ![Create a new test app](https://github.com/user-attachments/assets/9173c04f-1ad1-424c-8078-5ee4dda9c48a)

1. If you receive an error, stating that GitHub actions are **not allowed to create Pull Requests**, the reason for this is that your organizational settings doesn't allow the workflow to create pull requests, you can **click the link** and proceed to **create the pull request manually**:

   ![iPull request not allowed](https://github.com/user-attachments/assets/84b7f632-3895-4c52-975c-9c150e6ed997)

1. If you got this error, you can change that behavior under **Organization** -> **Settings** -> **Actions** -> **General** -> **Workflow permissions** -> Check **Allow GitHub Actions to create and approve pull requests**.

   ![iAllow GitHub Actions to create and approve pull requests](https://github.com/user-attachments/assets/93454d6c-2b6a-4180-837c-a500be11f37c)

1. When the workflow is done, navigate to **Pull Requests**, **inspect the PR**, **Merge the pull request** and **Confirm the merge**

   ![Merge pull request](https://github.com/user-attachments/assets/5f268ba9-dbf5-4df6-89c7-d8cce568b25a)

1. Under **Actions**, you will see that a Merge pull request CI workflow has been kicked off

   ![Merge pull request runningimage](https://github.com/user-attachments/assets/72282e67-89bd-4e8c-b46d-25a1aa5b4e35)

1. If you wait for the workflow to complete, you will see that it fails.

   ![Fail](https://github.com/user-attachments/assets/9e8b56c9-aae9-40aa-8904-d29101d21f1c)

1. Inspecting the build, you can see the details of the error.

   ![Test failure](https://github.com/user-attachments/assets/23e5299d-12e3-46bb-a2a4-890877f5a9de)

1. To fix this, open VS Code, pull changes from the server using the sync button, open the **HelloWorld.Test.al** file and fix the test message.

   ![Bug fix](https://github.com/user-attachments/assets/cc488145-45a6-458c-8c45-3d60f8a2b5c3)

1. Stage, Commit, and Push the change. On github.com, under **Actions** you will see that your check-in caused another CI workflow to be kicked off.

   ![CI workflow](https://github.com/user-attachments/assets/8550df71-9777-45d0-89df-113c99a1ed57)

1. This time it should be passing and if you investigate the CI/CD workflow, you will see that the deploy step has been skipped as no environment existed.

   ![Success](https://github.com/user-attachments/assets/47a6f189-5322-4539-bc92-d4fcf24cbdcf)

______________________________________________________________________

[back](../README.md)
