# #16 Add a performance test app to an existing project
*Prerequisites: A completed [scenario 1](GetStarted.md)*

1. On **github.com**, open **Actions** on your solution, select **Create a new performance test app** and then choose **Run workflow**. Enter values for **name**, **publisher**, and **ID range** and choose **Run workflow**
![Run Workflow](https://github.com/microsoft/AL-Go/assets/10775043/40f9bda7-578b-4844-9c2b-f59200d04584)
1. When the workflow is done, navigate to **Pull Requests**, **inspect the PR** and **Merge the pull request**
![Pull Request](https://github.com/microsoft/AL-Go/assets/10775043/e97ef897-93f4-4c9f-9ce2-e747d7021003)
1. Under **Actions**, you will see that a Merge pull request **CI workflow** has been kicked off
![Workflows](https://github.com/microsoft/AL-Go/assets/10775043/90ee2dee-4e2a-4d16-80bc-63d3ce1f53b5)
1. If you wait for the workflow to complete, you will see that it completes and one of the build artifacts are the **BCPT Test Results**
![Fail](https://github.com/microsoft/AL-Go/assets/10775043/ad154e32-34d4-49f1-a8de-e74ed5a79217)
1. Opening the **BCPT Test Results** and inspecting the results looks like this
![Test failure](https://github.com/microsoft/AL-Go/assets/10775043/0869601d-55e6-4e1d-9d1e-fb1a2c0c6b05)
1. Currently there isn't a visual viewer of these results. The goal is to have a PowerBI dashboard, which can gather BCPT test results from multiple builds and compare.

---
[back](../README.md)
