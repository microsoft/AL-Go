# Runners
Whenever you are running a workflow on GitHub, GitHub will need a Runner to execute the code.

GitHub supplies Windows and Linux runners which you can use, but you can also supply your own (Self Hosted runners)

---

## Self Hosted Runners
- Running on your own hardware or on a VM
  - You carry the cost for running the hardware / VM
- Not recommended for public repositories
- Auto scaling not yet supported for GitHub Actions and Azure VMs

---

## GitHub Hosted Runners vs. Self Hosted Runners
| GitHub Hosted Runners | Self Hosted Runners |
|---|---|
| No caching | Caching of artifacts and images |
| Typical build time from ~15 minutes | Typical build time from ~5 minutes |
| Zero maintenance | Some maintenance / renewal required |
| Likely enough for customer org | Likely demand for ISV/VAR orgs |
| Unlimited minutes for public repositories | Unlimited minutes for public repositories |
| Limited minutes for private repositories<br />- 2000 minutes (= 1000 Windows minutes)<br />- Enough for ~2 builds per day<br />- Additional Windows minutes | Unlimited minutes for public repositories | Unlimited minutes for private repositories |

---

[index](index.md)&nbsp;&nbsp;[previous](GetStarted.md)&nbsp;&nbsp;[next](GitHubSettings.md)