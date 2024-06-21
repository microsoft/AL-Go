# Dependencies #2 - Dependencies to AL-Go projects in other repositories

Many partners have a set of common helper functions, tables and other things, which they reuse in other apps.

With AL-Go for GitHub, the recommendation is to create a Common repository, which has one or more projects, which can be used in several of your other apps.

So, let's setup a single-project common repository like this. Navigate to https://aka.ms/algopte to create a new repository. Click Use this template and select Create a new repository. Select your organization as owner, specify a name and select Public.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/3ac95b12-7e51-4378-9072-d1415b9ed38d) |
|-|

Create 2 apps within the repository using the **Create a new app** workflow called **Common** and **Licensing**, using the following parameters:

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `.` |
| Name | `Common` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `60000..60099` |
| Include Sample Code | :black_square_button: |
| Direct Commit | :ballot_box_with_check: |
| Use GhTokenWorkflow | :black_square_button: |

and

| Name | Value |
| :-- | :-- |
| Use workflow from | `Branch: main` |
| Project name | `.` |
| Name | `Licensing` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `60100..60199` |
| Include Sample Code | :black_square_button: |
| Direct Commit | :ballot_box_with_check: |
| Use GhTokenWorkflow | :black_square_button: |

Leaving out the sample code in order to avoid name clashes.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ce08e813-bf5a-4814-8c56-a6f38cced01d) |
|-|

Wait for both workflows to complete.

Under **Code** locate the **app.json** file for the **Common** app and copy **id**, **name**, **publisher** and **version** to the clipboard.

Now locate the **app.json** file for the **Licensing** app and create a dependency to the **Common** app and commit the changes.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/29885e4e-072b-46d4-8b22-135adb973d48) |
|-|

Also copy the **id**, **name**, **publisher** and **version** from the **Licensing** app to the clipboard as well.

Select **Actions** and wait for the **CI/CD** workflow to complete.

Now, navigate back to your multi-project repository, which you created [here](Projects.md).

Add a dependency to the **Licensing** app from the **Common** repository, from the **mysolution.w1** app in the **W1** project.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/40d496fa-64ac-41e3-8b32-d1d33ba17a06) |
|-|

And as expected, the builds will fail.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7e7bc6c2-0783-4415-aaac-b2dea56998cf) |
|-|

In this example using the **useProjectDependencies** mechanism, but builds would also fail when using **include**.

In this workshop, I will describe two ways to to make this work.

## Using appDependencyProbingPaths

In the MySolution repository, navigate to Settings -> Secrets and Variables -> Actions and select Variables. Create a new repository variable called **ALGOREPOSETTINGS** with this content:

```json
  "appDependencyProbingPaths": [
    {
      "repo": "freddydkorg/Common",
      "release_status": "latestBuild"
    }
  ]
```

replacing **freddydkorg** with your organization name obviously.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/0ae5d283-0494-4a3d-b6a0-661092b46e09) |
|-|

> \[!NOTE\]
> Make sure you create a repository variable and not a repository secret

This setting means that all projects in this repository will download the **latest build** from **freddydkorg/Common** and a subsequent build will succeed. Go to **Actions**, select the **CI/CD** workflow, click **Run workflow** and wait for the workflow to complete.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b10c3050-dd45-47a0-8c2b-fbeb517c94c2) |
|-|

> \[!NOTE\]
> You can also define **appDependencyProbingPaths** in the settings file for individual projects (f.ex. **W1** project). This would also work when using **useProjectDependencies**.
> When using **include** however the **DK** and **US** projects would **fail** as they would **include** the source code for the **W1** project, but not the settings (i.e. the appDependencyProbingPaths).

## Using GitHub Packages

> \[!NOTE\]
> If you already added appDependencyProbingPaths, then please remove these settings before continuing, making your build fail again.

In order to use GitHub Packages for dependency resolution, we need to create an organizational secret called **GitHubPackagesContext**. The format of this secret needs to be **compressed JSON** containing two values: **serverUrl** and **token**. Example:

```json
{"token":"ghp_XXX","serverUrl":"https://nuget.pkg.github.com/freddydkorg/index.json"}
```

Where **ghp_XXX** should be replaced by a **personal access token** with permissions to **write:packages** and **freddydkorg** should be replaced by your **organization name**.

> \[!NOTE\]
> Fine-grained personal access tokens doesn't support packages at this time, you need to use classic personal access tokens.

To create a personal access token, navigate to [https://github.com/settings/tokens/new](https://github.com/settings/tokens/new), give it a name and select write:packages.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/48f7a8c5-728b-499d-ab38-1a4726b52da8) |
|-|

> \[!NOTE\]
> You can also use the BcContainerHelper function **New-ALGoNuGetContext** to create a correctly formed JSON structure.

Go to your organization settings and create an **organizational secret** called **GitHubPackagesContext** with the your secret value.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f369d7df-fed2-48e7-bf85-aa7924dd9cfa) |
|-|

Now, navigate to your **Common** repository and run the **CI/CD** Workflow. Inspect the workflow summary after completion:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/39023475-78a3-4be1-9f01-d3a476697c7f) |
|-|

Notice the **Deliver to GitHubPackages** job. By creating the **GitHubPackagesContext** secret, you have enabled Continuous Delivery to GitHub Packages.

Now, click **Code** and see that you have 2 Packages delivered from the repository:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/3fbf27fb-d0c1-442f-9221-83b1096612b0) |
|-|

Click **Packages**, which will take you to Packages in your organizational profile. All packages are stored on the organization with a link to the owning repository:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5d3f7089-7826-4651-8081-9b95d07e0e5e) |
|-|

Next, navigate to your **MySolution** repository (where you deleted the ALGOREPOSETTINGS repository variable) and run the **CI/CD** workflow and magically, all dependencies are now also resolved.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a9f12ea7-5414-441b-9e5c-c14ea803f35b) |
|-|

Looking into the logs under the **Build** step, you will find that **Resolving Dependencies** will find that it is missing the **Licensing** dependency and then, under **installing app dependencies**, it searches GitHub Packages to locate the missing dependencies (+ their dependencies)

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/d6504c55-19fc-489f-bdb5-b345f00432c2) |
|-|

and looking at packages for the organization, we will now see that there are 5 packages - 3 of them published from the MySolutions repository:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/95f989ed-1d88-4cd6-8959-25291d23d569) |
|-|

Continuous Delivery is not only GitHub Packages. Let's have a look at continuous delivery...

______________________________________________________________________

[Index](Index.md)  [next](ContinuousDelivery.md)
