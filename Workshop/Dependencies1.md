# Dependencies to a project in the same repository
Dependencies is a BIG topic, which is why it is handled in multiple sections in this workshop.

In general, dependencies between apps in the same repository are handled 100% automatically. AL-Go for GitHub will determine the order in which apps within the same project need to be built, and will use the apps built to satisfy dependencies from other apps. You only need to add your dependencies in app.json and you are good to go.

This topic describes two ways to handle dependencies to apps within another project in the same repository. In the MySolution example from the multi-project sample [here](Projects.md), we could have a dependency from the DK and US apps to the W1 app.

## useProjectDependencies
Let's go ahead and add the dependencies and see what happens. Grab the **id**, **name**, **publisher** and **version** from the **mysolution.w1** app.json and use them to add a dependency to that app into **mysolution.dk** and **mysolution.us**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/a1627453-c7c6-4877-bec7-ea322f9339dd) |
|-|

**Stage** your changes, **Commit** them and **Sync** your changes.

Another **CI/CD** workflow will be kicked off. Two of the jobs (the DK and the US apps) should fail fairly quickly as AL-Go cannot find the W1 app dependency anywhere.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/9bcfaa43-64ea-4e07-9505-ad1bd463c97c) |
|-|

At this time, the error message displayed in the annotations isn't very clear - we will fix that. If you drill into the failing workflow and into the compile step, you will find the real error:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/23685295-5ce3-4b08-8850-f342407316ea) |
|-|

It cannot find the mysolution.w1 app on which the two other apps depend, but we kind of knew that.

The recommended solution to this problem is to set a repository setting called **useProjectDependencies** to **true** and then run Update AL-Go System files.
Repository settings are in **.github/AL-Go-Settings.json**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/627a68a3-2d0e-4525-a7ff-88f901d786c0) |
|-|

Changing the settings file will kick off another build, which also will fail.

To address that failure, select **Actions**, select **Update AL-Go System Files** and click **Run workflow**. No need to change any parameters, just run the workflow.

Looking at the **Pull request** created by the **Update AL-Go System Files** workflow, we can see that all build workflows have been changed and now ínclude a **workflowDepth: 2** (instead of 1).

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/12758ae3-2e11-46ee-ae09-9bc186887e84) |
|-|

**Merge** the Pull request, **confirm** the merge and **delete** the temporary branch. Open the latest merge commit and see that the structure of the **CI/CD** workflow has changed. Now it builds the W1 project first and dependencies from the apps DK or US that are found in W1 will be automatically located.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5edbc124-9d09-4cad-9d1b-da4257ea065b) |
|-|

Looking at the artifacts produced by the build, we can see

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/b3d1e1aa-356a-405e-8001-07214cc3d71d) |
|-|

The **thisbuild** artifacts are shortlived - they are only there so that **depending projects** can find build artifacts from other jobs in the same workflow.

## include
The other mechanism is to *include* the dependency projects in the project we are building. This is done by using the project setting **appDependencyProbingPaths**, which specifies where to search for dependencies in general.

If you already set up **useProjectDependencies**, please remove this setting from **.github/AL-Go-Settings.json** and run **Update AL-Go System Files** to get back to a situation where AL-Go cannot locate the **mysolution.w1** dependency.

Now, modify **DK/.AL-Go/settings.json** and **US/.AL-Go/settings.json** by adding this property

```json
  "appDependencyProbingPaths": [
    {
      "repo": ".",
      "release_status": "include",
      "projects": "W1"
    }
  ]
```

Specifying a **"."** in **repo**, means to search in the same repository for the depdency. **Release_status** **include** means that AL-Go will include the actual source from the dependent project instead of downloading just a specific build. **Stage** the changes, **Commit** them, and **Sync**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/27fdeee6-3f5e-4d16-a4c9-e34001d2e26e) |
|-|

The **CI/CD** workflow runs again and you can observe that all the builds finish successfully.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/79aebe82-31b8-4b3b-a149-b75827035597) |
|-|

A look at the log reveals that it adds the **mysolution.w1** folder to the list of folders it needs to build for this job, as it checks **appDependencyProbingPaths**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/54eb7e63-bd5c-425d-bf5b-792ffe608853) |
|-|

**Note** that this implies that **mysolution.w1** will be compiled three times, and each project will contain its own copy of that app. The apps will be the same, but they will have different package IDs.

---
[Index](Index.md)&nbsp;&nbsp;[next](Dependencies2.md)
