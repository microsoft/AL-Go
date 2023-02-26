# Runners
Whenever you are running a workflow on GitHub, GitHub will need a Runner to execute the code.

GitHub supplies Windows and Linux runners which you can use, but you can also supply your own (Self Hosted runners)

## Self Hosted Runners
- Running on your own hardware or on a VM
  - You carry the cost for running the hardware / VM
- Not recommended for public repositories
- Auto scaling not yet supported for GitHub Actions and Azure VMs

## GitHub Hosted Runners vs. Self Hosted Runners
| GitHub Hosted Runners | Self Hosted Runners |
|---|---|
| No caching | Caching of artifacts and images |
| Typical build time from ~15 minutes | Typical build time from ~5 minutes |
| Zero maintenance | Some maintenance / renewal required |
| Likely enough for customer org | Likely demand for ISV/VAR orgs |
| Unlimited minutes for public repositories | Unlimited minutes for public repositories |
| Limited minutes for private repositories<br />- 2000 minutes (= 1000 Windows minutes)<br />- Enough for ~2 builds per day<br />- Additional Windows minutes | Unlimited minutes for public repositories | Unlimited minutes for private repositories |

## Excercise
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
[index](index.md)&nbsp;&nbsp;[previous](GetStarted.md)&nbsp;&nbsp;[next](.md)