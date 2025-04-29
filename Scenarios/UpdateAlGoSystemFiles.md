# Update AL-Go system files

*Prerequisites: A completed [scenario 5](RegisterProductionEnvironment.md)*

1. Every time a CI/CD pipeline runs, it checks whether there are updates to AL-Go system files. AL-Go System files are scripts in the **.AL-Go folder** plus scripts and workflows in the **.github folder**. Looking at the latest CI/CD workflow, we can see that updates are available.
   ![Updates available](https://github.com/user-attachments/assets/81b20bd1-2fe9-4c03-970c-74c9f92ba726)
1. In VS Code, try to modify the **LocalDevEnv.ps1** file, **stage** the change, **commit** and **push**.
   ![localdevenv](https://github.com/microsoft/AL-Go/assets/10775043/9eb67bc0-5460-44c5-8ede-fc8f6545a821)
1. Now there is an additional difference. AL-Go doesn’t support that anybody changes the AL-Go system files and will warn about these changes. The CI/CD pipeline, which kicked off when pushing the change, tells me about this.
1. To update the AL-Go system files using the Update AL-Go System Files workflow, you need to provide a secret called GHTOKENWORKFLOW. Please use [this walkthrough](./GhTokenWorkflow.md) to create this secret.
1. On github.com, under **Actions** in your project, select the **Update AL-Go system files** workflow and choose **Run workflow**. Leave the **Template Repository URL** blank and choose **Run workflow**.
   ![Update AL-Go System Files](https://github.com/user-attachments/assets/890990e3-7681-4abe-ab93-b99eab75ebbe)
1. Inspect the pull request and see that it indeed reverts your change to the `LocalDevEnv.ps1` file and removes the PowerPlatform functionality, since we do not have any PowerPlatform apps included.
   ![Inspect](https://github.com/user-attachments/assets/faf9f848-85c0-4871-9e52-1fec2e1a70b8)
1. By default, this workflow will apply any updates to the **workflow files (in .github\\workflows)** or **system scripts (in .AL-Go)** from the template repository used to spin up the repository. If you want to change branch or template Url, you can specify the `templateUrl@branch` when you run the workflow.

______________________________________________________________________

[back](../README.md)
