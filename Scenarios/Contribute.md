# Contributing to AL-Go

This section describes how to contribute to AL-Go. How to set up your own environment (your own set of actions and your own templates)

You can do this in two ways:
- Use a fork of AL-Go for GitHub in your own **personal GitHub account** in development mode
- Use 3 public repositories in your own **personal GitHub account** (AL-Go-PTE, AL-Go-AppSource and AL-Go-Actions, much like in production)

## Use a fork of AL-Go for GitHub in "development mode"

1. Fork the [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go) repository to your **personal GitHub account**.
2. You can optionally also create a branch in the AL-Go fork for the feature you are working on.

**https://github.com/<yourGitHubUserName>/AL-Go@<yourBranch>** can now be used as a template in your AL-Go project when running _Update AL-Go System Files_ to use the actions/workflows from this fork.

## Use 3 public repositories in "production mode"

1. Fork the [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go) repository to your **personal GitHub account**.
2. Navigate to [https://github.com/settings/tokens/new](https://github.com/settings/tokens/new) and create a new personal access token with **Full control of private repositories** and **workflow** permissions.
3. In your personal fork of AL-Go, create a New Repository Secret called **OrgPAT** with your personal access token as content. See **https://github.com/yourGitHubUserName/AL-Go/settings/secrets/actions**.
4. In your personal fork of AL-Go, navigate to **Actions**, select the **Deploy** workflow and choose **Run Workflow**.
5. Using the default settings press **Run workflow**.

Now you should have 3 new public repositories:

- [https://github.com/yourGitHubUserName/AL-Go-Actions](https://github.com/yourGitHubUserName/AL-Go-Actions)
- [https://github.com/yourGitHubUserName/AL-Go-AppSource](https://github.com/yourGitHubUserName/AL-Go-AppSource)
- [https://github.com/yourGitHubUserName/AL-Go-PTE](https://github.com/yourGitHubUserName/AL-Go-PTE)

You can optionally also create a branch in the AL-Go fork for the feature you are working on and then select that branch when running Deploy (both as **Use workflow from** and as **Branch to deploy to**).

**yourGitHubUserName/AL-Go-PTE@yourBranch** or **yourGitHubUserName/AL-Go-AppSource@yourBranch** can now be used in your AL project when running Update AL-Go System Files to use the actions/workflows from this area for your AL project.

Now you can clone these repos and work with them, fix issues etc. and when you are done with the functionality you want to contribute with, run the **Collect** workflow in your personal fork of the AL-Go repository. This collects the changes from your personal 3 repositories and creates a Pull Request against your personal fork (or commits directly)

Please ensure that all unit tests run and create a Pull Request against [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go). You are very welcome to run the end to end tests as well, but we will also run the end to end tests as part of the code review process.

> **Note**: You can also deploy to a different branch in the 3 public repositories by specifying a branch name under **Branch to deploy** to when running the **Deploy** workflow. The branch you specify in **Use workflow from** indicates which branch in **your personal fork of the AL-Go repository** you publish to the 3 repositories.

> **Note**: You can also collect from a different branch in the 3 public repositories by specifying a branch name under **Branch to collect** from when running the **Collect** workflow. The branch you specify in **Use workflow from** indicates which branch in in **your personal fork of the AL-Go repository** you want to submit the changes against.

> **Not recommended**: You can also run the deploy and collect actions personally by running the Deploy and Collect scripts in the Internal folder with a .json file as a parameter specifying which repositories to deploy to and collect from. The `fredddk.json` file in the internal folder is a sample of this.

## Unit tests
The Tests folder, in the AL-Go repository, contains a number of unit-tests and you can run these after collecting your changes from the 3 template repositories. Open Tests/runtests.ps1 in VS Code and select Run. Unit tests are quick and will run on every PR and every Push. We will be adding a lot of unit tests going forward.

## End to End tests
In the e2eTests folder, in the AL-Go repository, there are 3 types of end to end tests.
- Test-AL-Go.ps1 contains an end-2-end test scenario and is in E2E.yaml run for all combinations of Public/Private, Windows/Linux, Single/Multiproject and PTE/AppSource.
- Test-AL-Go-Upgrade.ps1 contains an end-2-end upgrade scenario and is run for all prior releases of AL-Go for GitHub to test that you can successfully upgrade that version to the latestand run CI/CD successfully.
- The scenarios folder contains a set of AL-Go scenarios, which tests specific functionality end to end. Every folder under e2eTests/scenarios, which contains a runtests.ps1 will be run as a scenario test, like:
  - UseDependencies - create a repo with multiple projects and set UseDependencies to modify CI/CD and other build workflows to build projects in the right order
  - GitHubPackages - create 3 repositories using GitHub Packages as dependency resolver and check that artifacts are built properly
  - buildModes - create a repository, set buildModes and test that generated artifacts are as expected.

In your personal fork, you can now run the end to end tests, if the following pre-requisites are available:
- You need the following secrets:
  - E2EPAT needs to be a Personal Access Token with these permissions: _admin:org, delete:packages, delete_repo, repo, workflow, write:packages_
  - AdminCenterApiCredentials needs to be the adminCenterApiCredentials as described [here](CreateOnlineDevEnv2.md).
  - LicenseFileUrl needs to be a direct download URL to a developer .bclicense file
  - InsiderSasToken needs to contain the Insider Sas Token from https://aka.ms/collaborate
- Beside the secrets, you need to have a GitHub organization setup, which will contain all the temporary repositories created by the end to end testing. This organization needs to have at least two instances of a GitHub runner registered as self-hosted (for running all private repo builds)

Run the End to end tests by running the *End to end tests* workflow and specify your organization in the corresponding field.
End to end testing will create a lot of repositories called tmpXYZ, where XYZ is a random letter combination. If End to end tests are failing, the tmp repositories are NOT removed, but can be used for troubleshooting.
You can run the *Cleanup after failed E2E* workflow to cleanup these repositories.

You can also run the end to end tests directly from VS Code, by providing the following global variables:
- $global:E2EgitHubOwner
- $global:SecureE2EPAT
- $global:SecureAdminCenterApiToken
- $global:SecureLicenseFileUrl
- $global:SecureInsiderSasToken

Where E2EgitHubOwner is of type string and the other global variables is of type SecureString.
Running end to end tests in VS Code will use your 3 deployed template repositories for running the tests.

---
[back](../README.md)
