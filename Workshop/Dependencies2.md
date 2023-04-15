# Dependencies to AL-Go projects in other repositories
Many partners have a set of common helper functions, tables and other things, which they reuse in other apps.

With AL-Go for GitHub, the recommendation is to create a Common repository, which has one or more projects, which can be used in several of your other apps.

So, let's setup a single-project common repository like this. Navigate to https://aka.ms/algopte to create a new repository. Click Use this template and select Create a new repository. Select your organization as owner, specify a name and select Public.

| ![image](https://user-images.githubusercontent.com/10775043/232203510-095f1f0d-e407-413d-9e17-7a3e3e43b821.png) |
|-|

And create 2 apps within the repository using the **Create a new app** workflow called **Common** and **Licensing**, using the following parameters:

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

And as expected, the builds will fail

| ![image](https://user-images.githubusercontent.com/10775043/232211698-943bdad0-18e8-4163-94b7-3e77a4bad486.png) |
|-|

In this example using the **include** mechanism, but also when using **useProjectDependencies**.
Now modify the **W1/.AL-Go/settings.json** and add an **appDependencyProbingPath** to the common repo:

| ![image](https://user-images.githubusercontent.com/10775043/232215466-427851f0-0b94-417e-b5e5-858bb62a12e9.png) |
|-|

Inspecting the build after this, will reveal that the W1 project succeeds and the DK and US projects fail. The reason for this is that we are using the **include** mechanism, which includes the source of W1 in DK and US, but it doesn't add the appDependencyProbingPaths from W1.









### Add dependency from mysolution.w1 to licensing

### cannot build

### Add appDependencyProbingPaths to AlGoOrgSettings


### add GitHubPackagesContext to secrets

### run CI/CD in common

### run CI/CD in mysolution - magic


There is more to dependencies later, but let's investigate what actually happened when you adding the GitHubPackagesContext secret?

You enabled continuous delivery - let's have a look at continuous delivery...

---
[Index](Index.md)&nbsp;&nbsp;[next](ContinuousDelivery.md)

