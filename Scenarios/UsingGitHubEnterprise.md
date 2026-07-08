# Using AL-Go for GitHub on GitHub Enterprise (GHE)

Repositories using AL-Go for GitHub are supported on **GitHub Enterprise Cloud with data residency** (also known as **GHE**, where your enterprise lives on a dedicated host like `https://<enterprise>.ghe.com`).

> [!NOTE]
> This support is for repositories **using** AL-Go for GitHub. The AL-Go for GitHub repository itself (the [microsoft/AL-Go](https://github.com/microsoft/AL-Go) development repository) is only supported on `github.com`.

## How it works

On GHE, the host names differ from the public GitHub, and AL-Go uses the standard GitHub Actions environment variables to target the correct host:

- `GITHUB_SERVER_URL` - e.g. `https://<enterprise>.ghe.com` (instead of `https://github.com`)
- `GITHUB_API_URL` - e.g. `https://<enterprise>.ghe.com/api/v3` (instead of `https://api.github.com`)

Because the AL-Go actions and workflows now derive all GitHub hosts from these variables, no manual configuration of host names is required inside your repositories.

## Recommended approach

The recommended approach is to create two indirect template repositories inside your enterprise organization - one for Per Tenant Extensions and one for AppSource Apps - based on the public AL-Go templates, using the [algoctl](https://github.com/Freddy-DK/AL-Go/tree/main/algoctl) CLI.

Before running the commands below, make sure that **git** and **GitHub CLI** are installed and that gh is authenticated to your GitHub enterprise org:

```pwsh
gh auth login --hostname <enterprise>.ghe.com
```

The algoctl tool uses GitHub CLI for authentication.

Run the following commands, replacing `<enterprise>` and `<org>` with your enterprise host and organization:

```pwsh
dotnet tool install --global algoctl --prerelease
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<enterprise>-PTE --templaterepo Freddy-DK/AL-Go-PTE
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<enterprise>-AppSource --templaterepo Freddy-DK/AL-Go-AppSource
```
<img width="1285" height="799" alt="image" src="https://github.com/user-attachments/assets/0c83b7e7-be79-4834-a010-38683f61d8af" />

This creates two new repositories inside your enterprise organization, seeded from the public AL-Go PTE and AppSource templates.
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/1913679b-53fb-40bb-8731-ff978a5696c6" />

## Verify the Template Repository setting

Now open the settings for both new repositories and put a checkmark in the **Template Repository** setting, which enables you to use these repositories as your enterprise templates:
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/f6ff984e-7cc2-4922-b88d-e99611950ae2" />

## Create your repositories

Use the *Use This Template* button to create a new repository in your enterprise organization:
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/8d52b807-2c53-4987-994a-1bb514d45d62" />

## Update AL-Go System Files

Use Update AL-Go System Files in the template repositories to grab the latest changes from Microsoft.

Use Update AL-Go System Files in your repositories to grab the latest changes from your template repositories.
