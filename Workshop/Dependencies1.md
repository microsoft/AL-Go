# Dependencies to a project in the same repository
Dependencies is a BIG topic, which is why it is handled in multiple sections in this workshop.

In general, dependencies between apps in the same repository is handles 100% automatically. AL-Go for GitHub will determine the order in which apps within the same project needs to be built and use the apps built to satisfye dependencies form other apps. You only need to add your dependencies in app.json and you are good to go.

This topic describes two ways to handle dependencies to apps within another project in the same repository. In the MySolution example from the multi-project sample [here](Projects.md), we could have a dependency from the DK and US apps to the W1 app.

Let's go ahead and add the dependencies and see what happens. Grab the **id**, **name**, **publisher** and **version** from **mysolution.w1** app and add a dependency in **mysolution.dk** and **mysolution.us**.

| ![image](https://user-images.githubusercontent.com/10775043/231805415-2e8f345c-f228-4940-9f77-9a05514bd8c0.png) |
|-|

**Stage** your changes, **Commit** them and **Sync** your changes.

Another **CI/CD** workflow will be kicked off and 2 of the jobs should fail fairly quickly.

| ![image](https://user-images.githubusercontent.com/10775043/231809668-a914793d-3e7f-4c02-9deb-13f7a1fce3e7.png) |
|-|

At this time, the error message displayed in the annotations isn't very clear - we will fix that. If you drill into the failing workflow and into the compile step, you will find the real error:

| ![image](https://user-images.githubusercontent.com/10775043/231810146-8ffe7305-da1d-4d43-ab2a-20952628632e.png) |
|-|

It cannot find my mysolution.w1 dependency, but we kind of knew that.

The recommended solution to this problem is to set a repository setting called **useProjectDependencies** to **true** and then run Update AL-Go System files.
Repository settings are in **.github/AL-Go-Settings.json**

| ![image](https://user-images.githubusercontent.com/10775043/231811594-fd29cc88-2aed-425d-bffb-eb84bfca0463.png) |
|-|

Changing the settings file will kick off another build, which also will fail.

Select **Actions**, select **Update AL-Go System Files** and click **Run workflow**. No need to change any parameters, just run the workflow.

Looking at the **Pull request** created by the **Update AL-Go System Files** workflow, we can see that all build workflows has been changed and now íncludes a **workflowDepth: 2** (instead of 1).
**Merge** the Pull request, **confirm** the merge and **delete** the temporary branch.

Open the latest merge commit and see that the structure of the **CI/CD** workflow has changed. Now it builds the W1 project first and any dependencies to apps in W1 from DK or US will be automatically located.

![image](https://user-images.githubusercontent.com/10775043/231813913-1685f87a-a822-4830-a1d3-f35f8422bcb0.png)
|-|

Looking at the artifacts produced by the build, we can see

| ![image](https://user-images.githubusercontent.com/10775043/231855006-a9f69995-200f-433b-8321-c0652289320d.png) |
|-|

where the **thisbuild** artifacts are shortlived and only used for depending projects to be able to find build artifacts from other jobs.









