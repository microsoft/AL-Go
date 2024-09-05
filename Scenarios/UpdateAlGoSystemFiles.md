# #6 Update AL-Go system files

*Prerequisites: A completed [scenario 5](RegisterProductionEnvironment.md)*

1. Every time a CI/CD pipeline runs, it checks whether there are updates to AL-Go system files. AL-Go System files are scripts in the **.AL-Go folder** and workflows in the **.github folder**. Looking into the details of the Check for updates to Al-Go system files, usually looks like this

   ![CI/CD](https://github.com/microsoft/AL-Go/assets/10775043/8322a06e-a270-4b6d-8d92-ccc547ca4555)

1. In VS Code, try to modify the **LocalDevEnv.ps1** file, **stage** the change, **commit** and **push**.

   ![localdevenv](https://github.com/microsoft/AL-Go/assets/10775043/9eb67bc0-5460-44c5-8ede-fc8f6545a821)

1. Now there is a difference. AL-Go doesn’t support that anybody changes the AL-Go system files and will warn about these changes. The CI/CD pipeline, which kicked off when pushing the change, tells me about this.

   ![summary](https://github.com/microsoft/AL-Go/assets/10775043/8b87cf1e-5f39-487d-9b39-4ebf9a39706a)

1. To update the AL-Go system files using the Update AL-Go System Files workflow, you need to provide a secret called GHTOKENWORKFLOW containing a Personal Access Token with permissions to modify workflows. Personal access tokens are either fine-grained personal access tokens or classic personal access tokens. AL-Go for GitHub works with both if you have enabled these tokens in organization settings:

   ![orgimage](https://github.com/microsoft/AL-Go/assets/10775043/f3a26b6c-ddf6-4ab6-9e7e-2a4ac04a0828)

1. To create a **classic** personal access token, navigate to [New personal access token](https://github.com/settings/tokens/new) in a browser. Name it, set the expiration date and check the **workflow option** in the list of **scopes**. The classic tokens have access to all repositories, which you as a user have access to.

   ![newPAT](https://github.com/microsoft/AL-Go/assets/10775043/1ab9978a-37e8-423a-8f8e-5c0203f7ae00)

1. To create a **fine-grained** personal access token, navigate to [New fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) in a browser. Name it, set the expiration date and specify which repositories to include. You need to and assign **Read and Write** permissions to **Contents**, **Pull Requests** and **Workflows**. You also need to assign **Read-only** permissions to **Actions**.

   ![newFineGrained](https://github.com/microsoft/AL-Go/assets/10775043/c4618a82-3f56-4423-9ab5-15b53b4b2e95)

1. Generate the token and **copy it to the clipboard**. You won’t be able to see the token again.

1. On github.com, open **Settings** in your project and select **Secrets**. Choose the New repository secret button and create a secret called GHTOKENWORKFLOW and paste the personal access token in the value field and choose **Add secret**.

   ![PAT](https://github.com/microsoft/AL-Go/assets/10775043/7dcccca3-ec43-47ba-bffb-795332c890ad)

1. On github.com, under **Actions** in your project, select the **Update AL-Go system files** workflow and choose **Run workflow**. Leave the **Template Repository URL** blank and choose **Run workflow**.

   ![update](https://github.com/microsoft/AL-Go/assets/10775043/221e6aa1-27a8-47ea-b011-88bb6b7005b9)

1. Inspect the pull request and see that it indeed reverts your change to the `LocalDevEnv.ps1` file.

![update](https://github.com/microsoft/AL-Go/assets/10775043/c5811750-eeb2-4ce5-a8a6-9d7db620c81e)

11. By default, this workflow will apply any updates to the **workflow files (in .github\\workflows)** or **system scripts (in .AL-Go)** from the template repository used to spin up the repository. If you want to change branch or template Url, you can specify the `templateUrl@branch` when you run the workflow.

______________________________________________________________________

[back](../README.md)
