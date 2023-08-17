# #13 Set up your own GitHub runner to increase build performance
*Prerequisites: An AL-Go repository setup using one of the scenarios*

When running the CI/CD workflow, the build job is by far the most time-consuming job. By adding your own GitHub Runner, which can cache the generic image, the build image and also the artifacts, the time for running the build job can become much faster.

GitHub runners can be registered for an organization (accessible for all repositories in the organization) or for a single repository.

1. Navigate to [https://github.com/organizations/{organization}/settings/actions/runners/new](https://github.com/organizations/{organization}/settings/actions/runners/new) to create a self-hosted runner for your organization. Use [https://github.com/{organization}/{repository}/settings/actions/runners](https://github.com/{organization}/{repository}/settings/actions/runners) to create a self-hosted runner for a single repository.
![Organization new runner](https://github.com/microsoft/AL-Go/assets/10775043/f09af5ee-73b5-40e3-bad1-98f0c7b0ddaa)
1. To create a self-hosted runner manually, choose Windows under Runner Image and x64 in architecture and follow the description on how to create a self-hosted runner manually, then go to step 9 to continue the configuration.
1. To create an Azure VM hosting x self-hosted runners, open a new tab and navigate to [https://aka.ms/getbuildagent](https://aka.ms/getbuildagent).
1. Enter the **Resource Group name**, **Region**, **VM Name**, **Admin Password** of your choice.
1. Enter the **number of agents** you want to create on the VM.
1. Grab the **token**, the **organization Url**, and the **Agent Url** from the Create Self-Hosted runner page, and specify **self-hosted** in labels.
![getbuildagent](https://github.com/microsoft/AL-Go/assets/10775043/959e9872-1b54-46ee-b202-ca80724334f0)
1. Select **Review and Create** and then review the deployment and choose **Create**.
1. Wait for the Azure VM creation to finalize, navigate back to see that the Runners have been registered and are ready to use.
![Runners](https://github.com/microsoft/AL-Go/assets/10775043/ba90e239-a8ee-4297-8bed-a30e3fc3db8a)
1. On the list of Runners on GitHub, choose the runner group **Default** and allow public repositories if your repository is public.
![public](https://github.com/microsoft/AL-Go/assets/10775043/9bdd01ab-ac67-44bf-bfd1-af5c5ec91364)
1. Now navigate to your project settings file (.AL-Go/settings.json) and set **gitHubRunner** to **self-hosted**.
1. Save and inspect your workflows performance increase on the second run.
1. Inspect that one of the runners pick up the workflow.
![Active](https://github.com/microsoft/AL-Go/assets/10775043/dfcd369c-ad54-427e-92d4-153afda30b53)
1. Clicking the runner reveals that the job it is running.
![Job](https://github.com/microsoft/AL-Go/assets/10775043/0ae30c22-9352-4864-a80e-81ed4ecd93e1)

## Additional info on build performance

1. Running 6 CI/CD workflows simultanously, causes 1 workflow to wait as I only had 5 runners.
![Wait](https://github.com/microsoft/AL-Go/assets/10775043/c18e4c23-4337-4747-ba67-177940175414)
1. Connecting to the runner VM and looking at utilization indicates that the VM is pretty busy and probably over-allocated when starting 5+ builds at the same time. Every build was ~50% slower than when running only 1 build.
![CPU](https://github.com/microsoft/AL-Go/assets/10775043/24fc97c0-2a70-4c24-a4e7-0193bf9df4a7)
1. Decreasing the number of runners to 4 causes the build performance to be similar to when running just 1 build.
1. Turning off real-time protection on the self-hosted runner makes builds go ~25% faster.
![Better utilization](https://github.com/microsoft/AL-Go/assets/10775043/41307197-1fa7-4586-a212-43ca73d8fd9f)

---
[back](../README.md)
