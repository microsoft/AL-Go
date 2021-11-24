# Contributing to AL-Go
This section describes how to contribute to AL-Go. How to setup your own environment (your own set of actions and your own templates)

1. Fork the https://github.com/microsoft/AL-Go repository to your **local GitHub account**.
2. Navigate to https://github.com/settings/tokens/new and create a new personal access token with **Full control of private repositories**
3. In your local fork of AL-Go, create a New Repository Secret called **OrgPAT** with your personal access token as content. (https://github.com/yourGitHubUserName/AL-Go/settings/secrets/actions) 
4. In your local fork of AL-Go, navigate to **Actions**, select the **Deploy** workflow and click **Run Workflow**.
5. Using the default settings press **Run workflow**.

Now you should have 3 new public repositories:

- https://github.com/yourGitHubUserName/AL-Go-Actions
- https://github.com/yourGitHubUserName/AL-Go-AppSource
- https://github.com/yourGitHubUserName/AL-Go-PTE

These URLs can be used in your AL project when running Update AL-Go System Files to use the actions/workflows from this area for your AL project.

Now you can clone these repos and work with them, fix issues etc. and when you are done with the functionality you want to contribute with, run the **Collect** workflow in your local fork of the AL-Go repository. This collects the changes from your local 3 repositories and creates a Pull Reqest against your local fork (or commits directly)

Ensure that all tests run and create a Pull Request against https://github.com/microsoft/AL-Go

> **Note**: You can also deploy to a different branch in the 3 public repositories by specifying a branch name under **Branch to deploy** to when running the **Deploy** workflow. The branch you specify in **Use workflow from** indicates which branch in **your local fork of the AL-Go repository** you publish to the 3 repositories.

> **Note**: You can also collect from a different branch in the 3 public repositories by specifying a branch name under **Branch to collect** from when running the **Collect** workflow. The branch you specify in **Use workflow from** indicates which branch in in **your local fork of the AL-Go repository** you want to submit the changes against.

> **Not recommended**: You can also run the deploy and collect actions locally by running the Deploy and Collect scripts in the Internal folder with a .json file as a parameter specifying which repositories to deploy to and collect from. The fredddk.json file in the internal folder is a sample of this.

