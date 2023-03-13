# Excercise: Create Self-Hosted Runners
Create self-hosted runners to improve build performance.

## Video
Watch a video of the excercise [here](https://youtu.be/nTCbCsU-_U8)

## Steps
- Create a self-hosted runner on your laptop
  - In a browser, navigate to your organizational settings
Click Actions ->Runners -> New runner
  - With Windows and x64 selected run the code lines from the script in a PowerShell session
  - Open a command prompt and run the configure lines in that
  - Your agent is now ready to serve you
- Create an Azure VM with a runner (Azure Subscription required)
  - In a browser, navigate to https://aka.ms/getbuildagent
  - Enter resource group, region, Vm Name, Admin Password
  - Enter token, organization and agent url from the above sample
  - Press Review + Create, when the deployment is complete, the agent will be ready to serve you
  - Hourly price ~$0,25
- We will remove both after the workshop

---
[index](index.md)&nbsp;&nbsp;[previous](CreateYourFirstRepo.md)&nbsp;&nbsp;[next](UseSelfHostedRunners.md)