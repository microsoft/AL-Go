# #6 Update AL-Go system files
*Prerequisites: A completed [scenario 5](RegisterProductionEnvironment.md)*

1. Every time a CI/CD pipeline runs, it checks whether there are updates to AL-Go system files. AL-Go System files are scripts in the **.AL-Go folder** and workflows in the **.github folder**. Looking into the details of the Check for updates to Al-Go system files, usually looks like this
![CI/CD](/Scenarios/images/6a.png)
1. In VS Code, try to modify the **LocalDevEnv.ps1** file, **stage** the change, **commit** and **push**.
![localdevenv](/Scenarios/images/6b.png)
1. Now there is a difference. AL-Go doesn’t support that anybody changes the AL-Go system files and will warn about these changes. The CI/CD pipeline, which kicked off when pushing the change, tells me about this.
![summary](/Scenarios/images/6c.png)
1. To update the AL-Go system files using the Update AL-Go System Files workflow, you need to provide a secret called GHTOKENWORKFLOW containing a Personal Access Token with permissions to modify workflows
1. In a browser, navigate to [New personal access token](https://github.com/settings/tokens/new) and create a new **personal access token**. Name it, set the expiration date and check the **workflow option** in the list of **scopes**.
![newPAT](/Scenarios/images/6d.png)
1. Generate the token and **copy it to the clipboard**. You won’t be able to see the token again.
1. On github.com, open **Settings** in your project and select **Secrets**. Choose the New repository secret button and create a secret called GHTOKENWORKFLOW and paste the personal access token in the value field and choose **Add secret**.
![PAT](/Scenarios/images/6e.png)
1. On github.com, under **Actions** in your project, select the **Update AL-Go system files** workflow and choose **Run workflow**. Leave the **Template Repository URL** blank and choose **Run workflow**.
![update](/Scenarios/images/6f.png)
1. Inspect the pull request and see that it indeed reverts your change to the `LocalDevEnv.ps1` file.
![update](/Scenarios/images/6g.png)
1. By default, this workflow will apply any updates to the **workflow files (in .github\workflows)** or **system scripts (in .AL-Go)** from the template repository used to spin up the repository. If you want to change branch or template Url, you can specify the `templateUrl@branch` when you run the workflow.
---
[back](/README.md)
