# Dependencies to AL-Go projects in other repositories
Many partners have a set of common helper functions, tables and other things, which they reuse in other apps.

With AL-Go for GitHub, the recommendation is to create a Common repository, which has one or more projects, which can be used in several of your other apps.

So, let's setup a single-project common repository like this. Navigate to https://aka.ms/algopte to create a new repository. Click Use this template and select Create a new repository. Select your organization as owner, specify a name and select Public.

| ![image](https://user-images.githubusercontent.com/10775043/232203510-095f1f0d-e407-413d-9e17-7a3e3e43b821.png) |
|-|

Run Update **AL-Go System Files** with **microsoft/AL-Go-PTE@preview** as the template URL and **Y** in Direct COMMIT.

When upgrade is done, create 2 apps within the repository using the **Create a new app** workflow called **Common** and **Licensing**, using the following parameters:

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

| ![image](https://user-images.githubusercontent.com/10775043/232205313-3e3df750-55d3-44ac-bb27-40f84971a9a0.png) |
|-|

Wait for both workflows to complete.

Under **Code** locate the **app.json** file for the **Common** app and copy **id**, **name**, **publisher** and **version** to the clipboard.

Now locate the **app.json** file for the **Licensing** app and create a dependency to the **Common** app and commit the changes.

| ![image](https://user-images.githubusercontent.com/10775043/232205817-c0c2adef-a61f-4406-8880-5d7db55c7804.png) |
|-|

Also copy the **id**, **name**, **publisher** and **version** from the **Licensing** app to the clipboard as well.

Select **Actions** and wait for the **CI/CD** workflow to complete.

Now, navigate back to your multi-project repository, which you created [here](Projects.md).

Add a dependency to the **Licensing** app from the **Common** repository, from the **mysolution.w1** app in the **W1** project.

| ![image](https://user-images.githubusercontent.com/10775043/232206403-bd93b016-3fe5-44fa-8aae-057323735034.png) |
|-|

And as expected, the builds will fail.

| ![image](https://user-images.githubusercontent.com/10775043/232211698-943bdad0-18e8-4163-94b7-3e77a4bad486.png) |
|-|

In this example using the **include** mechanism, but builds would also fail when using **useProjectDependencies**.

In this workshop, I will describe two ways to to make this work.

## Using appDependencyProbingPaths

Now your organization variable ALGoOrgSettings, and add:

```
    "appDependencyProbingPaths": [
        {
            "repo": "freddydkorg/Common",
            "release_status": "latestBuild"
        }
    ]
```

| ![image](https://user-images.githubusercontent.com/10775043/232247041-b9e20016-b734-4a39-9f87-e28a7af9d354.png) |
|-|

This setting means that all repositories in this organization will download the **latest build** from **freddydkorg/Common** and a subsequent build will succeed.

| ![image](https://user-images.githubusercontent.com/10775043/232249808-bed9cb0c-e73d-422e-a629-1373dc128c13.png) |
|-|

If we had added the**appDependencyProbingPaths** only to the **W1** project, then the **W1** project would **succeed** and the **DK** and **US** projects **fail**. The reason for this is that we are using the **include** mechanism, which includes the source of **W1** in **DK** and **US**, but it doesn't add the **appDependencyProbingPaths** from **W1**.

## Using GitHub Packages

If you already added appDependencyProbingPaths, then please remove these settings before continuing, making your build fail again.

In order to use GitHub Packages for dependency resolution, we need to create an organizational secret called **GitHubPackagesContext**. The format of this secret needs to be **compressed JSON** containing two values: **serverUrl** and **token**. Example:
```
{"token":"ghp_XXXX","serverUrl":"https://nuget.pkg.github.com/freddydkorg/index.json"}
```

Where **ghp_XXX** should be replaced by your **personal access token** with permissions to **Packages** and **freddydkorg** should be replaced by your **organization name**.

You can also use BcContainerHelper and the function **New-ALGoNuGetContext** to create a JSON structure in the right format.

Go to your organization settings and create an **organizational secret** called **GitHubPackagesContext** with the value above.

| ![image](https://user-images.githubusercontent.com/10775043/232253023-7131dba1-1be1-4cac-8786-27715899200b.png) |
|-|

Now, navigate to your **Common** repository and run the **CI/CD** Workflow. Inspect the workflow summary after completion:

| ![image](https://user-images.githubusercontent.com/10775043/232253742-7728e4a2-587e-40fa-a547-4c95ba4e9951.png) |
|-|

Notice the **Deliver to GitHub Packages** job, by creating the **GitHubPackagesContext** secret, you have enabled Continuous Delivery to GitHub Packages.

Now, navigate to your organization and select **Packages** and you will see GitHub Packages created for the two apps in **Common**.

| ![image](https://user-images.githubusercontent.com/10775043/232253790-7aee6c91-a858-4dd9-b85c-5f22a67394b5.png) |
|-|

Next, navigate to your **MySolution** repository and run the **CI/CD** workflow and magically, all dependencies are now also resolved.

| ![image](https://user-images.githubusercontent.com/10775043/232286871-845f02ea-a59a-46e8-b720-5ff1d6927ffe.png) |
|-|

And GitHub Packages have been published for the 3 apps in MySolution as well

| ![image](https://user-images.githubusercontent.com/10775043/232286814-4d4572f3-fa14-460e-84ba-f18fa071860f.png) |
|-|

Continuous Delivery is not only GitHub Packages. Let's have a look at continuous delivery...

---
[Index](Index.md)&nbsp;&nbsp;[next](ContinuousDelivery.md)

