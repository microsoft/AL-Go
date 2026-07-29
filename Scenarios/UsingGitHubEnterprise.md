# Using AL-Go for GitHub on GitHub Enterprise (GHE)

Repositories using AL-Go for GitHub are supported on **GitHub Enterprise Cloud with data residency** (also known as **GHE**, where your enterprise lives on a dedicated host like `https://<enterprise>.ghe.com`).

> [!NOTE]
> This support is for repositories **using** AL-Go for GitHub. The AL-Go for GitHub repository itself (the [microsoft/AL-Go](https://github.com/microsoft/AL-Go) development repository) is only supported on `github.com`.

> [!NOTE]
> The references below will be changed from Freddy-DK/* to microsoft/* before we merge the PR
> Only reason for referring to Freddy-DK/AL-Go-PTE is that this is the only version that works with GitHub Enterprise

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

Replace `OWNER/REPO` with the public template (for example `Freddy-DK/AL-Go-PTE` or `Freddy-DK/AL-Go-AppSource`), `<enterprise>.ghe.com` with your enterprise host and `ORG/REPO` with your organization/repository name:

```pwsh
# 1. Authenticate to your enterprise host (if not already)
gh auth login --hostname <enterprise>.ghe.com

# 2. Mirror-clone the source repo (includes all branches, tags, refs)
git clone --mirror https://github.com/OWNER/REPO.git

# 3. Create the destination repo on your enterprise instance
$env:GH_HOST = "<enterprise>.ghe.com"
gh repo create ORG/REPO --private
Remove-Item Env:GH_HOST

# 4. Remove GitHub-managed pull-request refs, then push the mirror
Set-Location REPO.git
git for-each-ref --format 'delete %(refname)' refs/pull | git update-ref --stdin
git push --mirror https://<enterprise>.ghe.com/ORG/REPO.git
```

> [!NOTE]
> The mirror-clone in step 2 reads from the **public** `github.com` template, which does not require authentication. Step 3 and step 4 target your enterprise host, using the credentials you authenticated with in step 1.

## Automated approach

Instead of copying the repository manually, you can use the [algoctl](https://github.com/Freddy-DK/algoctl) CLI, which performs the copy for you in a single command.

Before running the commands below, make sure that **git** and **GitHub CLI** are installed and that gh is authenticated to your GitHub enterprise host:

```pwsh
gh auth login --hostname <enterprise>.ghe.com
```

The algoctl tool uses GitHub CLI for authentication.

Install algoctl and run `createrepo`, replacing `<enterprise>` and `<org>` with your enterprise host and organization, and pointing `--templaterepo` at the public AL-Go template you want to copy:

```pwsh
dotnet tool install --global algoctl --prerelease
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<repo> --templaterepo Freddy-DK/AL-Go-PTE
```

This creates a new repository inside your enterprise organization, seeded from the public AL-Go template. Use `Freddy-DK/AL-Go-AppSource` as the `--templaterepo` for AppSource Apps.

## Indirect templates

If you want to use indirect templates you need to use the above techniques to copy the two AL-Go template repositories to your enterprise organization - one for Per Tenant Extensions and one for AppSource Apps - based on the public AL-Go templates. Using the [algoctl](https://github.com/Freddy-DK/AL-Go/tree/main/algoctl) CLI, this looks like:

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

Now you have two new repositories inside your enterprise organization, seeded from the public AL-Go PTE and AppSource templates.
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/1913679b-53fb-40bb-8731-ff978a5696c6" />

## Creating repositories based on your indirect template

Creating a repository based on your indirect template, requires you to follow the manual or automated approach from earlier in this documentation, and then run Update AL-Go System Files specifying your indirect template.

If you used the automated approach and specified your indirect template as your template repo, the indirect template is already setup as your template repository.

## Update AL-Go System Files

Use Update AL-Go System Files in the template repositories to grab the latest changes from Microsoft.
