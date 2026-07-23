# Using AL-Go for GitHub on GitHub Enterprise (GHE)

Repositories using AL-Go for GitHub are supported on **GitHub Enterprise Cloud with data residency** (also known as **GHE**, where your enterprise lives on a dedicated host like `https://<enterprise>.ghe.com`).

> [!NOTE]
> This support is for repositories **using** AL-Go for GitHub. The AL-Go for GitHub repository itself (the [microsoft/AL-Go](https://github.com/microsoft/AL-Go) development repository) is only supported on `github.com`.

## How it works

The AL-Go for GitHub templates are published on the public GitHub (`github.com`):

- [microsoft/AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE) for Per Tenant Extensions
- [microsoft/AL-Go-AppSource](https://github.com/microsoft/AL-Go-AppSource) for AppSource Apps

On `github.com`, you would normally use the **Use this template** button on one of these repositories to create your own repository. On GHE this is not possible, because:

- The source template repositories reside on `github.com`, while your destination repository lives in a **different** enterprise on a dedicated host (e.g. `https://<enterprise>.ghe.com`). The **Use this template** button can only create a repository on the same host as the template.
- Your enterprise credentials cannot be used to authenticate against or read public repositories on `github.com`, so your enterprise host has no way to pull directly from the public AL-Go templates.

This means we have to find a different way to copy a template repository from `github.com` into your enterprise. The sections below describe two methods of doing this - **manually** or **using a tool**.

## Manual approach

You can copy one of the public AL-Go templates into your enterprise using **git** and **GitHub CLI**. This mirror-clones the template repository from `github.com` and pushes it into a new repository on your enterprise host.

Replace `OWNER/REPO` with the public template (for example `microsoft/AL-Go-PTE` or `microsoft/AL-Go-AppSource`), and `ORG/REPO` and `github.mycompany.com` with your enterprise organization, repository name and host:

```pwsh
# 1. Authenticate to your enterprise host (if not already)
gh auth login --hostname github.mycompany.com

# 2. Mirror-clone the source repo (includes all branches, tags, refs)
git clone --mirror https://github.com/OWNER/REPO.git

# 3. Create the destination repo on your enterprise instance
$env:GH_HOST = "github.mycompany.com"
gh repo create ORG/REPO --private
Remove-Item Env:GH_HOST

# 4. Push everything into it
Set-Location REPO.git
git push --mirror https://github.mycompany.com/ORG/REPO.git
```

> [!NOTE]
> The mirror-clone in step 2 reads from the **public** `github.com` template, which does not require authentication. Step 3 and step 4 target your enterprise host, using the credentials you authenticated with in step 1.

## Automated approach

Instead of copying the repository manually, you can use the [algoctl](https://github.com/Freddy-DK/AL-Go/tree/main/algoctl) CLI, which performs the copy for you in a single command.

Before running the commands below, make sure that **git** and **GitHub CLI** are installed and that gh is authenticated to your GitHub enterprise host:

```pwsh
gh auth login --hostname <enterprise>.ghe.com
```

The algoctl tool uses GitHub CLI for authentication.

Install algoctl and run `createrepo`, replacing `<enterprise>` and `<org>` with your enterprise host and organization, and pointing `--templaterepo` at the public AL-Go template you want to copy:

```pwsh
dotnet tool install --global algoctl --prerelease
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<repo> --templaterepo microsoft/AL-Go-PTE
```

This creates a new repository inside your enterprise organization, seeded from the public AL-Go template. Use `microsoft/AL-Go-AppSource` as the `--templaterepo` for AppSource Apps.

## Indirect templates

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
