# Customizing AL-Go for GitHub

AL-Go for GitHub is a plug-and-play DevOps solution, intended to support 100% of the functionality needed by 90% of the people developing applications for Microsoft Dynamics 365 Business Central out-of-the-box.

If AL-Go functionality out-of-the-box doesn't match your needs, you should always start by creating a feature suggestion [here](https://github.com/microsoft/AL-Go/discussions) and see whether your needs are met by other mechanisms or required by other partners and should be part of AL-Go for GitHub.

If your feature should be part of AL-Go for GitHub, you can select to [contribute](Contribute.md) to AL-Go for GitHub yourself or wait for Microsoft or other partners to pickup your feature suggestion.

If your feature suggestion isn't accepted, you really have three options:

1. Customize AL-Go for GitHub to fit your needs
1. Select another managed DevOps solution
1. Create your own DevOps solution from scratch (not recommended)

Creating your own DevOps solution from scratch requires dedicated resources to develop and maintain workflows, processes etc. **This is not a small task**. There are many moving parts in a DevOps solution, which might require you to make changes to workflows and scripts over time and stay secure and having to maintain many repositories is tedious and time consuming, even when using templates and other advanced features.

Microsoft will continuously develop and maintain AL-Go for GitHub and ensure that we always use the latest versions of GitHub actions, which are under our control. Microsoft will never add dependencies to any third party GitHub action, which are not under our control.

Keeping your repositories up-to-date can be done manually or on a schedule (like Windows update really). You will be notified when an update is available and we recommend that you keep your repositories up-to-date at all time. If you make modifications to the AL-Go System Files (scripts and workflows) in your repository, in other ways than described in this document, these changes will be removed with the next AL-Go update.

> [!TIP]
> If for some reason the updated version of AL-Go for GitHub doesn't work for you, we recommend that you file an issue [here](https://github.com/microsoft/AL-Go/issues) with a detailed description of the problem and full logs of the failing workflows. You can then revert back to the prior version of AL-Go for GitHub until the issue is resolved.
>
> It is important to get back to the mainstream version of AL-Go for GitHub as soon as the issue is resolved.

There are three ways you can customize AL-Go for GitHub to fit your needs. You can

1. customize the repository with custom scripts, workflows or jobs following the guidelines below
1. create a customized repository and use this as your custom template repository
1. fork the AL-Go for GitHub and create your "own" version (not recommended)

> [!CAUTION]
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

If you add new workflows to the `.github/workflows` folder, which is unknown to AL-Go for GitHub, AL-Go will leave them untouched. These workflows need to follow standard GitHub Actions schema (yaml) and can be triggered as any other workflows. Example:

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

> [!CAUTION]
> This workflow gets triggered when the CI/CD workflow has completed. Note that the name of the CI/CD workflow currently is prefixed with a space, this space will very likely be removed in the future, which is why we specify both names in this example. Obviously this workflow would break if we decide to rename the CI/CD workflow to something different.

### Adding custom scripts

You can add custom powershell scripts under the .github folder for repository scoped scripts or in the .AL-Go folder for project scoped scripts. Specially named scripts in the .AL-Go folder can override standard functionality in AL-Go for GitHub workflows. A list of these script overrides can be found [here](https://aka.ms/algosettings#scriptoverrides). Scripts under the .github folder can be used in custom workflows instead of using inline scripts inside the workflow.

One example of a script override is the NewBcContainer override used in the System Application project in BCApps (can be found [here](https://github.com/microsoft/BCApps/blob/647efdacac0c0d13d726e14c89180a32cbb55cf2/build/projects/System%20Application/.AL-Go/NewBcContainer.ps1)). This override looks like:

```powershell
Param([Hashtable] $parameters)

$script = Join-Path $PSScriptRoot "../../../scripts/NewBcContainer.ps1" -Resolve
. $script -parameters $parameters
```

Which basically launches a script located in the script folder in the repository for creating the build container needed for building and testing the System Application. That script can be found [here](https://github.com/microsoft/BCApps/blob/647efdacac0c0d13d726e14c89180a32cbb55cf2/build/scripts/NewBcContainer.ps1).

> [!CAUTION]
> Script overrides will almost certainly be broken in the future. The current script overrides is very much tied to the current implementation of the `Run-AlPipeline` function in BcContainerHelper. In the future, we will move this functionality to GitHub actions and no longer depend on BcContainerHelper and Run-AlPipeline. At that time, these script overrides will have to be changed to follow the new implementation.

### Adding custom jobs

You can also add custom jobs to any of the existing AL-Go for GitHub workflows. Custom jobs can depend on other jobs and other jobs can be made to depend on custom jobs. Custom jobs need to be named `CustomJob<something>`, but can specify another name to be shown in the UI. Example:

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

> [!NOTE]
> All custom jobs will be moved to the tail of the yaml file when running Update AL-Go System Files, but dependencies to/from the custom jobs will be maintained.

> [!CAUTION]
> Custom jobs might be broken if the customized AL-Go for GitHub workflow has been refactored and the referenced jobs have been renamed. Therefore, please make sure to review the changes in AL-Go workflows when running Update AL-Go System Files.

### Custom job permissions

If any of your custom jobs require permissions, which exceeds the permissions already assigned in the workflow, then these permissions can be specified directly on the custom job.

## Using custom template repositories

If you have have customizations you want to apply to multiple repositories, you might want to consider using a custom template. A custom template is really just an AL-Go repository (which can be customized), which you use as a template repository for your repositories. This way, you can control your scripts, jobs or steps in a central location, potentially for specific purposes.

> [!NOTE]
> Custom templates can be public or private. If you are using a private custom template repository, AL-Go for GitHub will use the GhTokenWorkflow secret for downloading the template during Update AL-Go System Files and check for updates.

> [!TIP]
> The recommended way to create a new repository based on your custom AL-Go template is to create a new repository based on [AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE) or [AL-Go-AppSource](https://github.com/microsoft/AL-Go-AppSource), create a **GhTokenWorkflow** secret and then run the `Update AL-Go System Files` workflow with your custom template specified.

> [!NOTE]
> If you use the custom template as a GitHub template for creating the repository, by clicking use this template in your custom template - then you need to re-specify the custom Template the first time you run Update `AL-Go System Files` as the repository will be a copy of the template repository and by default point to the template repository of the custom template as it's template repository.

Repositories based on your custom template will notify you that changes are available for your AL-Go System Files when you update the custom template only. You will not be notified when new versions of AL-Go for GitHub is released in every repository - only in the custom template repository.

> [!WARNING]
> You should ensure that your custom template repository is kept up-to-date with the latest changes in AL-Go for GitHub.

> [!TIP]
> You can setup the Update AL-Go System Files workflow to run on a schedule to uptake new releases of AL-Go for GitHub regularly.

## Using custom template files

When using custom template repositories, often you need to add custom files that are related to AL-Go for GitHub, but are not part of the official AL-Go templates. Such files can be script overrides for certain AL-Go functionality, workflows that complement AL-Go capabilities or workflows that are easier to manage centrally.

In order to instruct AL-Go to sync such files, you need to define setting `customALGoFiles`. The setting is an object that can contain two properties: `filesToUpdate` and `filesToExclude`.

`filesToUpdate`, as the name suggests, is an array of file configurations that will instruct AL-Go which files to update. Every item in the array may contain the following properties:

- `sourcePath`: A path, relative to the template, where to look for files. If not specified the root folder is implied. _Example_: `src/scripts`.
- `filter`: A string to use for filtering in the specified source path. _Example_: `*.ps1`.
- `destinationPath`: A path, relative to repository that is being updated, where the files should be placed. _Example_: `src/templateScripts`.
- `perProject`: A boolean that indicates whether the matched files should be propagated for all available AL-Go projects. In that case, `destinationPath` is relative to the project folder. _Example_: `.AL-Go/scripts`.

`filesToExclude` is an array of file configurations that will instruct AL-Go which files to exclude (ignore) during the update. Every item in the array may contain the following properties:

- `sourcePath`: A path, relative to the template, where to look for files. If not specified the root folder is implied. _Example_: `src/scripts`.
- `filter`: A string to use for filtering in the specified source path. _Example_: `notRelevantScript.ps1`.

## Forking AL-Go for GitHub and making your "own" **public** version

Using a fork of AL-Go for GitHub to have your "own" public version of AL-Go for GitHub gives you the maximum customization capabilities. It does however also come with the most work.

> [!NOTE]
> When customizing AL-Go for GitHub using a fork, your customizations are public and will be visible to everyone. For more information, [read this](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-permissions-and-visibility-of-forks).

There are two ways of forking AL-Go for GitHub. You can fork the main [AL-Go for GitHub](https://github.com/microsoft/AL-Go) repository and develop AL-Go for GitHub like we do in Microsoft, or you can fork the template repositories [AL-Go PTE](https://github.com/microsoft/AL-Go-PTE) and/or [AL-Go-AppSource](https://github.com/microsoft/AL-Go-AppSource).

While we don't recommend forking the template repositories, we realize that it is possible for simple changes to the templates. You can fork the template repositories and make the changes directly in your fork. Note that we do not accept any pull requests to the template repositories as they are deployed from the main AL-Go repository. We do not actually develop anything in the template repositories ourself. In the template repositories you will find a branch for every version of AL-Go we have shipped. The main branch is the latest version and the preview branch is the next version. You can customize the preview branch and/or the main branch and then use your fork as the template repository when running Update AL-Go System Files from your app repositories.

> [!TIP]
> When forking the template repositories, you should include all branches in order to be able to use either the latest version of AL-Go or the preview version of AL-Go.

When forking the main [AL-Go for GitHub](https://github.com/microsoft/AL-Go) repository, you are basically developing AL-Go in the same way as we are doing in Microsoft. Please follow the guidelines [here](Contribute.md) on how to develop. This gives you maximum customization capabilities, but if your changes are not being contributed to AL-Go, then you will have to merge our changes all the time.

> [!CAUTION]
> We strongly suggest that you keep your changes to a minimum and that you keep your fork up-to-date with the latest changes of AL-Go for GitHub at all time.

______________________________________________________________________

[back](../README.md)
