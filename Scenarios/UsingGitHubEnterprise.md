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

Run the following commands, replacing `<enterprise>` and `<org>` with your enterprise host and organization:

```pwsh
dotnet tool install --global algoctl --prerelease
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<enterprise>-PTE --templaterepo Freddy-DK/AL-Go-PTE
algoctl createrepo --repo https://<enterprise>.ghe.com/<org>/<enterprise>-AppSource --templaterepo Freddy-DK/AL-Go-AppSource
```

This creates two new repositories inside your enterprise organization, seeded from the public AL-Go PTE and AppSource templates.

## Verify the Template Repository setting

Now open the settings for both new repositories and check the **Template Repository** setting (the `templateUrl` setting), so that **Update AL-Go System Files** pulls updates from the correct location.

> [!TIP]
> Please refer to [this description](settings.md) to learn about the settings file and how you can modify default behaviors.
