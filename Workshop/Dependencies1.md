# Dependencies #1 - Dependencies to a project in the same repository

Dependencies is a BIG topic, which is why it is handled in multiple sections in this workshop.

In general, dependencies between apps in the same project are handled 100% automatically. AL-Go for GitHub will determine the order in which apps within the same project need to be built, and will use the apps built to satisfy dependencies from other apps.

This means that in a single project repository, you only need to add your dependencies in app.json and you are good to go.

This topic describes two ways to handle dependencies to apps within another project in the same repository. In the MySolution example from the multi-project sample [here](Projects.md), we could have a dependency from the DK and US apps to the W1 app.

## useProjectDependencies

Let's go ahead and add the dependencies and see what happens. Grab the **id**, **name**, **publisher** and **version** from the **mysolution.w1/app.json** and use them to add a dependency to that app into **mysolution.dk/app.json** and **mysolution.us/app.json**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/ecab7ae7-f113-4df4-999e-d5cad6baac63) |
|-|

**Stage** your changes, **Commit** them and **Sync** your changes.

Another **CI/CD** workflow will be kicked off. Two of the jobs (the DK and the US apps) should fail fairly quickly as AL-Go cannot find the W1 app dependency anywhere.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/66230407-bbdd-4b30-bf89-6ebdcbe9d3a2) |
|-|

It cannot find the mysolution.w1 app on which the two other apps depend, but we kind of knew that.

The recommended solution to this problem is to set a repository setting called **useProjectDependencies** to **true** and then run Update AL-Go System Files.

Repository settings are in **.github/AL-Go-Settings.json**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/eb63bb7d-e830-4abd-9158-1ad01e8e9c5e) |
|-|

Changing the settings file will kick off another build, which also will fail.

Now, select **Actions**, select **Update AL-Go System Files** and click **Run workflow**. No need to change any parameters, just run the workflow.

Looking at the **Pull request** created by the **Update AL-Go System Files** workflow, we can see that all build workflows have been changed and now ínclude a **workflowDepth: 2** (instead of 1).

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f63124b5-0f16-4da1-b6e4-208da617c1a7) |
|-|

**Merge** the Pull request, **confirm** the merge and **delete** the temporary branch. Open the latest merge commit and see that the structure of the **CI/CD** workflow has changed. Now it builds the W1 project first and dependencies from the apps DK or US that are found in W1 will be automatically located.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/22328924-3c49-4295-bf5d-32cf3509241c) |
|-|

> \[!NOTE\]
> It isn't necessary to update AL-Go System files every time you change or add dependencies, but you will need to run the upgrade code every time you change the workflow dependency depth.

Looking at the artifacts produced by the build, we can see

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/97f24f75-7483-4ec6-a1d9-7fff2bacab80) |
|-|

> \[!NOTE\]
> The **thisbuild** artifacts are shortlived - they are only there so that **depending projects** can find build artifacts from other jobs in the same workflow.

## include

The other mechanism is to *include* the dependency projects in the project we are building. This is done by using the project setting **appDependencyProbingPaths**, which specifies where to search for dependencies in general.

> \[!NOTE\]
> If you already set up **useProjectDependencies**, please remove this setting from **.github/AL-Go-Settings.json**. You don't need to run **Update AL-Go System Files** before building, but you will be notified to do so when building.

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

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/8d70b96d-2b6f-4cf0-80cc-a34dfdede60b) |
|-|

The **CI/CD** workflow runs again and you can observe that all the builds finish successfully.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1b90eea9-258a-451e-9564-e31916ee550d) |
|-|

A look at the log reveals that it adds the **mysolution.w1** folder to the list of folders it needs to build for this job, as it checks **appDependencyProbingPaths**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/295a32fd-1048-44f1-975f-22a761040ba3) |
|-|

> \[!NOTE\]
> This implies that **mysolution.w1** will be compiled three times, and each project will contain its own copy of that app. The apps will be the same, but they will have different package IDs.

______________________________________________________________________

[Index](Index.md)  [next](Dependencies2.md)
