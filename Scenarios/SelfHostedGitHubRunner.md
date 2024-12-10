# #13 Set up your own GitHub runner to increase build performance

*Prerequisites: An AL-Go repository setup using one of the scenarios*

When running the CI/CD workflow, the build job is by far the most time-consuming job. By adding your own GitHub Runner, which can cache the generic image, the build image and also the artifacts, the time for running the build job can become much faster.

GitHub runners can be registered for an organization (accessible for all repositories in the organization) or for a single repository.

1. Navigate to [https://github.com/organizations/{organization}/settings/actions/runners/new](https://github.com/organizations/%7Borganization%7D/settings/actions/runners/new) to create a self-hosted runner for your organization. Use [https://github.com/{organization}/{repository}/settings/actions/runners](https://github.com/%7Borganization%7D/%7Brepository%7D/settings/actions/runners) to create a self-hosted runner for a single repository.
   ![Organization new runner](https://github.com/microsoft/AL-Go/assets/10775043/f09af5ee-73b5-40e3-bad1-98f0c7b0ddaa)
1. Now, you can either [Use the Azure VM Template to create your self-hosted runner](#use-the-azure-vm-template-to-create-your-self-hosted-runner) or you can [Create your self-hosted runner manually](#create-your-self-hosted-runner-manually)

## Use the Azure VM Template to create your self-hosted runner

1. To create an Azure VM hosting x self-hosted runners, open a new tab and navigate to [https://aka.ms/getbuildagent](https://aka.ms/getbuildagent).
1. Enter the **Resource Group name**, **Region**, **VM Name**, **Admin Password** of your choice.
1. Enter the **number of agents** you want to create on the VM.
1. Grab the **token**, the **organization Url**, and the **Agent Url** from the Create Self-Hosted runner page, and specify **self-hosted** in labels.
   ![getbuildagent](https://github.com/microsoft/AL-Go/assets/10775043/959e9872-1b54-46ee-b202-ca80724334f0)
1. Select **Review and Create** and then review the deployment and choose **Create**.
1. Wait for the Azure VM creation to finalize, navigate back to see that the Runners have been registered and are ready to use.
   ![Runners](https://github.com/microsoft/AL-Go/assets/10775043/ba90e239-a8ee-4297-8bed-a30e3fc3db8a)
1. Go to [Allow your repository access to your runners](#allow-your-repository-access-to-your-runners) to continue the configuration.

## Create your self-hosted runner manually

1. To create a self-hosted runner manually, choose Windows under Runner Image and x64 in architecture and follow the description on how to create a self-hosted runner manually
1. Make sure that the following software is installed on the computer (the suggestion in parentheses explains the mechanism used in https://aka.ms/getbuildagent)
   - Docker (getbuildagent use [this script](https://github.com/microsoft/nav-arm-templates/blob/master/InstallOrUpdateDockerEngine.ps1) to install or update Docker Engine on the Azure VM)
   - The AZ PowerShell module (getbuildagent use `Install-Module az -force`)
   - GIT (getbuildagent use `choco install git --force --params "/NoAutoCrlf"` after installing choco using `https://chocolatey.org/install.ps1`))
   - 7zip (getbuildagent use `choco install 7zip`)
   - GitHub CLI (getbuildagent use `choco install gh`)
   - PowerShell 7.4.1 (getbuildagent use `choco install pwsh -y`)
   - Microsoft Visual C++ Redistributable for Visual Studio 2015-2022 14.36.32532 (getbuildagent use `choco install vcredist140 -y`)
   - Microsoft .NET (getbuildagent use `choco install dotnet -y`)
   - Microsoft .NET SDK (getbuildagent use `choco install dotnet-sdk -y`)
   - nuget.org added as dotnet nuget source (getbuildagent use `dotnet nuget add source https://api.nuget.org/v3/index.json --name nuget.org`)

> \[!NOTE\]
> If the Deploy Reference Documentation job results in an error like [this](https://github.com/actions/upload-pages-artifact/issues/95), then you need to check your GIT installation as described in the issue.

## Allow your repository access to your runners

1. On the list of Runners on GitHub, choose the runner group **Default** and allow public repositories if your repository is public.
   ![public](https://github.com/microsoft/AL-Go/assets/10775043/9bdd01ab-ac67-44bf-bfd1-af5c5ec91364)
1. Now navigate to your repo settings file (.github/AL-Go-Settings.json) and set **gitHubRunner** to **self-hosted**.
   - Note that you can use other tags than **self-hosted** to identify special runners for GitHub jobs, or you can set gitHubRunner to "self-hosted, Windows" to ensure that a Windows version is selected if you have self-hosted linux runners as well.
1. Save and inspect your workflows performance increase on the second run.
1. Inspect that one of the runners pick up the workflow.
   ![Active](https://github.com/microsoft/AL-Go/assets/10775043/dfcd369c-ad54-427e-92d4-153afda30b53)
1. Clicking the runner reveals that the job it is running.
   ![Job](https://github.com/microsoft/AL-Go/assets/10775043/0ae30c22-9352-4864-a80e-81ed4ecd93e1)

## GitHubRunner vs. runs-on

You might have noticed that there are two settings in the repository settings file controlling which runners are selected, [GitHubRunner](https://aka.ms/algosettings#githubrunner) and [Runs-On](https://aka.ms/algosettings#runs-on).

`"runs-on"` is used for all jobs that don’t build/test your app, such as jobs that don’t require a lot of machine power or a docker container. AL-Go for GitHub supports using ubuntu-24.04 for runs-on, which is faster and cheaper than windows-latest (which is the default). Many jobs run in parallel using these runners, and we do not recommend using self-hosted runners for this type of job.

`"githubRunner"` is used for build/test jobs, which require more memory and a container.

## Additional info on build performance

1. Running 6 CI/CD workflows simultanously, causes 1 workflow to wait as I only had 5 runners.
   ![Wait](https://github.com/microsoft/AL-Go/assets/10775043/c18e4c23-4337-4747-ba67-177940175414)
1. Connecting to the runner VM and looking at utilization indicates that the VM is pretty busy and probably over-allocated when starting 5+ builds at the same time. Every build was ~50% slower than when running only 1 build.
   ![CPU](https://github.com/microsoft/AL-Go/assets/10775043/24fc97c0-2a70-4c24-a4e7-0193bf9df4a7)
1. Decreasing the number of runners to 4 causes the build performance to be similar to when running just 1 build.
1. Turning off real-time protection on the self-hosted runner makes builds go ~25% faster.
   ![Better utilization](https://github.com/microsoft/AL-Go/assets/10775043/41307197-1fa7-4586-a212-43ca73d8fd9f)

______________________________________________________________________

[back](../README.md)
