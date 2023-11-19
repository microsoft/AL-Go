# Dependencies to AL-Go projects in other repositories
Many partners have a set of common helper functions, tables and other things, which they reuse in other apps.

With AL-Go for GitHub, the recommendation is to create a Common repository, which has one or more projects, which can be used in several of your other apps.

So, let's setup a single-project common repository like this. Navigate to https://aka.ms/algopte to create a new repository. Click Use this template and select Create a new repository. Select your organization as owner, specify a name and select Public.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/c79dac2e-bf52-4f3a-b86e-6a3f8cc1f392) |
|-|

Create 2 apps within the repository using the **Create a new app** workflow called **Common** and **Licensing**, using the following parameters:

| Name | Value |
| :-- | :-- |
| Project name | `.` |
| Name | `Common` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `60000..60099` |
| Include Sample Code | `N` |
| Direct COMMIT | `Y` |

and

| Name | Value |
| :-- | :-- |
| Project name | `.` |
| Name | `Licensing` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `60100..60199` |
| Include Sample Code | `N` |
| Direct COMMIT | `Y` |

Leaving out the sample code in order to avoid name clashes.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/94ec923f-9e6a-4dc4-a689-b70ab4290e55) |
|-|

Wait for both workflows to complete.

Under **Code** locate the **app.json** file for the **Common** app and copy **id**, **name**, **publisher** and **version** to the clipboard.

Now locate the **app.json** file for the **Licensing** app and create a dependency to the **Common** app and commit the changes.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f9918c5e-7363-46a1-8d3d-2a3acc7efa0c) |
|-|

Also copy the **id**, **name**, **publisher** and **version** from the **Licensing** app to the clipboard as well.

Select **Actions** and wait for the **CI/CD** workflow to complete.

Now, navigate back to your multi-project repository, which you created [here](Projects.md).

Add a dependency to the **Licensing** app from the **Common** repository, from the **mysolution.w1** app in the **W1** project.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/6149aa2f-8bbc-4b63-9190-371a27ca593d) |
|-|

And as expected, the builds will fail.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/352d9170-43dc-431f-8e3d-503caab289d7) |
|-|

In this example using the **include** mechanism, but builds would also fail when using **useProjectDependencies**.

In this workshop, I will describe two ways to to make this work.

## Using appDependencyProbingPaths

In the MySolution repository, navigate to Settings -> Secrets and Variables -> Actions and select Variables. Create a new repository variable called **ALGOREPOSETTINGS** with this content:

```json
{
    "appDependencyProbingPaths": [
        {
            "repo": "freddydkorg/Common",
            "release_status": "latestBuild"
        }
    ]
}
```

replacing **freddydkorg** with your organization name obviously.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/2dee232d-5e00-4349-a581-e02828eed4b0) |
|-|

This setting means that all projects in this repository will download the **latest build** from **freddydkorg/Common** and a subsequent build will succeed.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f1cca350-9177-4d88-adb7-572bcd14b116) |
|-|

If we had added the**appDependencyProbingPaths** only to the **W1** project, then the **W1** project would **succeed** and the **DK** and **US** projects **fail**. The reason for this is that we are using the **include** mechanism, which includes the source of **W1** in **DK** and **US**, but it doesn't add the **appDependencyProbingPaths** and other settings from **W1**.

## Using GitHub Packages

If you already added appDependencyProbingPaths, then please remove these settings before continuing, making your build fail again.

In order to use GitHub Packages for dependency resolution, we need to create an organizational secret called **GitHubPackagesContext**. The format of this secret needs to be **compressed JSON** containing two values: **serverUrl** and **token**. Example:

```json
{"token":"ghp_XXXX","serverUrl":"https://nuget.pkg.github.com/freddydkorg/index.json"}
```

Where **ghp_XXX** should be replaced by a **personal access token** with permissions to **write:packages** and **freddydkorg** should be replaced by your **organization name**.

> [!NOTE]
> Fine-grained personal access tokens doesn't support packages at this time, you need to use classic personal access tokens.

You can also use BcContainerHelper and the function **New-ALGoNuGetContext** to create a JSON structure in the right format.

Go to your organization settings and create an **organizational secret** called **GitHubPackagesContext** with the value above.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/bd7ae71b-88b8-490c-a7bf-12792c59634b) |
|-|

Now, navigate to your **Common** repository and run the **CI/CD** Workflow. Inspect the workflow summary after completion:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4a449287-2521-49b1-b5c9-e57d7047319f) |
|-|

Notice the **Deliver to GitHubPackages** job. By creating the **GitHubPackagesContext** secret, you have enabled Continuous Delivery to GitHub Packages.

Now, click **Code** and see that you have 2 Packages delivered from the repository:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/eeeb6675-f565-47c6-8582-5c94c2b26971) |
|-|

Click **Packages**, which will take you to Packages in your organizational profile. All packages are stored on the organization with a link to the owning repository:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/010defe6-b3a7-4585-9326-d0d1de303157) |
|-|

Next, navigate to your **MySolution** repository (where you deleted the ALGOREPOSETTINGS repository variable) and run the **CI/CD** workflow and magically, all dependencies are now also resolved.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4ebbc94e-a55c-47cd-a361-4e78828bed7c) |
|-|

Looking into the logs under the RunPipeline step, you will find that Resolving Dependencies will find that it is missing the Licensing dependency and then, it searches GitHub Packages to locate the missing dependencies.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/c2e48b09-7239-4cb2-881e-cd52ee5d6508) |
|-|

Continuous Delivery is not only GitHub Packages. Let's have a look at continuous delivery...

---
[Index](Index.md)&nbsp;&nbsp;[next](ContinuousDelivery.md)
