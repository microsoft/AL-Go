# #16 Add a performance test app to an existing project

*Prerequisites: A completed [scenario 1](GetStarted.md)*

1. On **github.com**, open **Actions** on your solution, select **Create a new performance test app** and then choose **Run workflow**. Enter values for **name**, **publisher**, and **ID range** and choose **Run workflow**

   ![Run workflow](https://github.com/microsoft/AL-Go/assets/10775043/d499294e-8c88-4f2d-9bb4-b34bad276a6b)

   Note that if workflows are not allowed to create pull requests due to GitHub Settings, you can create the PR manually by following the link in the annotation

   ![Annotation](https://github.com/microsoft/AL-Go/assets/10775043/d346f0fc-5db4-4ff1-9c76-e93cb03ae504)

1. When the workflow is done, navigate to **Pull Requests**, **inspect the PR** and **Merge the pull request**

   ![Pull Request](https://github.com/microsoft/AL-Go/assets/10775043/d2831620-3bc9-4808-aa7a-997944aaaa33)

1. Under **Actions**, you will see that a Merge pull request **CI/CD workflow** has been kicked off

   ![Workflows](https://github.com/microsoft/AL-Go/assets/10775043/37f6c5b9-aaac-4cdc-b1d0-ef661cd2bfbe)

1. If you wait for the workflow to complete, you will see that it completes and one of the build artifacts are the **BCPT Test Results**

   ![BCPT Test Results](https://github.com/microsoft/AL-Go/assets/10775043/cb206f91-3b83-4000-987c-39faa9765695)

1. Opening the **BCPT Test Results** and inspecting the results looks like this

   ![BCPT Test Results.json](https://github.com/microsoft/AL-Go/assets/10775043/27acb70c-1ead-4832-b22a-b022c578250d)

1. Scrolling down further reveals the Performance Test Results in a table, which also indicates that if we want to set a baseline for comparing future BCPT Test Results, we need to add a `bcptBaseLine.json` file in the project folder.

   ![BCPT Test Results viewer](https://github.com/microsoft/AL-Go/assets/10775043/4b263e9e-7ec9-4101-92a7-046e7807e797)

1. After uploading a `bcptBaseLine.json`, to the project root (which is the repo root in single project repositories), another CI/CD workflow will be kicked off, which now compares the results with the baseline:

   ![With BaseLine](https://github.com/microsoft/AL-Go/assets/10775043/c00840d5-4c67-4a72-a4d9-cdebe62e54c0)

   Where negative numbers in the diff fields indicates faster execution or lower number of SQL statements than the baseline.

> \[!NOTE\]
>
> You can specify thresholds for performance testing in project settings (see [https://aka.ms/algosettings#bcptThresholds](https://aka.ms/algosettings#bcptThresholds)) or in a file called `bcptThresholds.json`, which should be located next to the `bcptBaseLine.json` file.

8. After uploading a `bcptThresholds.json` file with this content:

   ```
   {
     "durationWarning": 0,
     "durationError": 1
   }
   ```

   The CI/CD workflow now uses these thresholds for the CI/CD run:

   ![Warnings and Error](https://github.com/microsoft/AL-Go/assets/10775043/be85d4c1-c710-410d-aba3-b55de8750396)

______________________________________________________________________

[back](../README.md)
