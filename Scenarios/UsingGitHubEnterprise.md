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

You can copy one of the public AL-Go templates into your enterprise using **git** and **GitHub CLI**. This mirror-clones the template repository from `github.com` and pushes it into a new repository on your enterprise host.

Replace `OWNER/REPO` with the public template (for example `microsoft/AL-Go-PTE` or `microsoft/AL-Go-AppSource`), `<enterprise>.ghe.com` with your enterprise host and `ORG/REPO` with your organization/repository name:

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

## Indirect templates

If you want to use indirect templates you need to use the above technique to copy the two AL-Go template repositories to your enterprise organization - one for Per Tenant Extensions and one for AppSource Apps - based on the public AL-Go templates.

## Creating repositories based on your indirect template

Creating a repository based on your indirect template, requires you to follow the same process from earlier in this documentation, and then run Update AL-Go System Files specifying your indirect template - this step is very important.

## Update AL-Go System Files

Use Update AL-Go System Files in the template repositories to grab the latest changes from Microsoft.
