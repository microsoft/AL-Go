# Contributing to AL-Go

This section describes how to contribute to AL-Go. How to set up your own environment (your own set of actions and your own templates)

You can do this in two ways:

- Use a fork of AL-Go for GitHub in your own **personal GitHub account** in development mode
- Use 2 public repositories in your own **personal GitHub account** (AL-Go-PTE and AL-Go-AppSource, much like in production)

## Use a fork of AL-Go for GitHub in "development mode"

1. Fork the [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go) repository to your **personal GitHub account**.
1. You can optionally also create a branch in the AL-Go fork for the feature you are working on.

**<yourGitHubUserName>/AL-Go@<yourBranch>** can now be used as a template in your AL-Go project when running _Update AL-Go System Files_ to use the actions/workflows from this fork.

## Use 2 public repositories in "production mode"

1. Fork the [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go) repository to your **personal GitHub account**.
1. Navigate to [https://github.com/settings/tokens/new](https://github.com/settings/tokens/new) and create a new personal access token with **Full control of private repositories** and **workflow** permissions.
1. In your personal fork of AL-Go, create a New Repository Secret called **OrgPAT** with your personal access token as content. See **https://github.com/yourGitHubUserName/AL-Go/settings/secrets/actions**.
1. In your personal fork of AL-Go, navigate to **Actions**, select the **Deploy** workflow and choose **Run Workflow**.
1. Using the default settings press **Run workflow**. Select the AL-Go branch to run from and the branch to deploy to.

Now you should have 2 new public repositories:

- [https://github.com/yourGitHubUserName/AL-Go-AppSource](https://github.com/yourGitHubUserName/AL-Go-AppSource)
- [https://github.com/yourGitHubUserName/AL-Go-PTE](https://github.com/yourGitHubUserName/AL-Go-PTE)

> [!NOTE]
> Deploying to a branch called **preview** will only update the two template repositories (and use your AL-Go project with the current SHA as actions repository).

You can optionally also create a branch in the AL-Go fork for the feature you are working on and then select that branch when running Deploy (both as **Use workflow from** and as **Branch to deploy to**).

**yourGitHubUserName/AL-Go-PTE@yourBranch** or **yourGitHubUserName/AL-Go-AppSource@yourBranch** can now be used in your AL project when running Update AL-Go System Files to use the actions/workflows from this area for your AL project.

Please ensure that all unit tests run and create a Pull Request against [https://github.com/microsoft/AL-Go](https://github.com/microsoft/AL-Go). You are very welcome to run the end to end tests as well, but we will also run the end to end tests as part of the code review process.

> [!NOTE]
> You can also deploy to a different branch in the 3 public repositories by specifying a branch name under **Branch to deploy** to when running the **Deploy** workflow. The branch you specify in **Use workflow from** indicates which branch in **your personal fork of the AL-Go repository** you publish to the 3 repositories.

## Pre-Commit

In the AL-Go repository we use a number of precommit hooks to help us identify issues in the code. We run the precommit hooks locally but also as a PR check. In order to ensure this check passes please install pre-commit in your local AL-Go repository. Pre-Commit can be installed by following the instructions on https://pre-commit.com/#quick-start. Once the precommint hooks are installed you can run `pre-commit run --all-files` to verify your changes.

## Unit tests

The Tests folder, in the AL-Go repository, contains a number of unit-tests. Open Tests/runtests.ps1 in VS Code and select Run. Unit tests are quick and will run on every PR and every Push. We will be adding a lot of unit tests going forward.

## End to End tests

In the e2eTests folder, in the AL-Go repository, there are 3 types of end to end tests.

- Test-AL-Go.ps1 contains an end-2-end test scenario and is in E2E.yaml run for all combinations of Public/Private, Windows/Linux, Single/Multiproject and PTE/AppSource.
- Test-AL-Go-Upgrade.ps1 contains an end-2-end upgrade scenario and is run for all prior releases of AL-Go for GitHub to test that you can successfully upgrade that version to the latestand run CI/CD successfully.
- The scenarios folder contains a set of AL-Go scenarios, which tests specific functionality end to end. Every folder under e2eTests/scenarios, which contains a runtests.ps1 will be run as a scenario test, like:
  - UseProjectDependencies - create a repo with multiple projects and set **UseProjectDependencies** to modify CI/CD and other build workflows to build projects in the right order
  - GitHubPackages - create 3 repositories using GitHub Packages as dependency resolver and check that artifacts are built properly
  - SpecialCharacters - testing that various settings (+ publisher name and app name) can contain special national characters
  - and more...

In your personal fork, you can now run the end to end tests, if the following pre-requisites are available:

- You need to have a GitHub organization setup, which will contain all the temporary repositories created by the end to end testing. This organization needs to have at least two instances of a GitHub runner registered as self-hosted (for running all private repo builds)

- You need a GitHub App installed on **all repositories** in the GitHub organization with the following permissions:

  - Repository
    - Actions: Read / Write
    - Administration: Read / Write
    - Contents: Read / Write
    - Packages: Read / Write
    - Pages: Read / Write
    - Pull Requests: Read / Write
    - Secrets: Read / Write
    - Workflows: Read / Write

- You need the following variables:

  - **E2E_APP_ID** the app ID for the GitHub app installed on the GitHub organization used for testing

- You need the following secrets:

  - **ALGOAUTHAPP** needs to be a JSON-formatted secret containing GitHubAppClientId and PrivateKey for a GitHub App with the following repo read & write permissions: _Actions, Administration, Content, Packages, Pages, Pull Requests and Workflows_.
  - **AdminCenterApiCredentials** needs to be the adminCenterApiCredentials as described [here](CreateOnlineDevEnv2.md).
  - **E2E_PRIVATE_KEY** a private key for the GitHub app installed on the GitHub organization used for testing
  - **E2EAZURECREDENTIALS** a federated credential set up as described [here](secrets.md#federated-credential)
  - **E2E_GHPACKAGESPAT** a classic PAT with the following permissions: write:packages, delete:packages

Run the End to end tests by running the *End to end tests* workflow and specify your organization in the corresponding field.
End to end testing will create a lot of repositories called tmpXYZ, where XYZ is a random letter combination. If End to end tests are failing, the tmp repositories are NOT removed, but can be used for troubleshooting.
You can run the *Cleanup after failed E2E* workflow to cleanup these repositories.

You can also run the end to end tests directly from VS Code, by providing the following global variables:

|Variable|Type|Description|
|---|---|---|
|$global:E2EgitHubOwner| String | The GitHub owner of the test repositories (like `freddydk` or `microsoft`) |
|$global:SecureALGOAUTHAPP | SecureString | A json secret containing GitHubAppClientId and PrivateKey for a GitHub App with these repo read & write permissions: _Actions, Administration, Content, Packages, Pages, Pull Requests and Workflows_ |
|$global:SecureadminCenterApiCredentials| SecureString | Admin Center API Credentials |
|$global:SecureLicenseFileUrl| SecureString | Direct download URL to a license file |
|$global:pteTemplate| String | URL for your PTE template (like `freddyk/AL-Go-PTE@main` or `freddydk/AL-Go@main\|Templates/Per Tenant Extension` for using your AL-Go fork directly) |
|$global:appSourceTemplate| String | URL for your PTE template (like `freddyk/AL-Go-AppSource@main` or `freddydk/AL-Go@main\|Templates/AppSource App` for using your AL-Go fork directly) |
|$global:SecureAzureCredentials| SecureString | A JSON string containing the Azure_Credentials set up with [federated credentials](https://github.com/microsoft/AL-Go/blob/main/Scenarios/secrets.md#federated-credential) |
|$global:SecureGitHubPackagesToken| SecureString | A classic PAT with read/write access to GitHub packages in the organization the E2E tests are running in. |

## GitHub Codespaces

AL-Go supports developing from GitHub Codespaces. You can create codespaces by going to: [https://github.com/codespaces/new](https://github.com/codespaces/new?skip_quickstart=true&repo=413794983&ref=main). From here you can create codespace either for microsoft/AL-Go or for your fork of AL-Go.

Codespaces come pre-configured with Pre-Commit and with latest BCContainerHelper version installed.

______________________________________________________________________

[back](../README.md)
