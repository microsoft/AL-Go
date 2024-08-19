# Customizing AL-Go for GitHub

AL-Go for GitHub is a plug-and-play DevOps solution, intended to support 100% of the functionality needed by 90% of the people developing applications for Microsoft Dynamics 365 Business Central out-of-the-box.

If AL-Go functionality out-of-the-box doesn't match your needs, you really three options:

1. Customize AL-Go for GitHub to fit your needs
1. Select another managed DevOps solution
1. Create your own DevOps solution from scratch (not recommended)

Creating your own DevOps solution from scratch requires dedicated resources to develop and maintain workflows, processes etc. **This is not a small task**. There are many moving parts in a DevOps solution, which might require you to make changes to workflows and scripts over time and stay secure and having to maintain many repositories is tedious and time consuming, even when using templates and other advanced features.

Microsoft will continuously develop and maintain AL-Go for GitHub and ensure that we always use the latest versions of GitHub actions, which are under our control. Microsoft will never add dependencies to any third party GitHub action, which are not under our control.

Keeping your repositories up-to-date can be done manually or on a schedule (like Windows update really). You will be notified when an update is available and we recommend that you keep your repositories up-to-date at all time. If you make modifications to the AL-Go System Files (scripts and workflows) in your repository, in other ways than described in this document, these changes will be removed with the next AL-Go update.

> \[!TIP]
> If for some reason the updated version of AL-Go for GitHub doesn't work for you, we recommend that you file an issue [here](https://github.com/microsoft/AL-Go/issues) with a detailed description of the problem and full logs of the failing workflows. You can then revert back to the prior version of AL-Go for GitHub until the issue is resolved.
>
> It is important to get back to the mainstream version of AL-Go for GitHub as soon as the issue is resolved.

There are three ways you can customize AL-Go for GitHub to fit your needs. You can

1. customize the repository with custom scripts, workflows, jobs or steps following the guidelines below
1. create a customized repository and use this as your template repository (indirect template)
1. fork the AL-Go for GitHub and create your "own" version

> \[!CAUTION\]
> The more you customize AL-Go for GitHub, the more likely you are to be broken by future updates to AL-Go for GitHub, meaning that you will have to update your customizations to match the changes in AL-Go for GitHub.

## Customizing your repository

There are several ways you can customize your AL-Go repository and ensure that the changes you make, will survive an update of AL-Go for GitHub.

### Hide/Remove unused workflows

By adding a setting called [`unusedALGoSystemFiles`](https://aka.ms/algosettings#unusedalgosystemfiles) in your [repo settings](https://aka.ms/algosettings#settings), you can tell AL-Go for GitHub that these system files are not used. Example:

```
  "unusedALGoSystemFiles": [
    "AddExistingAppOrTestApp.yaml",
    "CreateApp.yaml",
    "CreatePerformanceTestApp.yaml",
    "CreateTestApp.yaml",
    "cloudDevEnv.ps1"
  ]
```

This setting will cause AL-Go for GitHub to remove these files during the next update. Note that if you remove files like `_BuildALGoProject.yaml`, AL-Go will obviously stop working as intended - so please use with care.

### Custom delivery

You can setup [custom delivery](https://aka.ms/algosettings#customdelivery) in order to deliver your apps to locations not supported by AL-Go for GitHub out-of-the-box, by adding a custom delivery powershell script (named `.github/DeliverTo<DeliveryTarget>.ps1`) and a context secret (called `<DeliveryTarget>Context`) formatted as compressed json, you can define the delivery functionality as you like. Example:

```powershell
Param([Hashtable] $parameters)

Get-ChildItem -Path $parameters.appsFolder | Out-Host
$context = $parameters.context | ConvertFrom-Json
Write-Host "Token Length: $($context.Token.Length)"
```

In this example the context secret is assumed to contain a Token property. Read [this](https://aka.ms/algosettings#customdelivery) for more information.

### Custom deployment

You can setup [custom deployment](https://aka.ms/algosettings#customdeployment) to environment types not supported by AL-Go for GitHub out-of-the-box. You can also override deployment functionality to environment Type `SaaS` if you like. You can add an environment called `<EnvironmentName>` and a `DeployTo<EnvironmentName>` setting, defining which environment Type should be used. Example:

```json
  "Environments": [
    "<EnvironmentName>"
  ],
  "DeployTo<EnvironmentName>": {
    "EnvironmentType": "<EnvironmentType>"
  }
```

You also need to create an AuthContext secret (called `<EnvironmentName>_AuthContext`) and a powershell script (named `.github/DeployTo<EnvironmentType>.ps1`), which defines the deployment functionality. Example:

```powershell
Param([Hashtable] $parameters)

$parameters | ConvertTo-Json -Depth 99 | Out-Host
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempPath | Out-Null
Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempPath | Out-Null
Get-ChildItem -Path $tempPath -Filter *.app | Out-Host
$authContext = $parameters.authContext | ConvertFrom-Json
Write-Host "Token Length: $($authContext.Token.Length)"
```

In this example the AuthContext secret is assumed to contain a Token property. Read [this](https://aka.ms/algosettings#customdeployment) for more information.

### Adding custom workflows

If you add new workflows to the `.github/workflows` folder, which is unknown to AL-Go for GitHub, AL-Go will leave them un-touched. These workflows needs to follow standard GitHub Actions schema (yaml) and can be triggered as any other workflows. Example:

```yaml
name: 'Create Build Tag'

on:
  workflow_run:
    workflows: [' CI/CD','CI/CD']
    types: [completed]
    branches: [ 'main' ]

run-name: "[${{ github.ref_name }}] Create build tag"

permissions: read-all

jobs:
  CreateTag:
    if: github.event.workflow_run.conclusion == 'success'
    runs-on: windows-latest
    steps:
      - name: mystep
        run: |
          Write-Host "Create tag"
```

It is recommended to prefix your workflows with `my`, `our`, your name or your organization name in order to avoid that the workflow suddenly gets overridden by a new workflow in AL-Go for GitHub. The above workflow is a real example from [here](https://github.com/microsoft/BCApps/blob/main/.github/workflows/CreateBuildTag.yaml).

> \[!CAUTION\]
> This workflow gets triggered when the CI/CD workflow has completed. Note that the name of the CI/CD workflow currently is prefixed with a space, this space will very likely be removed in the future, which is why we specify both names in this example. Obviously this workflow would break if we decide to rename the CI/CD workflow to something different.

### Adding custom scripts

You can add custom powershell scripts under the .github folder for repository scoped scripts or in the .AL-Go folder for project scoped scripts. Specially named scripts in the .AL-Go folder can override standard functionality in AL-Go for GitHub workflows. A list of these script overrides can be found [here](https://aka.ms/algosettings#customdeployment). Scripts under the .github folder can be used in custom workflows instead of using inline scripts inside the workflow.

One example of a script override is the NewBcContainer override used in the System Application project in BCApps (can be found [here](https://github.com/microsoft/BCApps/blob/main/build/projects/System%20Application/.AL-Go/NewBcContainer.ps1)). This override looks like:

```powershell
Param([Hashtable] $parameters)

$script = Join-Path $PSScriptRoot "../../../scripts/NewBcContainer.ps1" -Resolve
. $script -parameters $parameters
```

Which basically launches a script located in the script folder in the repository for creating the build container needed for building and testing the System Application.

> \[!CAUTION\]
> Script overrides will almost certainly be broken in the future. The current script overrides is very much tied to the current implementation of the `Run-AlPipeline` function in BcContainerHelper. In the future, we will move this functionality to GitHub actions and no longer depend on BcContainerHelper and Run-AlPipeline. At that time, these script overrides will have to be changed to follow the new implementation.

<a id="customALGoSystemFiles"></a>

### Adding custom workflows and/or scripts using a URL

By adding a setting called [`customALGoSystemFiles`](https://aka.ms/algosettings#customalgosystemfiles) in your [repo settings](https://aka.ms/algosettings#settings), you can tell AL-Go for GitHub that these files should be included in the update. Example:

```
  "customALGoSystemFiles": [
    {
      "Destination": ".AL-Go/",
      "Source": "https://raw.githubusercontent.com/freddydk/CustomALGoSystemFiles/main/.AL-Go/myDevEnv.ps1"
    },
    {
      "Destination": ".AL-Go/NewBcContainer.ps1",
      "Source": "https://raw.githubusercontent.com/microsoft/BCApps/main/build/scripts/NewBcContainer.ps1"
    },
    {
      "Destination": ".github/",
      "Source": "https://github.com/freddydk/CustomALGoSystemFiles/archive/refs/heads/main.zip",
      "FileSpec": "*/.github/*",
      "Recurse": true
    }
  ]
```

`customALGoSystemFiles` is an array of objects, which currently can have 4 properties:

| Property | Description | Mandatory | Default |
| :-- | :-- | :-: | :-- |
| Destination | Path in which the file should be placed. Can include the filename if the source doesn't point to a .zip file, must include a terminating / or \\ if a filename is not included. | Yes | |
| Source | URL to a either a single file or a .zip file containing custom AL-Go System Files. Must be https.  | Yes | |
| FileSpec | If the source URL points to a .zip file, this property can specify which files to include if the source URL points to a .zip file. The FileSpec can include a subfolder inside the .zip file, and must include a file name pattern.  | No | * |
| Recurse | Include all files matching the file name pattern in FileSpec from all subfolders (under a given subfolder from FileSpec) | No | true |

This setting will cause AL-Go for GitHub to include these files during the next update.

> \[!WARNING\]
> You can override existing AL-Go for GitHub system files this way, please prefix files in your repository with `my` or your organization name (except for DeployTo and DeliverTo) in order to avoid overriding future workflows from AL-Go for GitHub.

> \[!NOTE\]
> If the destination is in the .AL-Go folder, the file(s) will be copied to all .AL-Go folders in multi-project repositories.

### Adding custom jobs

You can also add custom jobs to any of the existing AL-Go for GitHub workflows. Custom jobs can depend on other jobs and other jobs can made to depend on custom jobs. Custom jobs needs to be named `CustomJob<something>`, but can specify another name to be shown in the UI. Example:

```yaml
  CustomJob-CreateBuildTag:
    name: Create Build Tag
    needs: [ Initialization, Build ]
    if: (!cancelled()) && (needs.Build.result == 'success')
    runs-on: [ ubuntu-latest ]
    steps:
      - name: Create Tag
        run: |
          Write-Host "Create Tag"

  PostProcess:
    needs: [ Initialization, Build2, Build1, Build, Deploy, Deliver, DeployALDoc, CustomJob-CreateBuildTag ]
    if: (!cancelled())
    runs-on: [ windows-latest ]
    steps:
      ...
```

Adding a custom job like this, will cause this job to run simultaneously with the deploy and the deliver jobs.

> \[!NOTE\]
> All custom jobs will be moved to the tail of the yaml file when running Update AL-Go System Files, but dependencies to/from the custom jobs will be maintained.

> \[!CAUTION\]
> Custom jobs might be broken if the customized AL-Go for GitHub workflow has been refactored and the referenced jobs have been renamed.

### Adding custom steps

You can also add custom steps to AL-Go for GitHub Workflows, but only in pre-defined anchor-points. The reason for only allowing custom steps at pre-defined anchor-points is that we want to limit the number of places where steps can be added in order to have some level of freedom to refactor, develop and maintain the AL-Go for GitHub workflows, without breaking customizations constantly.

At this time, the anchor-points where you can add custom steps are:

| Workflow | Job | Step | Before or AFter |
| :-- | :-- | :-- | :-: |
| _BuildALGoProject.yaml | BuildALGoProject | Read settings | After |
| | | Read secrets | After |
| | | Build | Before |
| | | Read secrets | After |
| | | Cleanup | Before |

The custom step needs to be named `CustomStep<something>` and if inserted in any of the specified anchor-points, it will be maintained after running Update AL-Go System Files. An example of a custom step could be a step, which modifies settings based on some business logic 

```yaml
      - name: CustomStep-ModifySettings
        run: |
          $settings = $env:Settings | ConvertFrom-Json
          $settings.artifact = Invoke-RestMethod -Method GET -UseBasicParsing -Uri "https://bca-url-proxy.azurewebsites.net/bca-url/sandbox/us?select=weekly&doNotRedirect=true"
          Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "Settings=$($$settings | ConvertTo-Json -Depth 99 -Compress)"
          Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "artifact=$($settings.artifact)"
```

> \[!TIP\]
> Create a feature request [here](https://github.com/microsoft/AL-Go/issues/new?assignees=&labels=enhancement&projects=&template=enhancement.yaml&title=%5BEnhancement%5D%3A+) with a description on where you would like additional anchor-points and what you want to use it for.

> \[!CAUTION\]
> Please be aware that changes to AL-Go for GitHub might break with future versions of AL-Go for GitHub. We will of course try to keep these breaking changes to a minimum, but the only way you can be sure to NOT be broken is by NOT customizing AL-Go for GitHub.

### Modifying workflow permissions

If any of your custom jobs require permissions, which exceeds the permissions already assigned in the workflow, then these permissions can be specified directly on the custom job.

If any of your custom steps require permissions, which exceeds the permissions already assigned in the workflow, you can modify the permissions of the workflow and assign additional permissions. AL-Go for GitHub will not allow you to remove permissions, which might be needed in other steps/jobs, but additional permissions will be included when running Update AL-Go System Files.

## Using indirect templates

If you have have customizations you want to apply to multiple repositories, you might want to consider using an indirect template. An indirect template is really just an AL-Go repository (can be customized), which you use as a template repository for your repositories. This way, you can control your scripts, jobs or steps in a central location, potentially for specific purposes.

> \[!NOTE\]
> Indirect templates can be public or private.



> \[!TIP\]
> The recommended way to create a new repository based on your indirect AL-Go template is to create a new repository based on [AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE) or [AL-Go-AppSource](https://github.com/microsoft/AL-Go-AppSource), create a GhTokenWorkflow secret and then run the `Update AL-Go System Files` workflow with your indirect template specied.




> \[!NOTE\]
> If you use the indirect template as a GitHub template, for creating the repository, then you need to re-specify the indirect Template the first time you run Update `AL-Go System Files` as the repository will be a copy of the template repository and by default point to the template repository of the indirect template as it's template repository.





## Forking AL-Go for GitHub and making your "own" **public** version

Using a fork of AL-Go for GitHub to have your "own" public version of AL-Go for GitHub gives you the maximum customization capabilities. It does however also come with the most work.

> \[!NOTE\]
> When customizing AL-Go for GitHub using a fork, your customizations are public and will be visible to everyone. For more information, [read this](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-permissions-and-visibility-of-forks).

There are two ways of forking AL-Go for GitHub. You can fork the main [AL-Go for GitHub](https://github.com/microsoft/AL-Go) repository or you can fork the template repositories [AL-Go PTE](https://github.com/microsoft/AL-Go-PTE) and/or [AL-Go-AppSource](https://github.com/microsoft/AL-Go-AppSource).

For simple changes to the templates, you can fork the template repositories and make the changes directly in your fork. Note that we do not accept any pull requests to the template repositories as they are deployed from the main AL-Go repository. We do not actually develop anything in the template repositories ourself. In the template repositories you will find a branch for every version of AL-Go we have shipped. The main branch is the latest version and the preview branch is the next version. You can customize the preview branch and/or the main branch and then use your fork as the template repository when running Update AL-Go System Files from your app repositories.

> \[!NOTE\]
> We do NOT accept pull requests to the template repositories. You need to follow the guidelines [here](Contribute.md) in order to contribute to AL-Go development.

> \[!TIP\]
> When forking the template repositories, you should include all branches in order to be able to use either the latest version of AL-Go or the preview version of AL-Go.

When forking the main [AL-Go for GitHub](https://github.com/microsoft/AL-Go) repository, you are basically developing AL-Go in the same way as we are doing in Microsoft. Please follow the guidelines [here](Contribute.md) on how to develop. This gives you maximum customization capabilities, but if your changes are not being contributed to AL-Go, then you will have to merge our changes all the time.

> \[!CAUTION\]
> We strongly suggest that you keep your changes to a minimum and that you keep your fork up-to-date with the latest changes of AL-Go for GitHub at all time.

______________________________________________________________________

[back](../README.md)
