# #2 Add a test app to an existing project
*Prerequisites: A completed [scenario 1](GetStarted.md)*

1. On **github.com**, open **Actions** on your solution, select **Create a new test app** and then choose **Run workflow**. Enter values for **name**, **publisher**, and **ID range** and choose **Run workflow**
![Run Workflow](https://github.com/microsoft/AL-Go/assets/10775043/96485817-a631-4626-92b4-89e6432f5622)
1. When the workflow is done, navigate to **Pull Requests**, **inspect the PR** and **Merge the pull request**
![Pull Request](https://github.com/microsoft/AL-Go/assets/10775043/9fef16a8-ed34-43ee-8678-5ea7d3f1d221)
1. Under **Actions**, you will see that a Merge pull request CI workflow has been kicked off
![Workflows](https://github.com/microsoft/AL-Go/assets/10775043/033ca252-ca26-457e-81a5-6f9edbda7a96)
1. If you wait for the workflow to complete, you will see that it fails.
![Fail](https://github.com/microsoft/AL-Go/assets/10775043/d009f93b-0346-4273-b180-34ecf83ab76f)
1. Inspecting the build, you can see the details of the error.
![Test failure](https://github.com/microsoft/AL-Go/assets/10775043/9120bf17-c3d4-414e-ae39-c876653b5567)
1. To fix this, open VS Code, pull changes from the server using the sync button, open the **HelloWorld.Test.al** file and fix the test message.
![Bug fix](https://github.com/microsoft/AL-Go/assets/10775043/49d0f417-b9b3-4a30-8a48-e296cfe03b70)
1. Stage, Commit, and Push the change. On github.com, under **Actions** you will see that your check-in caused another CI workflow to be kicked off.
![CI Workflow](https://github.com/microsoft/AL-Go/assets/10775043/c7527963-d728-413b-82bc-c9185674026f)
1. This time it should be passing and if you investigate the CI/CD workflow, you will see that the deploy step has been skipped as no environment existed.
![Success](https://github.com/microsoft/AL-Go/assets/10775043/4977dd06-36f3-45e1-a91b-991047f1604c)

---
[back](../README.md)
